import 'dart:convert';
import 'dart:typed_data';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:http/http.dart' as http;

import '../capture/pipeline.dart';
import '../data/database.dart';
import '../data/repo.dart';
import 'backup.dart';
import 'sheet_io.dart';
import 'sheets_sync.dart';

/// Chỉ xin drive.file + drive.appdata: app chỉ thấy file nó tạo (mục 6).
const googleScopes = [drive.DriveApi.driveFileScope, drive.DriveApi.driveAppdataScope];

/// OAuth client ID do nhà phát triển đăng ký trên Google Cloud, truyền lúc build:
/// --dart-define=GOOGLE_WEB_CLIENT_ID=... (web) và GOOGLE_SERVER_CLIENT_ID=... (Android, là client "Web application").
const _webClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
const _serverClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

bool get googleConfigured => kIsWeb ? _webClientId.isNotEmpty : _serverClientId.isNotEmpty;

const _keepBackups = 30;

class GoogleService {
  final AppDb db;
  final Repo repo;
  final CapturePipeline pipeline;
  GoogleService(this.db, this.repo, this.pipeline);

  bool _initialized = false;
  http.Client? _client;

  Future<void> _init() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize(
      clientId: kIsWeb ? _webClientId : null,
      serverClientId: kIsWeb ? null : _serverClientId,
    );
    _initialized = true;
  }

  /// `interactive`: chỉ true khi người dùng vừa bấm nút (luồng OAuth cần tương tác).
  Future<http.Client?> _authClient({bool interactive = false}) async {
    if (_client != null) return _client;
    if (!googleConfigured) return null;
    await _init();
    final authz =
        await GoogleSignIn.instance.authorizationClient.authorizationForScopes(googleScopes) ??
        (interactive ? await GoogleSignIn.instance.authorizationClient.authorizeScopes(googleScopes) : null);
    if (authz == null) return null;
    return _client = authz.authClient(scopes: googleScopes);
  }

  Future<bool> get connected async => await db.getSetting('sheets_id') != null;

  /// Kết nối lần đầu: xin quyền, tạo Sheet nếu chưa có (US-04 AC1).
  Future<void> connect() async {
    final c = await _authClient(interactive: true);
    if (c == null) throw StateError('Chưa cấp quyền Google');
    if (await db.getSetting('sheets_id') == null) {
      final (id, tabIds) = await createSpreadsheet(sheets.SheetsApi(c), drive.DriveApi(c));
      await db.setSetting('sheets_id', id);
      await db.setSetting('sheets_tab_ids', jsonEncode(tabIds));
    }
  }

  Future<void> disconnect() async {
    _client?.close();
    _client = null;
    if (_initialized) await GoogleSignIn.instance.disconnect();
    for (final k in ['sheets_id', 'sheets_tab_ids', 'sheets_last_sync']) {
      await (db.delete(db.settings)..where((s) => s.key.equals(k))).go();
    }
  }

  Future<String?> sheetUrl() async {
    final id = await db.getSetting('sheets_id');
    return id == null ? null : 'https://docs.google.com/spreadsheets/d/$id';
  }

  Future<SheetsSync?> _syncer() async {
    final id = await db.getSetting('sheets_id');
    final c = await _authClient();
    if (id == null || c == null) return null;
    final tabIds = Map<String, int>.from(jsonDecode(await db.getSetting('sheets_tab_ids') ?? '{}'));
    return SheetsSync(db, repo, GoogleSheetIO(sheets.SheetsApi(c), id, tabIds), pipeline: pipeline);
  }

  /// Đồng bộ nếu đã kết nối; null nếu chưa kết nối hoặc chưa có quyền (không làm phiền người dùng).
  Future<SyncResult?> sync({required Set<String> whitelist, required bool autoConfirm}) async {
    final s = await _syncer();
    if (s == null) return null;
    try {
      return await s.run(whitelist: whitelist, autoConfirm: autoConfirm);
    } on sheets.DetailedApiRequestError catch (e) {
      if (e.status == 401 || e.status == 403) _client = null; // token hết hạn → lần sau xin lại
      rethrow;
    }
  }

  Future<void> resolve(SyncConflict c, {required bool keepApp}) async => (await _syncer())?.resolveConflict(c, keepApp: keepApp);

  Future<void> restoreToSheet(String txnId) async {
    // Đánh dấu cần đẩy lại → lần đồng bộ sau sẽ append dòng.
    await db
        .into(db.syncLog)
        .insert(SyncLogCompanion.insert(entity: 'transaction', entityId: txnId, op: 'update', changedAt: DateTime.now()));
  }

  // ---------------- Sao lưu Drive appDataFolder ----------------

  Future<drive.DriveApi?> _drive({bool interactive = false}) async {
    final c = await _authClient(interactive: interactive);
    return c == null ? null : drive.DriveApi(c);
  }

  Future<void> uploadBackup(Uint8List bytes, {bool interactive = true}) async {
    final api = await _drive(interactive: interactive);
    if (api == null) throw StateError('Chưa kết nối Google');
    final name = 'vr-${DateTime.now().toUtc().toIso8601String().replaceAll(':', '-')}.vrbackup';
    await withBackoff(
      () => api.files.create(
        drive.File(name: name, parents: ['appDataFolder']),
        uploadMedia: drive.Media(Stream.value(bytes), bytes.length, contentType: 'application/octet-stream'),
      ),
    );
    // Giữ 30 bản mới nhất.
    final all = await listBackups(interactive: interactive);
    for (final f in all.skip(_keepBackups)) {
      await withBackoff(() => api.files.delete(f.id!));
    }
  }

  Future<List<drive.File>> listBackups({bool interactive = true}) async {
    final api = await _drive(interactive: interactive);
    if (api == null) return [];
    final r = await withBackoff(
      () => api.files.list(
        spaces: 'appDataFolder',
        orderBy: 'createdTime desc',
        pageSize: 100,
        $fields: 'files(id,name,createdTime,size)',
      ),
    );
    return r.files ?? [];
  }

  Future<Uint8List> downloadBackup(String fileId) async {
    final api = (await _drive(interactive: true))!;
    final media = await withBackoff(() => api.files.get(fileId, downloadOptions: drive.DownloadOptions.fullMedia)) as drive.Media;
    final bytes = BytesBuilder();
    await for (final chunk in media.stream) {
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  /// Sao lưu tự động hằng ngày (chỉ khi đã bật sao lưu và đã kết nối; im lặng nếu thiếu quyền).
  Future<bool> autoBackupIfDue(List<int>? dk) async {
    final env = await db.getSetting('backup_envelope');
    if (dk == null || env == null || await _drive() == null) return false;
    final last = DateTime.tryParse(await db.getSetting('backup_last') ?? '');
    if (last != null && DateTime.now().difference(last) < const Duration(hours: 24)) return false;
    await uploadBackup(await BackupCrypto.encryptFile(dk, env, await DbSnapshot(db).export()), interactive: false);
    await db.setSetting('backup_last', DateTime.now().toIso8601String());
    return true;
  }
}

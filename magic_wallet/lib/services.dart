import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'capture/parser.dart';
import 'capture/pipeline.dart';
import 'core/money.dart';
import 'core/periods.dart';
import 'data/database.dart';
import 'data/repo.dart';
import 'reports/report.dart';
import 'sync/google.dart';

/// Cầu nối tới module gốc Android (NotificationListenerService). Nền tảng khác không có → bỏ qua êm.
class NativeCapture {
  static const _ch = MethodChannel('magic_wallet/capture');
  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<T?> _call<T>(String m, [Object? args]) async {
    if (!supported) return null;
    try {
      return await _ch.invokeMethod<T>(m, args);
    } on MissingPluginException {
      return null;
    }
  }

  /// Lấy và xoá hàng đợi thông báo thô do service ghi lại.
  static Future<List<Map<String, dynamic>>> takeQueue() async {
    final raw = await _call<String>('takeQueue') ?? '';
    return [
      for (final line in const LineSplitter().convert(raw))
        if (line.trim().isNotEmpty) Map<String, dynamic>.from(jsonDecode(line)),
    ];
  }

  static Future<void> setWhitelist(Set<String> pkgs) => _call('setWhitelist', pkgs.toList());
  static Future<bool> listenerEnabled() async => await _call<bool>('isListenerEnabled') ?? false;
  static Future<void> openListenerSettings() => _call('openListenerSettings');

  /// FLAG_SECURE: chặn chụp màn hình và che nội dung trong trình chuyển app (10.1).
  static Future<void> setSecure(bool on) => _call('setSecure', on);
}

class Notifier {
  final _plugin = FlutterLocalNotificationsPlugin();
  static const _details = NotificationDetails(
    android: AndroidNotificationDetails('main', 'Ví Ma Thuật', channelDescription: 'Giao dịch, ngân sách, báo cáo'),
    iOS: DarwinNotificationDetails(),
  );
  bool _ready = false;

  Future<void> init({void Function(String? payload)? onTap}) async {
    if (kIsWeb) return; // shortcut: web chưa có thông báo hệ thống; cần thì dùng Notification API của trình duyệt.
    tzdata.initializeTimeZones();
    // shortcut: cố định múi giờ Việt Nam; người dùng ở nước ngoài cần thêm flutter_timezone.
    tz.setLocalLocation(tz.getLocation('Asia/Ho_Chi_Minh'));
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (r) => onTap?.call(r.payload),
    );
    _ready = true;
  }

  Future<void> requestPermission() async {
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  Future<void> show(int id, String title, String body, {String? payload}) async {
    if (!_ready) return;
    await _plugin.show(id: id, title: title, body: body, notificationDetails: _details, payload: payload);
  }

  /// Báo cáo tuần tối Chủ nhật 20:00, báo cáo tháng 8:00 ngày 1 (7.3).
  Future<void> scheduleReports() async {
    if (!_ready) return;
    final now = tz.TZDateTime.now(tz.local);
    var sunday = tz.TZDateTime(tz.local, now.year, now.month, now.day, 20);
    while (sunday.weekday != DateTime.sunday || sunday.isBefore(now)) {
      sunday = sunday.add(const Duration(days: 1));
    }
    await _plugin.zonedSchedule(
      id: 9001,
      scheduledDate: sunday,
      notificationDetails: _details,
      title: 'Báo cáo tuần đã sẵn sàng',
      body: 'Xem tuần này bạn tiêu bao nhiêu, vào đâu.',
      payload: 'report:week',
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
    final first = tz.TZDateTime(tz.local, now.month == 12 ? now.year + 1 : now.year, now.month % 12 + 1, 1, 8);
    await _plugin.zonedSchedule(
      id: 9002,
      scheduledDate: first,
      notificationDetails: _details,
      title: 'Báo cáo tháng đã sẵn sàng',
      body: 'Tổng kết tháng vừa qua và gợi ý ngân sách tháng mới.',
      payload: 'report:month',
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dayOfMonthAndTime,
    );
  }
}

/// Mọi dịch vụ của app, khởi tạo một lần.
class Services {
  final AppDb db;
  final Repo repo;
  final InstitutionCatalog catalog;
  final CapturePipeline pipeline;
  final GoogleService google;
  final Notifier notifier;
  final FlutterSecureStorage secure;
  Services._(this.db, this.repo, this.catalog, this.pipeline, this.google, this.notifier, this.secure);

  static Services? _instance;
  static Services get I => _instance!;

  static Future<Services> init({bool headless = false}) async {
    if (_instance != null) return _instance!;
    const secure = FlutterSecureStorage();
    // Khoá DB 256-bit sinh trên máy, giữ trong Keystore/Keychain (10.1).
    var key = await secure.read(key: 'db_key');
    if (key == null) {
      final r = Random.secure();
      key = List.generate(32, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await secure.write(key: 'db_key', value: key);
    }
    final db = AppDb.open(key);
    final repo = Repo(db);
    final catalog = InstitutionCatalog.fromJson(await rootBundle.loadString('assets/institutions.json'));
    final pipeline = CapturePipeline(db, repo, catalog);
    final s = Services._(db, repo, catalog, pipeline, GoogleService(db, repo, pipeline), Notifier(), secure);
    await s.notifier.init();
    await repo.purgeExpired(DateTime.now());
    final created = await repo.runRecurring(DateTime.now());
    if (created > 0) {
      await s.notifier.show(3, 'Hóa đơn định kỳ đến hạn', 'Có $created giao dịch định kỳ chờ bạn duyệt.', payload: 'pending');
    }
    if (!headless) await s.notifier.scheduleReports();
    return _instance = s;
  }

  // ---------------- Cài đặt ----------------

  Future<CalendarPrefs> prefs() async => CalendarPrefs(
    weekStart: int.tryParse(await db.getSetting('week_start') ?? '') ?? DateTime.monday,
    monthStartDay: int.tryParse(await db.getSetting('month_start_day') ?? '') ?? 1,
  );

  Future<bool> flag(String key, {bool def = false}) async =>
      (await db.getSetting(key)) == null ? def : (await db.getSetting(key)) == '1';
  Future<void> setFlag(String key, bool v) => db.setSetting(key, v ? '1' : '0');

  /// Whitelist = package của các tổ chức người dùng bật + app SMS (nếu bật) + package tự thêm (US-02 AC1).
  Future<Set<String>> whitelist() async {
    final ids = Set<String>.from(jsonDecode(await db.getSetting('capture_institutions') ?? '[]'));
    final extra = Set<String>.from(jsonDecode(await db.getSetting('capture_extra_packages') ?? '[]'));
    return {
      for (final i in catalog.all)
        if (ids.contains(i.id)) ...i.packages,
      if (await flag('capture_sms')) ...catalog.smsApps,
      ...extra,
    };
  }

  Future<void> pushWhitelist() async => NativeCapture.setWhitelist(await whitelist());

  Future<Set<String>> enabledInstitutions() async =>
      Set<String>.from(jsonDecode(await db.getSetting('capture_institutions') ?? '[]'));

  Future<void> setInstitution(String id, bool on) async {
    final ids = await enabledInstitutions();
    on ? ids.add(id) : ids.remove(id);
    await db.setSetting('capture_institutions', jsonEncode(ids.toList()));
    await pushWhitelist();
  }

  Future<void> enableInstitution(String id) => setInstitution(id, true);

  /// Dòng dữ liệu tự tính lại mỗi khi DB đổi (cho các thẻ tổng hợp).
  Stream<T> live<T>(Future<T> Function() load) async* {
    yield await load();
    await for (final _ in db.tableUpdates()) {
      yield await load();
    }
  }

  // ---------------- Thu thập ----------------

  /// Xử lý hàng đợi thông báo từ Android; trả về số giao dịch mới.
  Future<int> drainCapture() async {
    final queue = await NativeCapture.takeQueue();
    if (queue.isEmpty) return 0;
    final wl = await whitelist();
    final auto = await flag('auto_confirm');
    final cats = {for (final c in await repo.allCategories()) c.id: c};
    var n = 0;
    for (final e in queue) {
      final out = await pipeline.ingest(
        RawInput(
          source: 'notification',
          package: e['package'] ?? '',
          title: e['title'] ?? '',
          text: e['text'] ?? '',
          receivedAt: DateTime.fromMillisecondsSinceEpoch(e['postedAt'] ?? DateTime.now().millisecondsSinceEpoch),
        ),
        whitelist: wl,
        autoConfirmEnabled: auto,
      );
      if (out is Created) {
        n++;
        final t = await (db.select(db.transactions)..where((x) => x.id.equals(out.txnId))).getSingle();
        final cat = cats[t.categoryId]?.name ?? 'Chưa phân loại';
        // Mục 3.1 bước 3: "Đã ghi 45.000đ – Ăn uống. Đúng không?"
        await notifier.show(
          t.id.hashCode & 0x7fffffff,
          out.autoConfirmed ? 'Đã ghi tự động' : 'Giao dịch mới chờ duyệt',
          '${out.autoConfirmed ? 'Đã ghi' : 'Ghi'} ${formatVnd(t.amount)} – $cat. ${out.autoConfirmed ? '' : 'Đúng không?'}',
          payload: 'pending',
        );
      }
    }
    await checkBudgetAlerts();
    return n;
  }

  // ---------------- Báo cáo & ngân sách ----------------

  Future<List<BudgetStatus>> budgetStatus([DateTime? now]) async => budgetStatuses(
    budgets: await repo.watchBudgets().first,
    categories: await repo.allCategories(),
    now: now ?? DateTime.now(),
    prefs: await prefs(),
    load: repo.confirmedBetween,
  );

  /// US-03 AC1: báo khi chạm 80% và 100%, mỗi ngưỡng một lần mỗi kỳ.
  Future<void> checkBudgetAlerts() async {
    for (final b in await budgetStatus()) {
      final th = b.threshold;
      if (th == null) continue;
      final key = 'budget_alert:${b.budget.id}:${b.period.start.toIso8601String()}:$th';
      if (await db.getSetting(key) != null) continue;
      await db.setSetting(key, '1');
      final name = b.categoryName ?? 'tổng';
      await notifier.show(
        b.budget.id.hashCode & 0x7fffffff,
        th == 100 ? 'Đã vượt ngân sách $name' : 'Sắp hết ngân sách $name',
        'Đã dùng ${(b.pct * 100).round()}% (${formatVnd(b.spent)} / ${formatVnd(b.limit)}).',
        payload: 'budgets',
      );
    }
  }

  Future<Report> report(Period p) async {
    final prefs = await this.prefs();
    final prev = shiftPeriod(p, -1, prefs);
    final ly = p.type == PeriodType.month ? sameLastYear(p, prefs) : null;
    final prior = [for (var i = 1; i <= 4; i++) shiftPeriod(p, -i, prefs)];
    return buildReport(
      period: p,
      current: await repo.confirmedBetween(p.start, p.end),
      previous: await repo.confirmedBetween(prev.start, prev.end),
      sameLastYear: ly == null ? null : await repo.confirmedBetween(ly.start, ly.end),
      prior4: [for (final q in prior) await repo.confirmedBetween(q.start, q.end)],
      categories: await repo.allCategories(),
      budgets: (await budgetStatus()).where((b) => b.period.type == p.type).toList(),
      now: DateTime.now(),
    );
  }

  // ---------------- Đồng bộ ----------------

  Future<List<int>?> backupKey() async {
    final hex = await secure.read(key: 'backup_dk');
    if (hex == null) return null;
    return [for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];
  }

  Future<void> storeBackupKey(List<int> dk, String envelope) async {
    await secure.write(key: 'backup_dk', value: dk.map((b) => b.toRadixString(16).padLeft(2, '0')).join());
    await db.setSetting('backup_envelope', envelope);
  }

  /// Đồng bộ nền khi mở app/quay lại app; nuốt lỗi mạng nhưng ghi lại để màn hình Google hiển thị.
  Future<void> backgroundSync() async {
    try {
      final r = await google.sync(whitelist: await whitelist(), autoConfirm: await flag('auto_confirm'));
      if (r != null) {
        await db.setSetting('sheets_last_error', '');
        if (r.conflicts.isNotEmpty || r.missingOnSheet.isNotEmpty) {
          await db.setSetting('sheets_attention', '${r.conflicts.length + r.missingOnSheet.length}');
        }
      }
      await google.autoBackupIfDue(await backupKey());
    } catch (e) {
      await db.setSetting('sheets_last_error', '${DateTime.now().toIso8601String()} $e');
    }
  }

  /// Xoá toàn bộ dữ liệu trên máy (10.2.1: trong 2 chạm).
  Future<void> wipeAll() async {
    await db.transaction(() async {
      for (final t in db.allTables) {
        await db.delete(t).go();
      }
      await db.seedCategories();
    });
    await secure.delete(key: 'backup_dk');
    try {
      await google.disconnect();
    } catch (_) {
      // Không có mạng vẫn phải xoá xong trên máy; quyền Google thu hồi được trong tài khoản Google.
    }
  }
}

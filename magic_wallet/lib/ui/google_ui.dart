
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services.dart';
import '../sync/backup.dart';
import '../sync/google.dart';
import '../sync/sheets_sync.dart';
import 'export.dart';
import 'widgets.dart';

/// SC-10: trạng thái đồng bộ, mở Sheet, sao lưu/khôi phục.
class GoogleScreen extends StatefulWidget {
  const GoogleScreen({super.key});
  @override
  State<GoogleScreen> createState() => _GoogleScreenState();
}

class _GoogleScreenState extends State<GoogleScreen> {
  final s = Services.I;
  bool busy = false;
  SyncResult? last;

  Future<void> _run(Future<void> Function() f) async {
    setState(() => busy = true);
    try {
      await f();
    } catch (e) {
      if (mounted) toast(context, 'Lỗi: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _syncNow() => _run(() async {
    final r = await s.google.sync(whitelist: await s.whitelist(), autoConfirm: await s.flag('auto_confirm'));
    await s.db.setSetting('sheets_attention', '');
    await s.db.setSetting('sheets_last_error', ''); // lượt tay thành công thì xoá lỗi cũ của lượt nền
    setState(() => last = r);
    if (mounted && r != null) {
      toast(context, 'Đã đẩy ${r.pushed}, kéo về ${r.pulled}${r.inbox > 0 ? ', ${r.inbox} email' : ''}');
    }
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Google Sheets & sao lưu')),
      body: StreamBuilder<String?>(
        stream: s.db.watchSetting('sheets_id'),
        builder: (context, id) {
          final connected = id.data != null;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SizedBox(height: 4, child: busy ? const LinearProgressIndicator() : null),
              if (!googleConfigured)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.build_outlined),
                    title: Text('Bản build này chưa có OAuth client ID'),
                    subtitle: Text(
                      'Build lại với --dart-define=GOOGLE_SERVER_CLIENT_ID=… (Android) hoặc GOOGLE_WEB_CLIENT_ID=… (web). '
                      'Vẫn dùng đủ tính năng và sao lưu ra file ở bên dưới.',
                    ),
                  ),
                ),
              if (googleConfigured && !connected) ...[
                const Text(
                  'Dữ liệu sẽ nằm trong Google Sheet "Ví Riêng – Dữ liệu" của chính bạn. App chỉ thấy các file nó tạo ra.',
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.link),
                  label: const Text('Kết nối Google'),
                  onPressed: busy
                      ? null
                      : () => _run(() async {
                          await s.google.connect();
                          await _syncNow();
                        }),
                ),
              ],
              if (connected) ...[
                StreamBuilder<String?>(
                  stream: s.db.watchSetting('sheets_last_sync'),
                  builder: (context, t) => ListTile(
                    leading: const Icon(Icons.cloud_done_outlined),
                    title: const Text('Đã kết nối'),
                    subtitle: Text('Đồng bộ cuối: ${fmtStamp(t.data)}'),
                  ),
                ),
                StreamBuilder<String?>(
                  stream: s.db.watchSetting('sheets_last_error'),
                  builder: (context, e) => (e.data ?? '').isEmpty
                      ? const SizedBox()
                      : ListTile(
                          leading: const Icon(Icons.error_outline, color: expenseColor),
                          title: Text(e.data!, maxLines: 3),
                        ),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: busy ? null : _syncNow,
                      icon: const Icon(Icons.sync),
                      label: const Text('Đồng bộ ngay'),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Mở Sheet'),
                      onPressed: () async {
                        final u = await s.google.sheetUrl();
                        if (u != null) await launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication);
                      },
                    ),
                  ],
                ),
                if (last != null) ..._issues(last!),
                TextButton(
                  onPressed: () async {
                    if (await confirm(context, 'Ngắt kết nối? File Sheet vẫn còn trong Drive của bạn.')) {
                      await _run(s.google.disconnect);
                    }
                  },
                  child: const Text('Ngắt kết nối'),
                ),
              ],
              const Divider(height: 32),
              Text('Sao lưu mã hoá', style: Theme.of(context).textTheme.titleMedium),
              const _BackupSection(),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _issues(SyncResult r) => [
    for (final c in r.conflicts)
      Card(
        child: ListTile(
          title: const Text('Dòng bị sửa ở cả app và Sheet'),
          subtitle: Text('Sheet: ${c.sheetRow.skip(1).take(8).join(' | ')}'),
          trailing: Wrap(
            children: [
              TextButton(
                onPressed: () => _run(() async {
                  await s.google.resolve(c, keepApp: true);
                  r.conflicts.remove(c);
                }),
                child: const Text('Giữ app'),
              ),
              TextButton(
                onPressed: () => _run(() async {
                  await s.google.resolve(c, keepApp: false);
                  r.conflicts.remove(c);
                }),
                child: const Text('Giữ Sheet'),
              ),
            ],
          ),
        ),
      ),
    for (final id in r.missingOnSheet)
      Card(
        child: FutureBuilder(
          future: (s.db.select(s.db.transactions)..where((t) => t.id.equals(id))).getSingleOrNull(),
          builder: (context, t) => ListTile(
            title: const Text('Dòng đã bị xoá trên Sheet'),
            subtitle: Text(t.data == null ? id : '${dayLabel(t.data!.occurredAt)} · ${t.data!.note} · ${t.data!.amount} đ'),
            trailing: Wrap(
              children: [
                TextButton(
                  onPressed: () => _run(() async {
                    await s.repo.deleteTxn(id);
                    r.missingOnSheet.remove(id);
                  }),
                  child: const Text('Xoá trong app'),
                ),
                TextButton(
                  onPressed: () => _run(() async {
                    await s.google.restoreToSheet(id);
                    r.missingOnSheet.remove(id);
                  }),
                  child: const Text('Đưa lại lên Sheet'),
                ),
              ],
            ),
          ),
        ),
      ),
  ];
}

class _BackupSection extends StatefulWidget {
  const _BackupSection();
  @override
  State<_BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends State<_BackupSection> {
  final s = Services.I;
  bool busy = false;

  Future<void> _run(Future<void> Function() f) async {
    setState(() => busy = true);
    try {
      await f();
    } catch (e) {
      if (mounted) toast(context, 'Lỗi: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<String?> _ask(String title, {bool twice = false}) async {
    final a = TextEditingController(), b = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: a,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Mật khẩu sao lưu hoặc mã khôi phục'),
            ),
            if (twice)
              TextField(
                controller: b,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Nhập lại mật khẩu'),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Huỷ')),
          FilledButton(
            onPressed: () {
              if (a.text.length < 8) return toast(ctx, 'Tối thiểu 8 ký tự');
              if (twice && a.text != b.text) return toast(ctx, 'Hai lần nhập không khớp');
              Navigator.pop(ctx, a.text);
            },
            child: const Text('Tiếp'),
          ),
        ],
      ),
    );
  }

  Future<void> _enable() async {
    final pw = await _ask('Đặt mật khẩu sao lưu', twice: true);
    if (pw == null) return;
    await _run(() async {
      final (dk, env, code) = await BackupCrypto.setup(pw);
      await s.storeBackupKey(dk, env);
      if (!mounted) return;
      final grouped = [for (var i = 0; i < code.length; i += 4) code.substring(i, i + 4)].join('-');
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Mã khôi phục'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Ghi lại mã này ở nơi an toàn. Quên cả mật khẩu lẫn mã thì không ai khôi phục được dữ liệu — kể cả nhà phát triển.',
              ),
              const SizedBox(height: 12),
              SelectableText(grouped, style: const TextStyle(fontFamily: 'monospace', fontSize: 18)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: grouped)),
              child: const Text('Chép'),
            ),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tôi đã lưu')),
          ],
        ),
      );
      setState(() {});
    });
  }

  Future<Uint8List> _make() async {
    final dk = await s.backupKey();
    final env = await s.db.getSetting('backup_envelope');
    if (dk == null || env == null) throw StateError('Chưa bật sao lưu');
    return BackupCrypto.encryptFile(dk, env, await DbSnapshot(s.db).export());
  }

  Future<void> _restore(Uint8List bytes) async {
    final secret = await _ask('Mở bản sao lưu');
    if (secret == null) return;
    await _run(() async {
      final r = await BackupCrypto.decryptFile(bytes, secret);
      if (r == null) throw StateError('Sai mật khẩu hoặc mã khôi phục');
      final (payload, dk, env) = r;
      if (!mounted || !await confirm(context, 'Thay toàn bộ dữ liệu trên máy bằng bản sao lưu này?', ok: 'Khôi phục')) return;
      await DbSnapshot(s.db).restore(payload);
      await s.storeBackupKey(dk, env);
      if (mounted) toast(context, 'Đã khôi phục');
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: s.db.getSetting('backup_envelope'),
      builder: (context, env) {
        final enabled = env.data != null;
        return StreamBuilder<String?>(
          stream: s.db.watchSetting('sheets_id'),
          builder: (context, sid) {
            final drive = sid.data != null;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: 4, child: busy ? const LinearProgressIndicator() : null),
                const Text('Mã hoá đầu-cuối bằng mật khẩu của bạn (Argon2id + AES-256-GCM). Google cũng không đọc được.'),
                const SizedBox(height: 8),
                if (!enabled) FilledButton(onPressed: busy ? null : _enable, child: const Text('Bật sao lưu')),
                if (enabled) ...[
                  if (drive)
                    StreamBuilder<String?>(
                      stream: s.db.watchSetting('backup_last'),
                      builder: (context, l) => Text(
                        'Tự động hằng ngày lên Drive, giữ 30 bản. Lần cuối: '
                        '${fmtStamp(l.data)}',
                      ),
                    ),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (drive)
                        FilledButton(
                          onPressed: busy
                              ? null
                              : () => _run(() async {
                                  await s.google.uploadBackup(await _make());
                                  await s.db.setSetting('backup_last', DateTime.now().toIso8601String());
                                  if (context.mounted) toast(context, 'Đã sao lưu lên Drive');
                                }),
                          child: const Text('Sao lưu ngay'),
                        ),
                      OutlinedButton(
                        onPressed: busy
                            ? null
                            : () => _run(
                                () async => shareBytes(
                                  await _make(),
                                  'vi-rieng-${DateTime.now().toIso8601String().substring(0, 10)}.vrbackup',
                                  'application/octet-stream',
                                ),
                              ),
                        child: const Text('Lưu ra file'),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    if (drive)
                      OutlinedButton(onPressed: busy ? null : () => _pickDrive(context), child: const Text('Khôi phục từ Drive')),
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () async {
                              final f = await FilePicker.pickFiles();
                              if (f.isNotEmpty) await _restore(await f.first.readAsBytes());
                            },
                      child: const Text('Khôi phục từ file'),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _pickDrive(BuildContext context) async {
    final files = await s.google.listBackups();
    if (!context.mounted) return;
    final id = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Chọn bản sao lưu'),
        children: [
          if (files.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Chưa có bản nào.')),
          for (final f in files)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, f.id),
              child: Text(f.createdTime?.toLocal().toString().substring(0, 16) ?? f.name!),
            ),
        ],
      ),
    );
    if (id != null) await _restore(await s.google.downloadBackup(id));
  }
}

/// Thời điểm lưu dạng ISO → "yyyy-MM-dd HH:mm"; rỗng hoặc hỏng thì "chưa" thay vì làm vỡ giao diện.
String fmtStamp(String? iso) {
  final d = DateTime.tryParse(iso ?? '');
  if (d == null) return 'chưa';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

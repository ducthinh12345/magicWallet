import 'dart:convert';

import 'package:drift/drift.dart' show OrderingTerm, ComparableExpr;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../capture/parser.dart';
import '../capture/statement_import.dart';
import '../core/money.dart';
import '../data/database.dart';
import '../services.dart';
import '../pro/pro.dart';
import 'pro_screen.dart';
import 'setup_guide.dart';
import 'widgets.dart';

/// Phiên bản nội dung giải thích mục đích; đổi nội dung thì tăng số để xin đồng ý lại (Luật GDĐT 2023).
const consentVersion = '1';

const _purpose = {
  'notification':
      'Ví Ma Thuật sẽ đọc thông báo của CHỈ những ứng dụng ngân hàng/ví bạn chọn bên dưới để tự ghi giao dịch.\n\n'
      '• Chỉ xử lý trên điện thoại này, không gửi đi đâu.\n'
      '• Thông báo có OTP, mã xác thực, mật khẩu bị bỏ ngay, không lưu.\n'
      '• Nội dung gốc tự xoá sau 30 ngày; bạn xem được ở mục "Dữ liệu app đã đọc".\n'
      '• Rút lại đồng ý bất cứ lúc nào bằng cách tắt công tắc này.',
  'email':
      'Bạn sẽ tự cài một Google Apps Script vào tài khoản Google của mình. Script đọc các email đã gắn nhãn '
      '"Ví Ma Thuật" và ghi vào tab "Hộp thư" của Google Sheet của bạn; app kéo về để tạo giao dịch chờ duyệt.\n\n'
      '• Script chạy trong tài khoản của bạn, nhà phát triển không có quyền truy cập.\n'
      '• Gỡ bất cứ lúc nào tại script.google.com.',
};

Future<bool> askConsent(BuildContext context, String source) async {
  final s = Services.I;
  final ok =
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Bạn đồng ý chứ?'),
          content: SingleChildScrollView(child: Text(_purpose[source]!)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Không')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Tôi đồng ý')),
          ],
        ),
      ) ??
      false;
  // Lưu bằng chứng đồng ý (phiên bản, thời điểm) trên máy và trong bản sao lưu.
  await s.db.setSetting(
    'consent:$source',
    ok ? jsonEncode({'version': consentVersion, 'at': DateTime.now().toIso8601String()}) : '',
  );
  return ok;
}

/// Tắt ghi tự động: app đã ngừng xử lý ngay, nhưng quyền hệ thống chỉ người dùng tự gỡ được.
const _revokeListener = SetupStep(
  'listener',
  Icons.notifications_off_outlined,
  'Gỡ quyền truy cập thông báo',
  'Ví Ma Thuật đã ngừng đọc thông báo. Nếu muốn gỡ hẳn quyền khỏi hệ thống:',
  ['Trong danh sách vừa mở, chạm "Ví Ma Thuật".', 'Tắt công tắc "Cho phép truy cập thông báo".', 'Bấm nút Quay lại để về app.'],
);

/// SC-09: bật/tắt từng nguồn, chọn ngân hàng, thử với thông báo mẫu.
class SourcesScreen extends StatefulWidget {
  const SourcesScreen({super.key});
  @override
  State<SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends State<SourcesScreen> with WidgetsBindingObserver {
  final s = Services.I;
  bool listener = false, notifConsent = false, sms = false, auto = false, emailConsent = false;
  Set<String> enabled = {};
  Map<String, (int, int)> rates = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Quay về từ màn cài đặt hệ thống → đọc lại trạng thái quyền.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final l = await NativeCapture.listenerEnabled();
    final c = (await s.db.getSetting('consent:notification') ?? '').isNotEmpty;
    final e = (await s.db.getSetting('consent:email') ?? '').isNotEmpty;
    final en = await s.enabledInstitutions();
    final r = await _rates();
    final smsOn = await s.flag('capture_sms');
    final a = await s.flag('auto_confirm');
    if (!mounted) return;
    setState(() {
      listener = l;
      notifConsent = c;
      emailConsent = e;
      enabled = en;
      rates = r;
      sms = smsOn;
      auto = a;
    });
  }

  /// Tỷ lệ nhận dạng 7 ngày theo tổ chức (5.5): (nhận dạng được, tổng).
  Future<Map<String, (int, int)>> _rates() async {
    final since = DateTime.now().subtract(const Duration(days: 7));
    final rows = await (s.db.select(s.db.rawEvents)..where((e) => e.receivedAt.isBiggerOrEqualValue(since))).get();
    final out = <String, (int, int)>{};
    for (final r in rows) {
      final inst = s.catalog.identify(r.sourceApp ?? '', r.content.split('\n').first);
      if (inst == null) continue;
      final (ok, n) = out[inst.id] ?? (0, 0);
      out[inst.id] = (ok + (r.parseStatus == 'unknown' ? 0 : 1), n + 1);
    }
    return out;
  }

  Future<void> _toggleNotif(bool on) async {
    if (on) {
      if (!await askConsent(context, 'notification')) return;
      if (!listener && mounted) await guideTo(context, captureSetup(false).first);
    } else {
      // Rút lại đồng ý: xoá whitelist; quyền hệ thống người dùng tắt trong Cài đặt.
      await s.db.setSetting('consent:notification', '');
      await s.db.setSetting('capture_institutions', '[]');
      await s.setFlag('capture_sms', false);
      await s.pushWhitelist();
      if (listener && mounted) await guideTo(context, _revokeListener);
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Ghi tự động')),
      body: ListView(
        children: [
          if (!NativeCapture.supported)
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Đọc thông báo ngân hàng chỉ có trên Android.'),
              subtitle: Text('Trên thiết bị này hãy dùng email hoá đơn (Apps Script) hoặc nhập sao kê.'),
            ),
          if (NativeCapture.supported) ...[
            SwitchListTile(
              title: const Text('Đọc thông báo ngân hàng / ví'),
              subtitle: Text(
                notifConsent && listener
                    ? 'Đang bật'
                    : notifConsent
                    ? 'Cần cấp quyền "Truy cập thông báo" cho Ví Ma Thuật'
                    : 'Tắt',
              ),
              value: notifConsent && listener,
              onChanged: _toggleNotif,
            ),
            if (notifConsent) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text('Thiết lập điện thoại để ghi tự động chạy ổn định', style: theme.textTheme.titleMedium),
              ),
              const SetupChecklist(),
              const Divider(),
              SwitchListTile(
                title: const Text('Cả SMS biến động số dư'),
                subtitle: const Text('Đọc qua thông báo của app tin nhắn, không xin quyền đọc SMS'),
                value: sms,
                onChanged: (v) async {
                  await s.setFlag('capture_sms', v);
                  await s.pushWhitelist();
                  _load();
                },
              ),
              SwitchListTile(
                title: const Text('Tự xác nhận khi tin cậy ≥ 95%'),
                subtitle: const Text('Chỉ áp dụng cho giao dịch khớp quy tắc của bạn'),
                value: auto,
                onChanged: (v) async {
                  if (v && !await requirePro(context, 'Tự xác nhận giao dịch')) return;
                  await s.setFlag('auto_confirm', v);
                  _load();
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text('Ngân hàng & ví được đọc', style: theme.textTheme.titleMedium),
              ),
              for (final i in s.catalog.all)
                CheckboxListTile(
                  title: Text(i.name),
                  subtitle: _rateText(i.id),
                  value: enabled.contains(i.id),
                  onChanged: (v) async {
                    if (v! && enabled.length >= FreeLimits.autoSources &&
                        !await requirePro(context, 'Ghi tự động từ ${FreeLimits.autoSources + 1} ngân hàng/ví trở lên')) {
                      return;
                    }
                    await s.setInstitution(i.id, v);
                    _load();
                  },
                ),
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Tên ngân hàng/ví chỉ dùng để mô tả tương thích. Ví Ma Thuật không liên kết hay được bảo trợ bởi ngân hàng nào.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ],
          const Divider(),
          ListTile(
            leading: const Icon(Icons.science_outlined),
            title: const Text('Thử với thông báo mẫu'),
            subtitle: const Text('Dán một thông báo để xem app hiểu thế nào'),
            onTap: () => _tryParse(context),
          ),
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: const Text('Email hoá đơn (Apps Script)'),
            subtitle: Text(emailConsent ? 'Đã bật — dữ liệu về qua lần đồng bộ Google' : 'Hướng dẫn cài 1 lần'),
            onTap: () async {
              if (await requirePro(context, 'Đọc email hoá đơn') && context.mounted) await _emailGuide(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text('Nhập sao kê CSV'),
            subtitle: const Text('Tải sao kê từ internet banking rồi nhập để lấp chỗ thiếu'),
            onTap: () => importStatement(context),
          ),
          ListTile(
            leading: const Icon(Icons.visibility_outlined),
            title: const Text('Dữ liệu app đã đọc'),
            subtitle: const Text('Nội dung thông báo gốc 30 ngày gần nhất'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RawEventsScreen())),
          ),
        ],
      ),
    );
  }

  Widget? _rateText(String id) {
    final r = rates[id];
    if (r == null) return null;
    final (ok, n) = r;
    final pct = ok * 100 ~/ n;
    return Text(
      'Nhận dạng $pct% ($ok/$n) trong 7 ngày${pct < 95 ? ' — hãy kiểm tra mục "Dữ liệu app đã đọc"' : ''}',
      style: TextStyle(color: pct < 95 ? expenseColor : null),
    );
  }

  Future<void> _tryParse(BuildContext context) async {
    final ctl = TextEditingController();
    String result = '';
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Thử nhận dạng'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctl,
                maxLines: 4,
                decoration: const InputDecoration(hintText: 'Dán nội dung thông báo'),
              ),
              const SizedBox(height: 8),
              Text(result),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () {
                final r = parseNotification(ctl.text);
                set(
                  () => result = switch (r) {
                    Parsed(:final txn) =>
                      '${txn.direction > 0 ? 'Tiền vào' : 'Tiền ra'} ${formatVnd(txn.amount)}'
                          '${txn.balance == null ? '' : '\nSố dư: ${formatVnd(txn.balance!)}'}'
                          '${txn.last4 == null ? '' : '\nTài khoản: •••• ${txn.last4}'}'
                          '${txn.content.isEmpty ? '' : '\nNội dung: ${txn.content}'}'
                          '${txn.isRefund ? '\n(Hoàn tiền)' : ''}',
                    DroppedSensitive() => 'Có OTP/mã xác thực → bỏ qua, không lưu.',
                    Unrecognized() => 'Không nhận dạng được. Sẽ lưu vào "Chưa xác định" để bạn tự điền.',
                  },
                );
              },
              child: const Text('Thử'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _emailGuide(BuildContext context) async {
    final script = await rootBundle.loadString('assets/apps_script.gs');
    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          appBar: AppBar(title: const Text('Email hoá đơn')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                '1. Kết nối Google trong mục "Google Sheets & sao lưu" (để có file "Ví Riêng – Dữ liệu").\n'
                '2. Trong Gmail, tạo bộ lọc gắn nhãn "Ví Ma Thuật" cho email của ngân hàng, Shopee, Grab…\n'
                '3. Mở file Sheet → Tiện ích mở rộng → Apps Script, dán đoạn mã bên dưới, bấm Chạy hàm setup một lần và cấp quyền.\n'
                '4. Script chạy mỗi 15 phút, ghi email mới vào tab "Hộp thư"; app kéo về ở lần đồng bộ kế tiếp.',
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: const Icon(Icons.copy),
                label: const Text('Chép mã script'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: script));
                  if (ctx.mounted) toast(ctx, 'Đã chép');
                },
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () async {
                  if (await askConsent(ctx, 'email')) await _load();
                },
                child: const Text('Tôi đã cài xong, bật nguồn email'),
              ),
              const SizedBox(height: 12),
              SelectableText(script, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

/// S5: chọn file CSV → đoán cột (lưu lại mẫu ánh xạ) → chọn ví → tạo giao dịch chờ duyệt cho dòng còn thiếu.
Future<void> importStatement(BuildContext context) async {
  final s = Services.I;
  final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['csv']);
  if (files.isEmpty) return;
  var text = utf8.decode(await files.first.readAsBytes(), allowMalformed: true);
  if (text.startsWith('﻿')) text = text.substring(1);
  final rows = parseCsv(text);
  if (rows.length < 2) {
    if (context.mounted) toast(context, 'File trống');
    return;
  }
  // Sao kê hay có vài dòng thông tin trước bảng: lấy dòng đầu tiên đoán được cột làm tiêu đề.
  var headerIdx = rows.indexWhere((r) => guessMapping(r) != null);
  if (headerIdx < 0) headerIdx = 0;
  final header = rows[headerIdx];
  final saved = await s.db.getSetting(ColumnMapping.keyFor(header));
  ColumnMapping? m = saved != null ? ColumnMapping.fromJson(jsonDecode(saved)) : guessMapping(header);
  final wallets = (await s.repo.watchWallets().first).where((w) => !w.archived).toList();
  if (wallets.isEmpty) {
    if (context.mounted) toast(context, 'Tạo ví trước');
    return;
  }
  var walletId = wallets.first.id;
  int? date = m?.date, desc = m?.description, amount = m?.amount, debit = m?.debit, credit = m?.credit;
  if (!context.mounted) return;

  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        DropdownButtonFormField<int?> col(String label, int? v, ValueChanged<int?> f) => DropdownButtonFormField<int?>(
          initialValue: v,
          decoration: InputDecoration(labelText: label),
          items: [
            const DropdownMenuItem(value: null, child: Text('—')),
            for (var i = 0; i < header.length; i++)
              DropdownMenuItem(value: i, child: Text(header[i].isEmpty ? 'Cột ${i + 1}' : header[i])),
          ],
          onChanged: (x) => set(() => f(x)),
        );
        final preview = (date != null && desc != null && (amount != null || debit != null || credit != null))
            ? mapRows(
                rows.skip(headerIdx + 1).toList(),
                ColumnMapping(date: date!, description: desc!, amount: amount, debit: debit, credit: credit),
              )
            : <StatementRow>[];
        return AlertDialog(
          title: const Text('Ánh xạ cột sao kê'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: walletId,
                  decoration: const InputDecoration(labelText: 'Nhập vào ví'),
                  items: [for (final w in wallets) DropdownMenuItem(value: w.id, child: Text(w.name))],
                  onChanged: (v) => set(() => walletId = v!),
                ),
                col('Ngày', date, (x) => date = x),
                col('Nội dung', desc, (x) => desc = x),
                col('Số tiền (có dấu ±)', amount, (x) => amount = x),
                col('Ghi nợ (tiền ra)', debit, (x) => debit = x),
                col('Ghi có (tiền vào)', credit, (x) => credit = x),
                const SizedBox(height: 8),
                Text('Đọc được ${preview.length} dòng'),
                for (final r in preview.take(3))
                  Text(
                    '${r.date.day}/${r.date.month} ${r.direction > 0 ? '+' : '−'}${formatVnd(r.amount)} ${r.description}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
            FilledButton(onPressed: preview.isEmpty ? null : () => Navigator.pop(ctx, true), child: const Text('Nhập')),
          ],
        );
      },
    ),
  );
  if (go != true) return;
  m = ColumnMapping(date: date!, description: desc!, amount: amount, debit: debit, credit: credit);
  await s.db.setSetting(ColumnMapping.keyFor(header), jsonEncode(m.toJson()));
  final n = await s.pipeline.importStatement(mapRows(rows.skip(headerIdx + 1).toList(), m), walletId);
  if (context.mounted) toast(context, 'Đã thêm $n giao dịch chờ duyệt (bỏ qua dòng đã có)');
}

/// "Dữ liệu app đã đọc" (10.1): người dùng tự kiểm tra app đã đọc gì.
class RawEventsScreen extends StatelessWidget {
  const RawEventsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = Services.I;
    const status = {'parsed': 'Đã ghi', 'unknown': 'Chưa xác định', 'duplicate': 'Trùng — đã gộp'};
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dữ liệu app đã đọc'),
        actions: [
          IconButton(
            tooltip: 'Xoá hết',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () async {
              if (await confirm(context, 'Xoá toàn bộ nội dung thông báo gốc đã lưu?', ok: 'Xoá')) {
                await s.db.delete(s.db.rawEvents).go();
              }
            },
          ),
        ],
      ),
      body: StreamBuilder<List<RawEvent>>(
        stream: (s.db.select(s.db.rawEvents)..orderBy([(e) => OrderingTerm.desc(e.receivedAt)])).watch(),
        builder: (context, snap) {
          final list = snap.data ?? const <RawEvent>[];
          if (snap.hasData && list.isEmpty) return const EmptyState('App chưa đọc nội dung nào.');
          return ListView(
            children: [
              for (final e in list)
                ListTile(
                  title: Text(e.content, maxLines: 3, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${dayLabel(e.receivedAt)} · ${e.sourceApp ?? e.source} · ${status[e.parseStatus] ?? e.parseStatus}',
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

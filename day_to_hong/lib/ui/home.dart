import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';

import '../app/pro.dart';
import '../app/session.dart';
import '../app/tracker.dart';
import '../data/sync.dart';
import '../main.dart' show pro, rose, track;
import 'circle.dart';
import 'more.dart';
import 'sign_in.dart';

const playUrl = 'https://play.google.com/store/apps/details?id=vn.vimathuat.day_to_hong';

/// SC-03.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Sync? sync;
  bool sharing = false;
  Pause pause = const Pause();
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await openSync(track);
    if (s == null) return;
    s.onSos = showSos; // service tắt vẫn nhận SOS khi app đang mở; Track.firstSeen chống báo trùng
    final running = await Tracker.running, p = await Pause.load();
    if (!mounted) return;
    setState(() {
      sync = s;
      sharing = running;
      pause = p;
    });
    _refresh();
    _poll = Timer.periodic(const Duration(minutes: 1), (_) => _refresh()); // mở app thì xem mới hơn nhịp nền 3 phút
  }

  Future<void> _refresh() => sync!.refresh().catchError((Object e) => debugPrint('refresh: $e'));

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _toggleShare(bool on) async {
    if (on) {
      if (!await askSharePermissions(context)) return;
      await Tracker.start();
    } else {
      Tracker.stop();
    }
    setState(() => sharing = on);
  }

  Future<void> _setPause(Pause p) async {
    await Pause.save(p);
    Tracker.refresh(); // nút tạm ẩn chỉ hiện khi service đang chạy
    setState(() => pause = p);
  }

  Future<void> _create() async {
    final s = sync!;
    final owned = s.circles.value.where((c) => c.ref.owner).length;
    final r = await showDialog<(String, bool)>(context: context, builder: (_) => InviteDialog(canFamily: true, me: s.email));
    if (r == null || !mounted) return;
    final (email, family) = r;
    final block = createBlock(pro: pro.owned.value, family: family, ownedCircles: owned);
    if (block != null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => ProScreen(reason: block)));
      return;
    }
    await guard(context, () async {
      final ref = await s.create(family: family);
      final code = await s.invite(ref, email);
      await _refresh();
      if (mounted) await shareInvite(email, code);
    });
  }

  Future<void> _join() async {
    final code = await showDialog<String>(context: context, builder: (_) => const _JoinDialog());
    if (code == null || !mounted) return;
    await guard(context, () async {
      await sync!.join(code);
      await _refresh();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã nối dây tơ hồng 💞')));
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = sync;
    if (s == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dây tơ hồng', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Cài đặt',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsScreen(sync: s))),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showModalBottomSheet(
          context: context,
          builder: (c) => SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                leading: const Icon(Icons.favorite_border, color: rose),
                title: const Text('Tạo sợi tơ & mời bằng Gmail'),
                onTap: () {
                  Navigator.pop(c);
                  _create();
                },
              ),
              ListTile(
                leading: const Icon(Icons.vpn_key_outlined, color: rose),
                title: const Text('Tôi có mã mời'),
                onTap: () {
                  Navigator.pop(c);
                  _join();
                },
              ),
            ]),
          ),
        ),
        icon: const Icon(Icons.favorite_border),
        label: const Text('Nối dây tơ hồng'),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
          children: [
            _shareCard(),
            ValueListenableBuilder(
              valueListenable: s.circles,
              builder: (_, list, _) => list.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('Chưa có sợi tơ nào.\nBấm "Nối dây tơ hồng" để mời người thương, hoặc dán mã mời bạn nhận được.',
                          textAlign: TextAlign.center),
                    )
                  : Column(children: [for (final c in list) _CircleCard(sync: s, view: c)]),
            ),
            const SizedBox(height: 16),
            Center(child: SosButton(sync: s)),
          ],
        ),
      ),
    );
  }

  Widget _shareCard() {
    final hidden = pause.active;
    return Card(
      child: Column(children: [
        SwitchListTile(
          secondary: Icon(sharing && !hidden ? Icons.share_location : Icons.location_off_outlined, color: rose),
          title: const Text('Chia sẻ vị trí của tôi'),
          subtitle: Text(!sharing
              ? 'Đang tắt — người thân không thấy bạn'
              : hidden
                  ? (pause.forever ? 'Đang tạm ẩn' : 'Tạm ẩn tới ${hm(pause.until!)}')
                  : 'Đang chia sẻ · cập nhật mỗi ${syncEvery.inMinutes} phút'),
          value: sharing,
          onChanged: _toggleShare,
        ),
        if (sharing)
          OverflowBar(alignment: MainAxisAlignment.end, children: [
            if (hidden)
              TextButton(onPressed: () => _setPause(const Pause()), child: const Text('Hiện lại vị trí'))
            else ...[
              TextButton(
                onPressed: () => _setPause(Pause(until: DateTime.now().add(const Duration(hours: 1)))),
                child: const Text('Tạm ẩn 1 giờ'),
              ),
              TextButton(onPressed: () => _setPause(const Pause(forever: true)), child: const Text('Tạm ẩn')),
            ],
          ]),
      ]),
    );
  }
}

class _CircleCard extends StatelessWidget {
  final Sync sync;
  final CircleView view;
  const _CircleCard({required this.sync, required this.view});

  @override
  Widget build(BuildContext context) {
    final others = view.members.where((m) => m.email != sync.email).toList();
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CircleScreen(sync: sync, circleId: view.ref.id))),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(children: [
            ListTile(
              leading: Icon(view.ref.family ? Icons.family_restroom : Icons.favorite, color: rose),
              title: Text(view.ref.family ? 'Gia đình' : 'Sợi tơ đôi', style: const TextStyle(fontWeight: FontWeight.w700)),
              trailing: const Icon(Icons.chevron_right),
            ),
            if (view.error != null) ConsentAwareError(sync: sync, error: view.error!),
            for (final m in others)
              ListTile(dense: true, leading: const Icon(Icons.person_pin_circle_outlined), title: Text(m.label), subtitle: Text(status(m))),
            if (others.isEmpty && view.pending.isEmpty && view.error == null)
              const ListTile(dense: true, leading: Icon(Icons.hourglass_empty), title: Text('Chờ người ấy nhập mã mời…')),
            for (final e in view.pending)
              ListTile(dense: true, leading: const Icon(Icons.hourglass_empty), title: Text(e), subtitle: const Text('Đã mời, chưa nhập mã')),
          ]),
        ),
      ),
    );
  }
}

/// Lỗi của một sợi tơ; nếu là thiếu quyền Google thì có nút cấp lại ngay.
class ConsentAwareError extends StatelessWidget {
  final Sync sync;
  final String error;
  const ConsentAwareError({super.key, required this.sync, required this.error});
  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        leading: const Icon(Icons.error_outline, color: Colors.orange),
        title: Text(error),
        trailing: error.contains('quyền Google')
            ? TextButton(
                onPressed: () => guard(context, () async {
                  if (await regrant(sync.email)) await sync.refresh();
                }),
                child: const Text('Cấp quyền'),
              )
            : null,
      );
}

String hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Trạng thái trung thực — quá 30 phút ghi rõ có thể đã tắt máy.
String status(Member m, [DateTime? now]) {
  if (m.locked) return 'Chưa giải mã được — mã mời sai hoặc người này dùng mã cũ';
  if (m.paused) return m.pausedUntil == null ? 'Đang ẩn vị trí' : 'Tạm ẩn tới ${hm(m.pausedUntil!)}';
  final f = m.fix;
  if (f == null) return 'Chưa có vị trí';
  final ago = (now ?? DateTime.now()).difference(DateTime.fromMillisecondsSinceEpoch(f.t));
  final s = ago.inMinutes < 1 ? 'vừa xong' : ago.inMinutes < 60 ? '${ago.inMinutes} phút trước' : ago.inHours < 24 ? '${ago.inHours} giờ trước' : '${ago.inDays} ngày trước';
  return ago.inMinutes > 30 ? 'Cập nhật $s — có thể đã tắt máy/mất mạng' : 'Cập nhật $s';
}

/// Chạy một thao tác mạng, báo lỗi dễ hiểu bằng SnackBar thay vì nuốt lỗi.
Future<void> guard(BuildContext context, Future<void> Function() f) async {
  try {
    await f();
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendly(e))));
  }
}

/// App không tự gửi gì — người dùng chọn kênh nhắn (Zalo, Messenger…).
Future<void> shareInvite(String email, String code) => SharePlus.instance.share(ShareParams(
      text: 'Mình mời bạn ($email) nối "Dây tơ hồng" — chia sẻ vị trí, kế hoạch và kỷ niệm của hai đứa.\n'
          '1) Cài app: $playUrl\n2) Đăng nhập đúng Gmail $email\n3) Bấm "Nối dây tơ hồng" › "Tôi có mã mời" và dán mã:\n$code',
    ));

/// SC-06: nhập Gmail. Trả (email, family).
class InviteDialog extends StatefulWidget {
  final bool canFamily;
  final String me;
  const InviteDialog({super.key, required this.canFamily, required this.me});
  @override
  State<InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends State<InviteDialog> {
  final _email = TextEditingController();
  bool _family = false;
  String? _err;

  void _ok() {
    final e = normalizeEmail(_email.text);
    if (e == null) return setState(() => _err = 'Email chưa đúng');
    if (e == widget.me) return setState(() => _err = 'Đây là email của bạn');
    Navigator.pop(context, (e, _family));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Mời bằng Gmail'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _email,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(labelText: 'Gmail của người ấy', errorText: _err),
            onSubmitted: (_) => _ok(),
          ),
          if (widget.canFamily)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Sợi tơ gia đình'),
              subtitle: const Text('Tới 10 người · Gói Gia đình'),
              value: _family,
              onChanged: (v) => setState(() => _family = v),
            ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Huỷ')),
          FilledButton(onPressed: _ok, child: const Text('Mời')),
        ],
      );
}

/// Chuẩn hoá email mời. Null nếu không giống email.
String? normalizeEmail(String s) {
  final e = s.trim().toLowerCase();
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e) ? e : null;
}

class _JoinDialog extends StatefulWidget {
  const _JoinDialog();
  @override
  State<_JoinDialog> createState() => _JoinDialogState();
}

class _JoinDialogState extends State<_JoinDialog> {
  final _code = TextEditingController();
  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Nhập mã mời'),
        content: TextField(
          controller: _code,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(hintText: 'Dán cả tin nhắn có mã DTH1.… vào đây'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(context, _code.text), child: const Text('Nối dây')),
        ],
      );
}

/// Giữ 2 giây để tránh bấm nhầm trong túi.
class SosButton extends StatefulWidget {
  final Sync sync;
  const SosButton({super.key, required this.sync});
  @override
  State<SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends State<SosButton> with SingleTickerProviderStateMixin {
  late final _hold = AnimationController(vsync: this, duration: const Duration(seconds: 2))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _fire();
    });

  Future<void> _fire() async {
    _hold.reset();
    final messenger = ScaffoldMessenger.of(context);
    Position? p;
    try {
      p = await Geolocator.getCurrentPosition().timeout(const Duration(seconds: 8));
    } catch (_) {
      p = await Geolocator.getLastKnownPosition(); // không có GPS mới vẫn gửi SOS ngay
    }
    try {
      final n = await widget.sync.sos(p == null ? null : fixOf(p));
      messenger.showSnackBar(SnackBar(
          content: Text(n == 0
              ? 'Chưa có sợi tơ nào để gửi SOS'
              : 'Đã gửi SOS tới $n sợi tơ — người thân nhận trong vòng vài phút. Nếu khẩn cấp, hãy gọi 113/115.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Không gửi được SOS: ${friendly(e)} — hãy gọi điện trực tiếp.')));
    }
  }

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'SOS, giữ 2 giây để gửi cảnh báo khẩn cấp',
        child: GestureDetector(
          onTapDown: (_) => _hold.forward(),
          onTapUp: (_) => _hold.reverse(),
          onTapCancel: () => _hold.reverse(),
          child: AnimatedBuilder(
            animation: _hold,
            builder: (_, _) => Stack(alignment: Alignment.center, children: [
              SizedBox.square(dimension: 96, child: CircularProgressIndicator(value: _hold.value, strokeWidth: 6, color: Colors.red)),
              const CircleAvatar(
                  radius: 40,
                  backgroundColor: Colors.red,
                  child: Text('SOS', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900))),
            ]),
          ),
        ),
      );
}

/// Gợi ý khi chia sẻ hay bị ngắt.
const batteryHint = 'Nếu vị trí hay "đứng hình": vào Cài đặt điện thoại › Ứng dụng › Dây tơ hồng › Pin › chọn "Không hạn chế". '
    'Máy Xiaomi/Oppo/Vivo: bật thêm "Tự khởi chạy".';

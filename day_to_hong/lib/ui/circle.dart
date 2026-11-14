import 'dart:io';

import 'package:flutter/material.dart';
import 'package:googleapis/calendar/v3.dart' as cal;
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/geo.dart';
import '../data/store.dart';
import '../data/sync.dart';
import '../main.dart' show openMapAt, pro, rose, track;
import 'home.dart';
import 'more.dart';

/// SC-04: Vị trí · Kế hoạch · Kỷ niệm của một sợi tơ.
class CircleScreen extends StatelessWidget {
  final Sync sync;
  final String circleId;
  const CircleScreen({super.key, required this.sync, required this.circleId});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: sync.circles,
        builder: (_, list, _) {
          final v = list.where((c) => c.ref.id == circleId).firstOrNull;
          if (v == null) return const Scaffold(body: Center(child: Text('Sợi tơ không còn nữa.')));
          final ref = v.ref;
          return DefaultTabController(
            length: 3,
            child: Scaffold(
              appBar: AppBar(
                title: Text(ref.family ? 'Gia đình' : 'Sợi tơ đôi'),
                actions: [
                  PopupMenuButton<String>(
                    onSelected: (a) => switch (a) {
                      'invite' => _invite(context, ref),
                      'code' => shareInvite('người ấy', sync.inviteCode(ref)),
                      _ => _leave(context, ref),
                    },
                    itemBuilder: (_) => [
                      if (ref.owner) const PopupMenuItem(value: 'invite', child: Text('Mời thêm người')),
                      const PopupMenuItem(value: 'code', child: Text('Gửi lại mã mời')),
                      PopupMenuItem(value: 'leave', child: Text(ref.owner ? 'Xoá sợi tơ' : 'Rời sợi tơ')),
                    ],
                  ),
                ],
                bottom: const TabBar(tabs: [Tab(text: 'Vị trí'), Tab(text: 'Kế hoạch'), Tab(text: 'Kỷ niệm')]),
              ),
              body: TabBarView(children: [
                _Places(sync: sync, view: v),
                _Plans(sync: sync, ref: ref),
                _Memories(sync: sync, ref: ref),
              ]),
            ),
          );
        },
      );

  Future<void> _invite(BuildContext context, CircleRef ref) async {
    // Mất Pro thì sợi tơ gia đình vẫn chạy nhưng không thêm người.
    if (ref.family && !pro.owned.value) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const ProScreen(reason: 'Thêm người vào sợi tơ gia đình cần Gói Gia đình.')));
      return;
    }
    final r = await showDialog<(String, bool)>(context: context, builder: (_) => InviteDialog(canFamily: false, me: sync.email));
    if (r == null || !context.mounted) return;
    await guard(context, () async {
      final code = await sync.invite(ref, r.$1);
      await shareInvite(r.$1, code);
      await sync.refresh();
    });
  }

  Future<void> _leave(BuildContext context, CircleRef ref) async {
    final ok = await confirm(
      context,
      ref.owner ? 'Xoá sợi tơ?' : 'Rời sợi tơ?',
      ref.owner
          ? 'Lịch chung (cả kế hoạch và kỷ niệm) sẽ bị xoá khỏi Google Calendar của mọi người. Không hoàn tác được.'
          : 'Bạn sẽ không thấy vị trí, kế hoạch, kỷ niệm của sợi tơ này nữa.',
      ref.owner ? 'Xoá' : 'Rời',
    );
    if (!ok || !context.mounted) return;
    await guard(context, () async {
      await sync.leave(ref);
      if (context.mounted) Navigator.pop(context);
    });
  }
}

Future<bool> confirm(BuildContext context, String title, String body, String yes) async =>
    await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Thôi')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(yes)),
        ],
      ),
    ) ==
    true;

// ---------------- Vị trí ----------------

class _Places extends StatelessWidget {
  final Sync sync;
  final CircleView view;
  const _Places({required this.sync, required this.view});

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: sync.refresh,
        child: ListView(padding: const EdgeInsets.all(12), children: [
          if (view.error != null) ConsentAwareError(sync: sync, error: view.error!),
          for (final m in view.members)
            Card(
              child: ListTile(
                leading: CircleAvatar(backgroundColor: rose.withValues(alpha: 0.15), child: Text(_me(m).characters.first)),
                title: Text(_me(m)),
                subtitle: Text(status(m)),
                trailing: m.fix != null && !m.paused
                    ? IconButton(tooltip: 'Mở Google Maps', icon: const Icon(Icons.map_outlined), onPressed: () => openMapAt(m.fix!.latLng))
                    : null,
                onTap: () => _sheet(context, m),
              ),
            ),
          for (final e in view.pending)
            Card(
              child: ListTile(
                leading: const Icon(Icons.hourglass_empty),
                title: Text(e),
                subtitle: const Text('Đã mời, chưa nhập mã'),
                trailing: IconButton(
                  tooltip: 'Huỷ lời mời',
                  icon: const Icon(Icons.close),
                  onPressed: () => guard(context, () async {
                    await sync.kick(view.ref, e);
                    await sync.refresh();
                  }),
                ),
              ),
            ),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Vị trí cập nhật mỗi vài phút, mã hoá trong lịch chung. Kéo xuống để làm mới.', textAlign: TextAlign.center),
          ),
        ]),
      );

  String _me(Member m) => m.email == sync.email ? 'Tôi' : m.label;

  void _sheet(BuildContext context, Member m) => showModalBottomSheet(
        context: context,
        builder: (s) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(title: Text(_me(m), style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text(status(m))),
            ListTile(
              leading: const Icon(Icons.timeline),
              title: const Text('Lộ trình hôm nay'),
              onTap: () {
                Navigator.pop(s);
                Navigator.push(context, MaterialPageRoute(builder: (_) => RouteScreen(
                      title: _me(m),
                      points: track.since(m.email == sync.email ? Track.mine : view.ref.id, m.email, _today()),
                    )));
              },
            ),
            if (view.ref.owner && m.email != sync.email)
              ListTile(
                leading: const Icon(Icons.person_remove_outlined, color: Colors.red),
                title: const Text('Mời ra khỏi sợi tơ'),
                onTap: () {
                  Navigator.pop(s);
                  guard(context, () async {
                    await sync.kick(view.ref, m.email);
                    await sync.refresh();
                  });
                },
              ),
          ]),
        ),
      );
}

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

/// SC-05: lộ trình vẽ ngay trên máy (không dùng Maps SDK vì bắt buộc gắn thẻ thanh toán).
/// Xem trên bản đồ thật: mở Google Maps chỉ đường qua tối đa 8 điểm trung gian.
class RouteScreen extends StatelessWidget {
  final String title;
  final List<Fix> points;
  const RouteScreen({super.key, required this.title, required this.points});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('Lộ trình hôm nay · $title')),
        body: points.length < 2
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Hôm nay chưa đủ điểm để vẽ lộ trình.\nĐiểm chỉ được ghi khi người ấy di chuyển và đang chia sẻ.',
                      textAlign: TextAlign.center),
                ),
              )
            : Column(children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: CustomPaint(size: Size.infinite, painter: RoutePainter(points, Theme.of(context).colorScheme.primary)),
                  ),
                ),
                Text('${hm(DateTime.fromMillisecondsSinceEpoch(points.first.t))} → ${hm(DateTime.fromMillisecondsSinceEpoch(points.last.t))} · '
                    '${(routeMeters(points) / 1000).toStringAsFixed(1)} km · ${points.length} điểm'),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton.icon(
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Xem trên Google Maps'),
                    onPressed: () => launchUrl(directionsUrl(points), mode: LaunchMode.externalApplication),
                  ),
                ),
              ]),
      );
}

double routeMeters(List<Fix> p) => [for (var i = 1; i < p.length; i++) p[i - 1].metersTo(p[i])].fold(0.0, (a, b) => a + b);

/// Link chỉ đường Google Maps qua lộ trình (lấy mẫu đều ≤ 8 điểm trung gian — giới hạn của link trên điện thoại).
Uri directionsUrl(List<Fix> p) {
  final mid = p.length <= 2 ? <Fix>[] : [for (var i = 1; i <= 8; i++) p[(i * (p.length - 1)) ~/ 9]];
  return Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'origin': p.first.latLng,
    'destination': p.last.latLng,
    if (mid.isNotEmpty) 'waypoints': mid.map((f) => f.latLng).toSet().join('|'),
    'travelmode': 'driving',
  });
}

class RoutePainter extends CustomPainter {
  final List<Fix> pts;
  final Color color;
  RoutePainter(this.pts, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final lats = pts.map((p) => p.lat), lngs = pts.map((p) => p.lng);
    final minLat = lats.reduce((a, b) => a < b ? a : b), maxLat = lats.reduce((a, b) => a > b ? a : b);
    final minLng = lngs.reduce((a, b) => a < b ? a : b), maxLng = lngs.reduce((a, b) => a > b ? a : b);
    // Cùng một thang cho cả hai trục để đường đi không bị méo.
    final span = [maxLat - minLat, maxLng - minLng, 1e-4].reduce((a, b) => a > b ? a : b);
    final scale = size.shortestSide / span;
    Offset at(Fix p) => Offset((p.lng - minLng) * scale, size.height - (p.lat - minLat) * scale);
    final path = Path()..moveTo(at(pts.first).dx, at(pts.first).dy);
    for (final p in pts.skip(1)) {
      path.lineTo(at(p).dx, at(p).dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 5
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round);
    canvas.drawCircle(at(pts.first), 9, Paint()..color = Colors.green);
    canvas.drawCircle(at(pts.last), 9, Paint()..color = color);
  }

  @override
  bool shouldRepaint(RoutePainter old) => old.pts != pts;
}

// ---------------- Kế hoạch ----------------

class _Plans extends StatefulWidget {
  final Sync sync;
  final CircleRef ref;
  const _Plans({required this.sync, required this.ref});
  @override
  State<_Plans> createState() => _PlansState();
}

class _PlansState extends State<_Plans> {
  late Future<List<cal.Event>> _f = widget.sync.plans(widget.ref);
  void _reload() => setState(() => _f = widget.sync.plans(widget.ref));

  Future<void> _add() async {
    final r = await showDialog<_PlanInput>(context: context, builder: (_) => const _PlanDialog());
    if (r == null || !mounted) return;
    await guard(context, () => widget.sync.addPlan(widget.ref, title: r.title, start: r.start, place: r.place, note: r.note));
    _reload();
  }

  Future<void> _delete(cal.Event e) async {
    if (!await confirm(context, 'Xoá kế hoạch?', e.summary ?? '', 'Xoá') || !mounted) return;
    await guard(context, () => widget.sync.deleteEvent(widget.ref, e.id!));
    _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton: FloatingActionButton(tooltip: 'Thêm kế hoạch', onPressed: _add, child: const Icon(Icons.add)),
        body: _EventList(
          future: _f,
          onRefresh: _reload,
          empty: 'Chưa có kế hoạch nào.\nKế hoạch thêm ở đây hiện luôn trong Google Calendar của cả hai, có nhắc lịch.',
          tile: (e) => ListTile(
            leading: const Icon(Icons.event, color: rose),
            title: Text(e.summary ?? '(không tên)'),
            subtitle: Text([_when(e), if (e.location?.isNotEmpty == true) e.location!].join(' · ')),
            onLongPress: () => _delete(e),
          ),
        ),
      );
}

String _when(cal.Event e) {
  final d = e.start?.dateTime?.toLocal() ?? e.start?.date;
  if (d == null) return '';
  final day = '${d.day}/${d.month}/${d.year}';
  return e.start?.dateTime == null ? day : '${hm(d)} · $day';
}

class _PlanInput {
  final String title;
  final DateTime start;
  final String? place, note;
  const _PlanInput(this.title, this.start, this.place, this.note);
}

class _PlanDialog extends StatefulWidget {
  const _PlanDialog();
  @override
  State<_PlanDialog> createState() => _PlanDialogState();
}

class _PlanDialogState extends State<_PlanDialog> {
  final _title = TextEditingController(), _place = TextEditingController(), _note = TextEditingController();
  DateTime _at = DateTime.now().add(const Duration(days: 1)).copyWith(hour: 19, minute: 0, second: 0, millisecond: 0, microsecond: 0);

  Future<void> _pick() async {
    final d = await showDatePicker(
        context: context, initialDate: _at, firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime(2100));
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_at));
    if (t == null) return;
    setState(() => _at = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Kế hoạch mới'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: _title, autofocus: true, decoration: const InputDecoration(labelText: 'Làm gì? (vd. Đi xem phim)')),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: Text('${hm(_at)} · ${_at.day}/${_at.month}/${_at.year}'),
              onTap: _pick,
            ),
            TextField(controller: _place, decoration: const InputDecoration(labelText: 'Ở đâu (tuỳ chọn)')),
            const SizedBox(height: 8),
            TextField(controller: _note, decoration: const InputDecoration(labelText: 'Ghi chú (tuỳ chọn)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Huỷ')),
          FilledButton(
            onPressed: () {
              if (_title.text.trim().isEmpty) return;
              Navigator.pop(context, _PlanInput(_title.text.trim(), _at, _orNull(_place.text), _orNull(_note.text)));
            },
            child: const Text('Lưu'),
          ),
        ],
      );
}

String? _orNull(String s) => s.trim().isEmpty ? null : s.trim();

// ---------------- Kỷ niệm ----------------

class _Memories extends StatefulWidget {
  final Sync sync;
  final CircleRef ref;
  const _Memories({required this.sync, required this.ref});
  @override
  State<_Memories> createState() => _MemoriesState();
}

class _MemoriesState extends State<_Memories> {
  late Future<List<cal.Event>> _f = widget.sync.memories(widget.ref);
  void _reload() => setState(() => _f = widget.sync.memories(widget.ref));

  Future<void> _add() async {
    final r = await showDialog<_MemoryInput>(context: context, builder: (_) => const _MemoryDialog());
    if (r == null || !mounted) return;
    await guard(context, () => widget.sync.addMemory(widget.ref, title: r.title, day: r.day, note: r.note, photo: r.photo));
    _reload();
  }

  Future<void> _delete(cal.Event e) async {
    if (!await confirm(context, 'Xoá kỷ niệm?', e.summary ?? '', 'Xoá') || !mounted) return;
    await guard(context, () => widget.sync.deleteEvent(widget.ref, e.id!));
    _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton: FloatingActionButton(tooltip: 'Thêm kỷ niệm', onPressed: _add, child: const Icon(Icons.favorite)),
        body: _EventList(
          future: _f,
          onRefresh: _reload,
          empty: 'Chưa có kỷ niệm nào.\nLưu lại ngày đầu gặp nhau, chuyến đi đầu tiên… kèm một tấm ảnh.',
          tile: (e) {
            final photo = e.attachments?.firstOrNull?.fileUrl;
            final note = e.description ?? '';
            return ListTile(
              leading: const Icon(Icons.favorite, color: rose),
              title: Text((e.summary ?? '').replaceFirst('💗 ', '')),
              subtitle: Text([_when(e), if (note.isNotEmpty) note].join('\n')),
              isThreeLine: note.isNotEmpty,
              trailing: photo == null
                  ? null
                  : IconButton(
                      tooltip: 'Xem ảnh',
                      icon: const Icon(Icons.photo_outlined),
                      onPressed: () => launchUrl(Uri.parse(photo), mode: LaunchMode.externalApplication),
                    ),
              onLongPress: () => _delete(e),
            );
          },
        ),
      );
}

class _MemoryInput {
  final String title;
  final DateTime day;
  final String? note;
  final File? photo;
  const _MemoryInput(this.title, this.day, this.note, this.photo);
}

class _MemoryDialog extends StatefulWidget {
  const _MemoryDialog();
  @override
  State<_MemoryDialog> createState() => _MemoryDialogState();
}

class _MemoryDialogState extends State<_MemoryDialog> {
  final _title = TextEditingController(), _note = TextEditingController();
  DateTime _day = DateTime.now();
  File? _photo;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Kỷ niệm mới'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: _title, autofocus: true, decoration: const InputDecoration(labelText: 'Tên kỷ niệm')),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.today),
              title: Text('${_day.day}/${_day.month}/${_day.year}'),
              onTap: () async {
                final d = await showDatePicker(context: context, initialDate: _day, firstDate: DateTime(1950), lastDate: DateTime(2100));
                if (d != null) setState(() => _day = d);
              },
            ),
            TextField(controller: _note, maxLines: 3, decoration: const InputDecoration(labelText: 'Ghi lại đôi dòng')),
            const SizedBox(height: 8),
            if (_photo != null) ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(_photo!, height: 120, fit: BoxFit.cover)),
            TextButton.icon(
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(_photo == null ? 'Thêm ảnh (lưu trong Google Drive của bạn)' : 'Đổi ảnh'),
              onPressed: () async {
                final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
                if (x != null) setState(() => _photo = File(x.path));
              },
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Huỷ')),
          FilledButton(
            onPressed: () {
              if (_title.text.trim().isEmpty) return;
              Navigator.pop(context, _MemoryInput(_title.text.trim(), _day, _orNull(_note.text), _photo));
            },
            child: const Text('Lưu'),
          ),
        ],
      );
}

/// Danh sách sự kiện có kéo-để-làm-mới và báo lỗi rõ ràng.
class _EventList extends StatelessWidget {
  final Future<List<cal.Event>> future;
  final VoidCallback onRefresh;
  final String empty;
  final Widget Function(cal.Event) tile;
  const _EventList({required this.future, required this.onRefresh, required this.empty, required this.tile});

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: future,
        builder: (_, s) {
          if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (s.hasError) {
            return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(friendly(s.error!), textAlign: TextAlign.center)));
          }
          final items = s.data!;
          return RefreshIndicator(
            onRefresh: () async => onRefresh(),
            child: items.isEmpty
                ? ListView(children: [Padding(padding: const EdgeInsets.all(32), child: Text(empty, textAlign: TextAlign.center))])
                : ListView(padding: const EdgeInsets.only(bottom: 88), children: [for (final e in items) Card(child: tile(e))]),
          );
        },
      );
}

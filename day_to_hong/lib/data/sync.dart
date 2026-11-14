import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:googleapis/calendar/v3.dart' as cal;
import 'package:googleapis/drive/v3.dart' as drive;

import '../core/crypto.dart';
import '../core/geo.dart';
import 'google.dart';
import 'store.dart';

const coupleMax = 2;
const familyMax = 10;

/// Loại sự kiện app tự đánh dấu trong extendedProperties.shared['dth'].
const kLoc = 'loc', kSos = 'sos', kMemory = 'memory', kPlan = 'plan';

/// Lộ trình gửi kèm vị trí: điểm của mình trong 2 giờ gần nhất, tối đa 60 điểm (~3 KB mô tả sự kiện).
const trailWindow = Duration(hours: 2);
const trailMax = 60;

class Member {
  final String email, name;
  final Fix? fix;
  final List<Fix> trail;
  final bool paused, locked;
  final DateTime? pausedUntil;
  const Member(this.email,
      {this.name = '', this.fix, this.trail = const [], this.paused = false, this.locked = false, this.pausedUntil});

  String get label => locked ? email : (name.isEmpty ? email.split('@').first : name);
}

/// Giải mã sự kiện 📍 của một thành viên. Sai khoá/bị sửa → locked (vẫn hiện email, không sập luồng).
Future<Member> decodeMember(List<int> key, String email, String? box) async {
  if (box == null || box.isEmpty) return Member(email, locked: true);
  try {
    final j = await Box.open(key, box);
    return Member(
      email,
      name: j['name'] as String? ?? '',
      fix: j['fix'] == null ? null : Fix.unpack(j['fix'] as List),
      trail: [for (final p in (j['trail'] as List? ?? const [])) Fix.unpack(p as List)],
      paused: j['paused'] == true,
      pausedUntil: j['until'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['until'] as int),
    );
  } catch (_) {
    return Member(email, locked: true);
  }
}

/// Nội dung sự kiện 📍 của mình. Đang tạm ẩn thì không gửi toạ độ và lộ trình.
Map<String, dynamic> memberBody(String email, String name, {Fix? fix, List<Fix> trail = const [], bool paused = false, DateTime? until}) => {
      'email': email,
      'name': name,
      if (!paused && fix != null) 'fix': fix.pack(),
      if (!paused) 'trail': [for (final f in trail.length > trailMax ? trail.sublist(trail.length - trailMax) : trail) f.pack()],
      'paused': paused,
      if (until != null) 'until': until.millisecondsSinceEpoch,
    };

class CircleView {
  final CircleRef ref;
  final List<Member> members;
  final List<String> pending; // email đã mời chưa vào (chỉ chủ thấy)
  final String? error;
  const CircleView(this.ref, this.members, {this.pending = const [], this.error});
}

String friendly(Object e) => switch (e) {
      NeedsConsent() => 'Cần cấp lại quyền Google — mở app và bấm "Cấp quyền".',
      cal.DetailedApiRequestError(status: 404 || 403) => 'Không truy cập được lịch: Gmail này chưa được mời hoặc đã bị gỡ.',
      SocketException() || TimeoutException() => 'Không có mạng — sẽ thử lại.',
      _ => '$e',
    };

/// Đồng bộ qua Google Calendar. Chạy ở cả isolate giao diện và service nền — mọi thao tác idempotent.
class Sync {
  final String email, name;
  final GoogleApis g;
  final Track track;
  void Function(String who, Fix? at)? onSos;

  /// `g`: chỉ test truyền vào (Calendar giả); app dùng GoogleApis thật theo email.
  Sync(this.email, this.name, this.track, {GoogleApis? g}) : g = g ?? GoogleApis(email);

  final circles = ValueNotifier<List<CircleView>>([]);
  final _locIds = <String, String>{}; // calendarId → id sự kiện 📍 của mình

  Future<T> _cal<T>(Future<T> Function(cal.CalendarApi api) f) async {
    try {
      return await f(await g.calendar());
    } on cal.DetailedApiRequestError catch (e) {
      if (e.status != 401) rethrow;
      await g.invalidate();
      return f(await g.calendar());
    }
  }

  // ---------------- Sợi tơ ----------------

  /// Chủ tạo lịch phụ trong Google Calendar của chính mình (miễn phí, không máy chủ).
  Future<CircleRef> create({required bool family}) async {
    final c = await _cal((a) => a.calendars.insert(cal.Calendar(
          summary: family ? 'Dây tơ hồng · Gia đình 💞' : 'Dây tơ hồng 💞',
          description: 'Lịch chung của Dây tơ hồng. Các sự kiện 📍 ngày 01/01/2000 chứa vị trí đã mã hoá — đừng xoá.',
          timeZone: 'Asia/Ho_Chi_Minh',
        )));
    final ref = CircleRef(c.id!, Box.randomKey(), owner: true, family: family);
    await Vault.saveCircles([...await Vault.circles(), ref]);
    await _publishTo(ref, memberBody(email, name, paused: true));
    return ref;
  }

  Future<List<String>> _sharedWith(CircleRef ref) async {
    final acl = await _cal((a) => a.acl.list(ref.id));
    return [
      for (final r in acl.items ?? <cal.AclRule>[])
        if (r.scope?.type == 'user' && r.role != 'owner' && r.scope?.value != null && r.scope!.value!.toLowerCase() != email) r.scope!.value!.toLowerCase(),
    ];
  }

  /// Chia sẻ quyền sửa lịch cho Gmail người thương; Google tự gửi email báo. Trả mã mời để gửi kèm.
  Future<String> invite(CircleRef ref, String who) async {
    final shared = await _sharedWith(ref);
    if (!shared.contains(who) && shared.length + 1 >= (ref.family ? familyMax : coupleMax)) {
      throw StateError('Sợi tơ đã đủ ${ref.family ? familyMax : coupleMax} người.');
    }
    await _cal((a) => a.acl.insert(cal.AclRule(role: 'writer', scope: cal.AclRuleScope(type: 'user', value: who)), ref.id));
    return Invite(ref.id, ref.key).encode();
  }

  String inviteCode(CircleRef ref) => Invite(ref.id, ref.key).encode();

  /// Người được mời dán mã. Google từ chối nếu Gmail đang đăng nhập không được chia sẻ lịch → "chỉ tài khoản đã đăng ký".
  Future<void> join(String code) async {
    final inv = Invite.parse(code);
    if (inv == null) throw StateError('Mã mời không đúng. Hãy dán nguyên đoạn bắt đầu bằng DTH1.');
    final mine = await Vault.circles();
    if (mine.any((c) => c.id == inv.calendarId)) return;
    try {
      await _cal((a) => a.calendarList.insert(cal.CalendarListEntry(id: inv.calendarId)));
    } on cal.DetailedApiRequestError catch (e) {
      if (e.status != 409) rethrow; // đã có trong danh sách lịch (vd. bấm nhận từ email Google) — vẫn tham gia được
    }
    final ref = CircleRef(inv.calendarId, inv.key);
    await Vault.saveCircles([...mine, ref]);
    await _publishTo(ref, memberBody(email, name, paused: true));
  }

  /// Chủ rời = xoá cả lịch. Thành viên rời: xoá vị trí của mình rồi bỏ lịch khỏi danh sách.
  Future<void> leave(CircleRef ref) async {
    if (ref.owner) {
      await _cal((a) => a.calendars.delete(ref.id));
    } else {
      final id = await _myLocId(ref);
      if (id != null) await _cal((a) => a.events.delete(ref.id, id));
      await _cal((a) => a.calendarList.delete(ref.id));
    }
    await Vault.saveCircles([for (final c in await Vault.circles()) if (c.id != ref.id) c]);
    track.forget(ref.id);
    circles.value = [for (final c in circles.value) if (c.ref.id != ref.id) c];
  }

  /// Gỡ quyền của một người: Google chặn họ đọc lịch ngay, nên không cần đổi khoá.
  Future<void> kick(CircleRef ref, String who) async {
    await _cal((a) => a.acl.delete(ref.id, 'user:$who'));
    for (final e in await _events(ref, kLoc)) {
      if (e.extendedProperties?.shared?['who'] == who) await _cal((a) => a.events.delete(ref.id, e.id!));
    }
  }

  // ---------------- Vị trí ----------------

  Future<List<cal.Event>> _events(CircleRef ref, String kind, {DateTime? updatedMin}) async =>
      (await _cal((a) => a.events.list(ref.id, sharedExtendedProperty: ['dth=$kind'], updatedMin: updatedMin, maxResults: 250))).items ??
      [];

  Future<String?> _myLocId(CircleRef ref) async {
    final cached = _locIds[ref.id];
    if (cached != null) return cached;
    for (final e in await _events(ref, kLoc)) {
      if (e.extendedProperties?.shared?['who'] == email) return _locIds[ref.id] = e.id!;
    }
    return null;
  }

  Future<void> _publishTo(CircleRef ref, Map<String, dynamic> body) async {
    final ev = cal.Event(
      summary: '📍 Dây tơ hồng · $name (đừng xoá)',
      description: await Box.seal(ref.key, body),
      start: cal.EventDateTime(date: DateTime.utc(2000, 1, 1)),
      end: cal.EventDateTime(date: DateTime.utc(2000, 1, 2)),
      transparency: 'transparent',
      extendedProperties: cal.EventExtendedProperties(shared: {'dth': kLoc, 'who': email}),
    );
    final id = await _myLocId(ref);
    try {
      if (id != null) {
        await _cal((a) => a.events.patch(ev, ref.id, id));
        return;
      }
    } on cal.DetailedApiRequestError catch (e) {
      if (e.status != 404 && e.status != 410) rethrow; // ai đó xoá mất sự kiện 📍 → tạo lại
      _locIds.remove(ref.id);
    }
    _locIds[ref.id] = (await _cal((a) => a.events.insert(ev, ref.id))).id!;
  }

  /// Gửi trạng thái của mình tới mọi sợi tơ. Trả số sợi tơ lỗi (không nuốt lỗi im lặng).
  Future<int> publish({Fix? fix, bool paused = false, DateTime? until}) async {
    final trail = track.since(Track.mine, email, DateTime.now().subtract(trailWindow));
    final body = memberBody(email, name, fix: fix, trail: trail, paused: paused, until: until);
    var failed = 0;
    for (final ref in await Vault.circles()) {
      try {
        await _publishTo(ref, body);
      } catch (e) {
        failed++;
        debugPrint('publish ${ref.id}: $e');
      }
    }
    return failed;
  }

  /// Đọc vị trí mọi người + SOS mới. Lộ trình nhận được ghi vào SQLite trên máy.
  Future<void> refresh() async {
    final out = <CircleView>[];
    for (final ref in await Vault.circles()) {
      try {
        final members = <Member>[];
        for (final e in await _events(ref, kLoc)) {
          final who = e.extendedProperties?.shared?['who'];
          if (who == null) continue;
          if (who == email) _locIds[ref.id] = e.id!;
          final m = await decodeMember(ref.key, who, e.description);
          for (final f in [...m.trail, ?m.fix]) {
            track.add(ref.id, who, f);
          }
          members.add(m);
        }
        await _sos(ref, members);
        final pending = ref.owner ? [for (final e in await _sharedWith(ref)) if (!members.any((m) => m.email == e)) e] : <String>[];
        out.add(CircleView(ref, members, pending: pending));
      } catch (e) {
        final old = circles.value.where((c) => c.ref.id == ref.id).firstOrNull;
        out.add(CircleView(ref, old?.members ?? const [], pending: old?.pending ?? const [], error: friendly(e)));
      }
    }
    circles.value = out;
  }

  Future<void> _sos(CircleRef ref, List<Member> members) async {
    for (final e in await _events(ref, kSos, updatedMin: DateTime.now().subtract(const Duration(hours: 1)))) {
      final who = e.extendedProperties?.shared?['who'];
      if (who == null || who == email || !track.firstSeen('sos:${e.id}')) continue;
      Fix? at;
      try {
        final j = await Box.open(ref.key, e.extendedProperties!.shared!['box'] ?? '');
        at = j['fix'] == null ? null : Fix.unpack(j['fix'] as List);
      } catch (_) {}
      onSos?.call(members.where((m) => m.email == who).firstOrNull?.label ?? who, at);
    }
  }

  /// SOS: sự kiện 30 phút hiện cả trong Google Calendar, kèm link bản đồ dạng rõ (khẩn cấp quan trọng hơn mã hoá).
  Future<int> sos(Fix? fix) async {
    var sent = 0;
    final now = DateTime.now();
    for (final ref in await Vault.circles()) {
      await _cal((a) async => a.events.insert(
            cal.Event(
              summary: '🆘 SOS — $name cần giúp đỡ',
              description: fix == null ? 'Không có vị trí kèm theo — hãy gọi ngay.' : 'Vị trí: https://maps.google.com/?q=${fix.latLng}',
              start: cal.EventDateTime(dateTime: now.toUtc()),
              end: cal.EventDateTime(dateTime: now.add(const Duration(minutes: 30)).toUtc()),
              extendedProperties: cal.EventExtendedProperties(shared: {
                'dth': kSos,
                'who': email,
                'box': await Box.seal(ref.key, {if (fix != null) 'fix': fix.pack()}),
              }),
            ),
            ref.id,
          ));
      sent++;
    }
    return sent;
  }

  // ---------------- Kế hoạch & kỷ niệm (dạng thường, hiện trong Google Calendar) ----------------

  /// Mọi sự kiện sắp tới trong lịch chung, kể cả do người dùng tạo thẳng trong Google Calendar; bỏ 📍/SOS/kỷ niệm.
  Future<List<cal.Event>> plans(CircleRef ref) async {
    final now = DateTime.now();
    final r = await _cal((a) => a.events.list(ref.id,
        timeMin: now.subtract(const Duration(days: 1)).toUtc(),
        timeMax: now.add(const Duration(days: 180)).toUtc(),
        singleEvents: true,
        orderBy: 'startTime',
        maxResults: 100));
    return [
      for (final e in r.items ?? <cal.Event>[])
        if (!{kLoc, kSos, kMemory}.contains(e.extendedProperties?.shared?['dth'])) e,
    ];
  }

  Future<void> addPlan(CircleRef ref, {required String title, required DateTime start, Duration length = const Duration(hours: 1), String? place, String? note}) =>
      _cal((a) => a.events.insert(
            cal.Event(
              summary: title,
              location: place,
              description: note,
              start: cal.EventDateTime(dateTime: start.toUtc()),
              end: cal.EventDateTime(dateTime: start.add(length).toUtc()),
              reminders: cal.EventReminders(useDefault: true),
              extendedProperties: cal.EventExtendedProperties(shared: {'dth': kPlan, 'who': email}),
            ),
            ref.id,
          ));

  Future<List<cal.Event>> memories(CircleRef ref) async =>
      (await _events(ref, kMemory))..sort((a, b) => (b.start?.date ?? DateTime(0)).compareTo(a.start?.date ?? DateTime(0)));

  /// Kỷ niệm = sự kiện cả ngày "💗 …". Ảnh tải lên Drive của người đăng (drive.file), chia sẻ riêng cho từng thành viên.
  Future<void> addMemory(CircleRef ref, {required String title, required DateTime day, String? note, File? photo}) async {
    cal.EventAttachment? att;
    if (photo != null) {
      final d = await g.drive_();
      final len = await photo.length();
      final f = await d.files.create(
        drive.File(name: 'Dây tơ hồng · $title.jpg', mimeType: 'image/jpeg'),
        uploadMedia: drive.Media(photo.openRead(), len, contentType: 'image/jpeg'),
        $fields: 'id,webViewLink',
      );
      final others = {
        for (final m in circles.value.where((c) => c.ref.id == ref.id).firstOrNull?.members ?? const <Member>[])
          if (m.email != email) m.email,
      };
      for (final who in others) {
        await d.permissions.create(drive.Permission(type: 'user', role: 'reader', emailAddress: who), f.id!, sendNotificationEmail: false);
      }
      att = cal.EventAttachment(fileUrl: f.webViewLink, fileId: f.id, title: title, mimeType: 'image/jpeg');
    }
    final date = DateTime.utc(day.year, day.month, day.day);
    await _cal((a) => a.events.insert(
          cal.Event(
            summary: '💗 $title',
            description: note,
            start: cal.EventDateTime(date: date),
            end: cal.EventDateTime(date: date.add(const Duration(days: 1))),
            transparency: 'transparent',
            attachments: att == null ? null : [att],
            extendedProperties: cal.EventExtendedProperties(shared: {'dth': kMemory, 'who': email}),
          ),
          ref.id,
          supportsAttachments: true,
        ));
  }

  Future<void> deleteEvent(CircleRef ref, String eventId) => _cal((a) => a.events.delete(ref.id, eventId));

  /// Xoá dữ liệu: rời mọi sợi tơ (sợi tơ mình tạo bị xoá cả lịch). Không có tài khoản phía nhà phát triển để xoá.
  Future<int> leaveAll() async {
    var failed = 0;
    for (final ref in await Vault.circles()) {
      try {
        await leave(ref);
      } catch (e) {
        failed++;
      }
    }
    return failed;
  }
}

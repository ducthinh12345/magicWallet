import 'package:day_to_hong/app/pro.dart';
import 'package:day_to_hong/core/crypto.dart';
import 'package:day_to_hong/core/geo.dart';
import 'package:day_to_hong/data/store.dart';
import 'package:day_to_hong/data/sync.dart';
import 'package:day_to_hong/ui/circle.dart' show directionsUrl;
import 'package:day_to_hong/ui/home.dart' show normalizeEmail, status;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'fake_calendar.dart';

void main() {
  group('Box & Invite', () {
    test('mã hoá rồi giải mã đúng; bản mã không lộ toạ độ; sai khoá/bị sửa → lỗi', () async {
      final k = Box.randomKey();
      final box = await Box.seal(k, {'lat': 10.7769});
      expect(box.contains('10.7769'), isFalse);
      expect(await Box.open(k, box), {'lat': 10.7769});
      await expectLater(Box.open(Box.randomKey(), box), throwsA(anything));
      final bytes = box.codeUnits.toList()..[20] = box.codeUnitAt(20) == 65 ? 66 : 65;
      await expectLater(Box.open(k, String.fromCharCodes(bytes)), throwsA(anything));
    });

    test('mã mời: mã hoá/giải mã, tìm được trong tin nhắn dán kèm chữ, từ chối mã hỏng', () {
      final inv = Invite('abc123@group.calendar.google.com', Box.randomKey());
      final back = Invite.parse('Anh ơi dán mã này nhé:\n${inv.encode()}\nyêu anh')!;
      expect(back.calendarId, inv.calendarId);
      expect(back.key, inv.key);
      expect(Invite.parse('DTH1.abc.def'), isNull);
      expect(Invite.parse(inv.encode().substring(0, 30)), isNull);
    });
  });

  group('Fix & Throttle', () {
    Fix at(double dLat, int sec, {double acc = 10}) => Fix(10.0 + dLat, 106.0, acc, sec * 1000); // 0.0003° ≈ 33 m

    test('pack/unpack giữ ~1 m và giây', () {
      final f = Fix.unpack(const Fix(10.123456789, 106.987654321, 12.6, 1700000000123).pack());
      expect(f.lat, 10.12346);
      expect(f.lng, 106.98765);
      expect(f.acc, 13);
      expect(f.t, 1700000000000);
    });

    test('bỏ sai số lớn; cần ≥ 25 m VÀ ≥ 20 s', () {
      final t = Throttle();
      expect(t.take(at(0, 0, acc: 150)), isFalse);
      expect(t.take(at(0, 0)), isTrue);
      expect(t.take(at(0.0003, 10)), isFalse);
      expect(t.take(at(0.00001, 60)), isFalse);
      expect(t.take(at(0.0003, 60)), isTrue);
    });
  });

  group('memberBody / decodeMember', () {
    final k = Box.randomKey();
    const f = Fix(10.1, 106.2, 5, 1700000000000);

    test('khứ hồi qua mã hoá; lộ trình bị cắt còn 60 điểm mới nhất', () async {
      final trail = [for (var i = 0; i < 100; i++) Fix(10, 106, 5, i * 1000)];
      final m = await decodeMember(k, 'a@x.vn', await Box.seal(k, memberBody('a@x.vn', 'Linh', fix: f, trail: trail)));
      expect(m.name, 'Linh');
      expect(m.fix!.lat, 10.1);
      expect(m.trail.length, trailMax);
      expect(m.trail.first.t, 40000);
    });

    test('tạm ẩn: không gửi toạ độ lẫn lộ trình', () async {
      final until = DateTime(2026, 11, 14, 20);
      final body = memberBody('a@x.vn', 'Linh', fix: f, trail: [f], paused: true, until: until);
      expect(body.containsKey('fix'), isFalse);
      expect(body.containsKey('trail'), isFalse);
      final m = await decodeMember(k, 'a@x.vn', await Box.seal(k, body));
      expect(m.paused, isTrue);
      expect(m.pausedUntil, until);
    });

    test('sai khoá hoặc mô tả trống → locked, không ném lỗi', () async {
      expect((await decodeMember(Box.randomKey(), 'a@x.vn', await Box.seal(k, memberBody('a@x.vn', 'L')))).locked, isTrue);
      expect((await decodeMember(k, 'a@x.vn', null)).locked, isTrue);
    });
  });

  test('normalizeEmail', () {
    expect(normalizeEmail('  Minh.Nguyen@GMAIL.com '), 'minh.nguyen@gmail.com');
    expect(normalizeEmail('minh'), isNull);
    expect(normalizeEmail('a b@gmail.com'), isNull);
  });

  test('createBlock: miễn phí 1 sợi tơ đôi; gia đình cần Pro; Pro tối đa 5', () {
    expect(createBlock(pro: false, family: false, ownedCircles: 0), isNull);
    expect(createBlock(pro: false, family: false, ownedCircles: 1), isNotNull);
    expect(createBlock(pro: false, family: true, ownedCircles: 0), contains('Gói Gia đình'));
    expect(createBlock(pro: true, family: true, ownedCircles: 4), isNull);
    expect(createBlock(pro: true, family: false, ownedCircles: 5), isNotNull);
  });

  test('status', () {
    final now = DateTime(2026, 11, 14, 12);
    Member m(int minsAgo) => Member('u', fix: Fix(0, 0, 5, now.subtract(Duration(minutes: minsAgo)).millisecondsSinceEpoch));
    expect(status(m(0), now), 'Cập nhật vừa xong');
    expect(status(m(12), now), 'Cập nhật 12 phút trước');
    expect(status(m(45), now), contains('có thể đã tắt máy'));
    expect(status(const Member('u', paused: true), now), 'Đang ẩn vị trí');
    expect(status(const Member('u', locked: true), now), startsWith('Chưa giải mã'));
  });

  test('directionsUrl: tối đa 8 điểm trung gian, đầu/cuối đúng', () {
    final pts = [for (var i = 0; i < 50; i++) Fix(10 + i / 1000, 106, 5, i)];
    final u = directionsUrl(pts);
    expect(u.queryParameters['origin'], pts.first.latLng);
    expect(u.queryParameters['destination'], pts.last.latLng);
    expect(u.queryParameters['waypoints']!.split('|').length, lessThanOrEqualTo(8));
  });

  group('Track (SQLite)', () {
    late Track t;
    setUp(() => t = Track(sqlite3.openInMemory()));

    test('trùng điểm không nhân đôi; since lọc người/thời gian, xếp theo giờ; firstSeen một lần', () {
      t.add('c', 'u', const Fix(1, 1, 5, 2000));
      t.add('c', 'u', const Fix(1, 1, 5, 2000));
      t.add('c', 'u', const Fix(2, 2, 5, 1000));
      t.add('c', 'v', const Fix(3, 3, 5, 1500));
      expect([for (final f in t.since('c', 'u', DateTime.fromMillisecondsSinceEpoch(0))) f.t], [1000, 2000]);
      expect(t.firstSeen('sos:1'), isTrue);
      expect(t.firstSeen('sos:1'), isFalse);
    });

    test('prune 30 ngày; forget theo sợi tơ', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      t.add('c', 'u', Fix(1, 1, 5, DateTime.now().subtract(const Duration(days: 31)).millisecondsSinceEpoch));
      t.add('c', 'u', Fix(1, 1, 5, now));
      t.add('d', 'u', Fix(1, 1, 5, now));
      t.prune();
      expect(t.since('c', 'u', DateTime(2000)).length, 1);
      t.forget('c');
      expect(t.since('c', 'u', DateTime(2000)), isEmpty);
      expect(t.since('d', 'u', DateTime(2000)).length, 1);
    });
  });

  group('Luồng hai người trên Google Calendar giả', () {
    // Mỗi "máy" có Keystore riêng: đổi bộ nhớ giả của flutter_secure_storage khi chuyển máy.
    final devices = <String, Map<String, String>>{'linh': {}, 'minh': {}, 'eve': {}};
    Future<T> on<T>(String who, Future<T> Function() f) async {
      FlutterSecureStorage.setMockInitialValues(devices[who]!);
      try {
        return await f();
      } finally {
        devices[who] = await const FlutterSecureStorage().readAll();
      }
    }

    test('tạo → mời → Gmail lạ bị chặn → nhập mã → thấy vị trí, lộ trình của nhau → SOS báo đúng một lần → mời ra', () async {
      final fake = FakeCalendar();
      final tl = Track(sqlite3.openInMemory()), tm = Track(sqlite3.openInMemory()), te = Track(sqlite3.openInMemory());
      final linh = Sync('linh@gmail.com', 'Linh', tl, g: FakeApis('linh@gmail.com', fake));
      final minh = Sync('minh@gmail.com', 'Minh', tm, g: FakeApis('minh@gmail.com', fake));
      final eve = Sync('eve@gmail.com', 'Eve', te, g: FakeApis('eve@gmail.com', fake));

      final code = await on('linh', () async {
        final ref = await linh.create(family: false);
        return linh.invite(ref, 'minh@gmail.com');
      });
      // Sợi tơ đôi: mời người thứ ba bị chặn.
      await on('linh', () async => expect(() async => linh.invite((await Vault.circles()).single, 'ba@gmail.com'), throwsStateError));

      // Có mã nhưng sai Gmail → Google từ chối, không lưu sợi tơ.
      await on('eve', () async {
        await expectLater(eve.join(code), throwsA(anything));
        expect(await Vault.circles(), isEmpty);
      });

      // Minh nhập mã kèm chữ thừa, rồi gửi vị trí đang di chuyển.
      final t0 = DateTime.now().subtract(const Duration(minutes: 10)).millisecondsSinceEpoch;
      final p1 = Fix(10.80, 106.70, 8, t0), p2 = Fix(10.81, 106.71, 8, t0 + 60000);
      await on('minh', () async {
        await minh.join('Mã đây: $code');
        tm.add(Track.mine, minh.email, p1);
        tm.add(Track.mine, minh.email, p2);
        expect(await minh.publish(fix: p2), 0);
      });

      // Linh thấy Minh (giải mã được) và lộ trình của Minh nằm trong SQLite máy Linh.
      await on('linh', () async {
        await linh.publish(fix: const Fix(10.7, 106.6, 5, 1700000000000));
        await linh.refresh();
        final v = linh.circles.value.single;
        expect(v.error, isNull);
        final m = v.members.firstWhere((m) => m.email == 'minh@gmail.com');
        expect(m.name, 'Minh');
        expect(m.locked, isFalse);
        expect(m.fix!.lat, 10.81);
        expect(v.pending, isEmpty);
        expect(tl.since(v.ref.id, 'minh@gmail.com', DateTime(2000)).length, 2);
      });

      // Mô tả sự kiện 📍 trên "Google" không chứa toạ độ dạng rõ.
      final cid = fake.calendars.keys.single;
      final descs = [for (final e in (fake.calendars[cid]!['events'] as Map).values) '${e['description']}'];
      expect(descs.any((d) => d.contains('10.81')), isFalse);

      // Minh tạm ẩn → Linh thấy "đang ẩn", không thấy toạ độ.
      await on('minh', () => minh.publish(paused: true));
      await on('linh', () async {
        await linh.refresh();
        final m = linh.circles.value.single.members.firstWhere((m) => m.email == 'minh@gmail.com');
        expect(m.paused, isTrue);
        expect(m.fix, isNull);
      });

      // SOS của Minh báo cho Linh đúng một lần dù làm mới nhiều lần; Minh không tự nhận SOS của mình.
      final got = <String>[];
      linh.onSos = (who, at) => got.add('$who@${at?.lat}');
      minh.onSos = (who, at) => got.add('self');
      await on('minh', () => minh.sos(p2));
      await on('linh', () => linh.refresh());
      await on('linh', () => linh.refresh());
      await on('minh', () => minh.refresh());
      expect(got, ['Minh@10.81']);

      // Linh mời Minh ra → Google chặn Minh đọc lịch, Minh thấy lỗi dễ hiểu thay vì sập.
      await on('linh', () async {
        await linh.kick((await Vault.circles()).single, 'minh@gmail.com');
        await linh.refresh();
        expect(linh.circles.value.single.members.map((m) => m.email), ['linh@gmail.com']);
      });
      await on('minh', () async {
        await minh.refresh();
        expect(minh.circles.value.single.error, contains('chưa được mời hoặc đã bị gỡ'));
      });

      // Linh xoá sợi tơ → lịch biến mất khỏi "Google".
      await on('linh', () async {
        await linh.leave((await Vault.circles()).single);
        expect(await Vault.circles(), isEmpty);
      });
      expect(fake.calendars, isEmpty);
    });
  });
}

import 'dart:convert';

import 'package:day_to_hong/data/google.dart';
import 'package:googleapis/calendar/v3.dart' as cal;
import 'package:http/http.dart' as http;

/// Google Calendar giả trong bộ nhớ, đủ các endpoint lib/data/sync.dart dùng, kèm luật quyền như Google thật:
/// chỉ chủ hoặc email có ACL mới đọc/ghi được lịch; thêm lịch vào danh sách khi không có ACL → 404.
class FakeCalendar {
  final calendars = <String, Map<String, dynamic>>{}; // id → {owner, acl: Set<String>, events: Map<id, json>}
  var _seq = 0;

  http.Client clientFor(String email) => _Client(this, email);

  http.Response handle(String who, String method, Uri u, Map<String, dynamic>? body) {
    final seg = u.pathSegments.skipWhile((s) => s != 'v3').skip(1).toList();
    json(Object o, [int code = 200]) => http.Response(jsonEncode(o), code, headers: {'content-type': 'application/json'});
    final err = http.Response('{"error":{"code":404,"message":"Not Found"}}', 404, headers: {'content-type': 'application/json'});

    if (method == 'POST' && seg.length == 1 && seg[0] == 'calendars') {
      final id = 'c${++_seq}@group.calendar.google.com';
      calendars[id] = {'owner': who, 'acl': <String>{}, 'events': <String, Map<String, dynamic>>{}, 'meta': body};
      return json({...?body, 'id': id});
    }
    if (seg.length >= 3 && seg[0] == 'users' && seg[1] == 'me' && seg[2] == 'calendarList') {
      final id = method == 'POST' ? body!['id'] as String : Uri.decodeComponent(seg[3]);
      final c = calendars[id];
      if (c == null || (c['owner'] != who && !(c['acl'] as Set<String>).contains(who))) return err;
      return method == 'DELETE' ? http.Response('', 204) : json({'id': id});
    }
    if (seg.isEmpty || seg[0] != 'calendars') return err;
    final id = Uri.decodeComponent(seg[1]);
    final c = calendars[id];
    if (c == null) return err;
    final owner = c['owner'] == who;
    final acl = c['acl'] as Set<String>;
    if (!owner && !acl.contains(who)) return err;
    final events = c['events'] as Map<String, Map<String, dynamic>>;

    if (seg.length == 2 && method == 'DELETE') {
      if (!owner) return err;
      calendars.remove(id);
      return http.Response('', 204);
    }
    if (seg.length >= 3 && seg[2] == 'acl') {
      if (!owner) return http.Response('{"error":{"code":403,"message":"Forbidden"}}', 403);
      if (method == 'GET') {
        return json({
          'items': [
            {'role': 'owner', 'scope': {'type': 'user', 'value': who}},
            for (final e in acl) {'role': 'writer', 'scope': {'type': 'user', 'value': e}},
          ]
        });
      }
      if (method == 'POST') {
        acl.add((body!['scope'] as Map)['value'] as String);
        return json(body);
      }
      acl.remove(Uri.decodeComponent(seg[3]).replaceFirst('user:', ''));
      return http.Response('', 204);
    }
    if (seg.length >= 3 && seg[2] == 'events') {
      if (method == 'POST') {
        final eid = 'e${++_seq}';
        events[eid] = {...body!, 'id': eid, 'updated': DateTime.now().toUtc().toIso8601String()};
        return json(events[eid]!);
      }
      if (seg.length == 4) {
        final eid = seg[3];
        if (!events.containsKey(eid)) return err;
        if (method == 'DELETE') {
          events.remove(eid);
          return http.Response('', 204);
        }
        if (method == 'PATCH') {
          events[eid] = {...events[eid]!, ...body!, 'updated': DateTime.now().toUtc().toIso8601String()};
          return json(events[eid]!);
        }
      }
      // GET list: lọc sharedExtendedProperty=k=v như Google.
      final filters = u.queryParametersAll['sharedExtendedProperty'] ?? const [];
      final items = events.values.where((e) {
        final shared = ((e['extendedProperties'] as Map?)?['shared'] as Map?) ?? const {};
        return filters.every((f) => shared[f.split('=')[0]] == f.split('=')[1]);
      }).toList();
      return json({'items': items});
    }
    return err;
  }
}

class _Client extends http.BaseClient {
  final FakeCalendar cal_;
  final String who;
  _Client(this.cal_, this.who);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest r) async {
    final raw = await r.finalize().bytesToString(); // googleapis gửi body dạng stream
    final body = raw.isEmpty ? null : jsonDecode(raw) as Map<String, dynamic>;
    final res = cal_.handle(who, r.method, r.url, body);
    return http.StreamedResponse(Stream.value(res.bodyBytes), res.statusCode, headers: res.headers, request: r);
  }
}

/// GoogleApis dùng Calendar giả thay vì token thật.
class FakeApis extends GoogleApis {
  final FakeCalendar fake;
  FakeApis(super.email, this.fake);
  @override
  Future<cal.CalendarApi> calendar() async => cal.CalendarApi(fake.clientFor(email));
}

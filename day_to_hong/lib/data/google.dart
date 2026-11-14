import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:googleapis/calendar/v3.dart' as cal;
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

/// Quyền Google tối thiểu. Tất cả thuộc nhóm "nhạy cảm"/thường, không có scope "hạn chế" → xác minh OAuth miễn phí, không CASA.
const googleScopes = [
  cal.CalendarApi.calendarAppCreatedScope, // tạo/xoá lịch phụ "Dây tơ hồng" của mình
  cal.CalendarApi.calendarAclsScope, // chia sẻ lịch đó cho Gmail người thương
  cal.CalendarApi.calendarCalendarlistScope, // người được mời thêm lịch vào danh sách của họ
  cal.CalendarApi.calendarEventsScope, // đọc/ghi sự kiện trên lịch người khác chia sẻ cho mình
  drive.DriveApi.driveFileScope, // ảnh kỷ niệm: chỉ thấy file app tự tải lên
];

/// OAuth client "Web application" (Google Cloud, miễn phí, không cần thanh toán) — dùng cho bước chọn tài khoản trên Android.
const serverClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

class _Bearer extends http.BaseClient {
  final String token;
  final _inner = http.Client();
  _Bearer(this.token);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest r) {
    r.headers['Authorization'] = 'Bearer $token';
    // Không có timeout thì một lần mạng treo làm service nền đứng mãi.
    return _inner.send(r).timeout(const Duration(seconds: 30));
  }
}

/// Lấy access token theo đúng email — chạy được cả trong service nền (không cần Activity khi không phải hỏi lại quyền).
class GoogleApis {
  final String email;
  GoogleApis(this.email);

  static bool _inited = false;
  static Future<void> init() async {
    if (_inited) return;
    await GoogleSignInPlatform.instance.init(const InitParameters(serverClientId: serverClientId));
    _inited = true;
  }

  String? _token;
  DateTime _at = DateTime(2000);

  /// `prompt`: chỉ true khi người dùng vừa bấm nút (hiện hộp thoại cấp quyền). Null = chưa cấp quyền.
  Future<String?> token({bool prompt = false}) async {
    if (_token != null && DateTime.now().difference(_at) < const Duration(minutes: 45)) return _token;
    await init();
    final r = await GoogleSignInPlatform.instance.clientAuthorizationTokensForScopes(ClientAuthorizationTokensForScopesParameters(
      request: AuthorizationRequestDetails(scopes: googleScopes, userId: null, email: email, promptIfUnauthorized: prompt),
    ));
    _token = r?.accessToken;
    _at = DateTime.now();
    return _token;
  }

  /// Token bị Google thu hồi/hết hạn sớm (401) → bỏ cache để lần sau xin lại.
  Future<void> invalidate() async {
    final t = _token;
    _token = null;
    if (t != null) await GoogleSignInPlatform.instance.clearAuthorizationToken(ClearAuthorizationTokenParams(accessToken: t));
  }

  Future<http.Client> _client() async {
    final t = await token();
    if (t == null) throw const NeedsConsent();
    return _Bearer(t);
  }

  Future<cal.CalendarApi> calendar() async => cal.CalendarApi(await _client());
  Future<drive.DriveApi> drive_() async => drive.DriveApi(await _client());
}

/// Người dùng cần mở app để cấp (lại) quyền Google.
class NeedsConsent implements Exception {
  const NeedsConsent();
  @override
  String toString() => 'Cần mở app để cấp quyền Google';
}

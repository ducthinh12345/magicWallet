# Build Dây tơ hồng trên máy khác — tóm tắt

> App Flutter (Android). **Không server, không phí**: dữ liệu đi qua Google Calendar/Drive của người dùng.
> Chi tiết nghiệp vụ: `../Tài liệu thiết kế nghiệp vụ – Dây tơ hồng.md` · Kiến trúc & giới hạn: `README.md` · Phát hành Play: `docs/release/play-store.md`.

## 0. Mang code sang
Thư mục `day_to_hong/` **chưa được commit** (tính tới 2026-11-14). Trước khi sang máy mới: commit + push vào repo
(`origin` hiện là `github.com:ducthinh12345/magicWallet.git`, repo chung với Ví Ma Thuật), hoặc copy cả thư mục, bỏ `build/` và `.dart_tool/`.

## 1. Công cụ (phiên bản đã build thành công)
| Công cụ | Phiên bản | Ghi chú |
| --- | --- | --- |
| Flutter | 3.47.9 stable (Dart 3.13.7) | `pubspec.yaml` yêu cầu Dart ≥ 3.13.7 |
| JDK | **17** | Đặt `JAVA_HOME` trỏ vào JDK 17 trước khi build |
| Android SDK | platform **android-37**, build-tools 36.0.0, NDK 28.2.13676358 | `compileSdk = 37` (plugin androidx bắt buộc) |
| Gradle / AGP / Kotlin | 9.3.1 / 9.1.0 / 2.4.0 | Tự tải qua wrapper, không cần cài |

```sh
flutter doctor --android-licenses   # chấp nhận license
sdkmanager "platforms;android-37.0" "build-tools;36.0.0" "ndk;28.2.13676358"
```

## 2. Khoá ký (không có trong git — copy bằng kênh an toàn)
- File keystore: `vimathuat-upload.jks` (dùng chung với Ví Ma Thuật), alias `upload`,
  SHA-1 `94:CA:17:17:27:3E:B3:93:B2:C8:EF:22:54:0A:79:23:E5:04:3B:0C`.
- Tạo `android/key.properties` (đã nằm trong `.gitignore`):
  ```properties
  storePassword=<mật khẩu>
  keyPassword=<mật khẩu>
  keyAlias=upload
  storeFile=/đường/dẫn/tuyệt/đối/tới/vimathuat-upload.jks
  ```
- Thiếu file này thì bản release **tự ký bằng khoá debug** → Play từ chối. Mất keystore thì phải xin Google đặt lại upload key.

## 3. Cấu hình Google (một lần cho cả dự án, miễn phí, KHÔNG gắn thẻ thanh toán)
Nếu đã làm trên máy cũ thì chỉ cần mang theo client ID, bỏ qua bước này.
1. Google Cloud Console › dự án › bật **Google Calendar API** và **Google Drive API**.
2. OAuth consent screen (External): thêm 5 scope — `calendar.app.created`, `calendar.acls`, `calendar.calendarlist`,
   `calendar.events`, `drive.file`; thêm Gmail thử nghiệm (≤ 100 người khi chưa xác minh).
3. Credentials: OAuth client **Web application** → lấy client ID (dùng ở bước 4);
   OAuth client **Android**: package `vn.vimathuat.day_to_hong` + SHA-1 ở mục 2 (và SHA-1 Play App Signing sau lần tải lên đầu).

## 4. Build
```sh
cd day_to_hong
export JAVA_HOME=<đường dẫn JDK 17>
flutter pub get
flutter analyze && flutter test        # mong đợi: No issues found! · All tests passed! (14 test)

DEFS="--dart-define=GOOGLE_SERVER_CLIENT_ID=<client-web>.apps.googleusercontent.com --dart-define=PRIVACY_URL=https://<trang chính sách>"
flutter build apk --debug $DEFS          # cài thử: adb install -r build/app/outputs/flutter-apk/app-debug.apk
flutter build appbundle --release $DEFS  # → build/app/outputs/bundle/release/app-release.aab
```
- Thêm `--dart-define=DEV_PRO=true` vào bản **debug** để thử Gói Gia đình không cần mua (bản release luôn bỏ qua cờ này).
- Trước mỗi lần tải lên Play: tăng `version:` trong `pubspec.yaml` (số sau dấu `+` phải tăng).
- Thiếu `GOOGLE_SERVER_CLIENT_ID` → app chỉ hiện màn "Bản build thiếu GOOGLE_SERVER_CLIENT_ID".

## 5. Kiểm bản build
```sh
keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab | grep SHA1   # phải khớp SHA-1 ở mục 2
$ANDROID_HOME/build-tools/36.0.0/aapt2 dump xmltree build/app/outputs/flutter-apk/app-debug.apk --file AndroidManifest.xml \
  | grep -E 'foregroundServiceType|BACKGROUND_LOCATION|BILLING'
# mong đợi: foregroundServiceType=0x8 (location), có com.android.vending.BILLING, KHÔNG có ACCESS_BACKGROUND_LOCATION
```

## 6. Lỗi đã gặp
| Triệu chứng | Cách xử lý |
| --- | --- |
| `Cannot lock execution history cache … already locked by this process` | Gradle daemon cũ kẹt khoá: `cd android && ./gradlew --stop`; vẫn kẹt thì `./gradlew bundleRelease --no-daemon` (lần đầu ~45 phút) |
| `No space left on device` | Build release cần vài GB trống; xoá `build/` rồi build lại |
| Lỗi đòi compile với API 37 | Cài `platforms;android-37.0` (mục 1) |
| `Unable to locate a Java Runtime` khi chạy `keytool` | Dùng `$JAVA_HOME/bin/keytool` |
| Đăng nhập Google hỏng trên bản tải từ Play | Thiếu OAuth client Android với SHA-1 **Play App Signing** (mục 3) |

## 7. Đổi icon (tuỳ chọn)
Sửa `assets/icon/full.svg` / `foreground.svg` → xuất PNG 1024 (macOS: `qlmanage -t -s 1024 -o . full.svg`) → `dart run flutter_launcher_icons`.

## 8. Còn phải làm trước khi phát hành
Chưa gọi Google Calendar/Drive thật lần nào (Calendar giả trong `test/fake_calendar.dart` mô phỏng theo tài liệu).
Thử trên **hai máy Android với hai Gmail**: mời → nhập mã → bật chia sẻ → thấy vị trí trong ≤ 3 phút → thêm kế hoạch (hiện trong
Google Calendar máy kia) → thêm kỷ niệm có ảnh → SOS → tạm ẩn → mời ra. Sau đó làm theo `docs/release/play-store.md`.

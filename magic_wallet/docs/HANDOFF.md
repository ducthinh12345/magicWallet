# Bàn giao – tiếp tục Ví Ma Thuật trên máy khác

Cập nhật: 2026-11-14. Repo: `git@github.com:ducthinh12345/magicWallet.git`, app nằm trong `magic_wallet/`.

## 1. Lấy code
```sh
git clone git@github.com:ducthinh12345/magicWallet.git && cd magicWallet/magic_wallet
git config --local user.name "<tên>" && git config --local user.email "<email noreply GitHub>"
flutter pub get
```

## 2. Thứ KHÔNG có trong git – phải chép tay (qua kênh an toàn, không gửi chat/email thường)
| File | Dùng cho | Thiếu thì sao |
| --- | --- | --- |
| `~/.android/vimathuat-upload.jks` | Ký bản phát hành CH Play | **Mất là không cập nhật được app trên Play** (phải xin Google reset upload key). Sao lưu vào trình quản lý mật khẩu. |
| `magic_wallet/android/key.properties` | Mật khẩu + đường dẫn tới file .jks | Build release lỗi ký. Sửa `storeFile` nếu đường dẫn home khác. `chmod 600`. |
| `~/.android/debug.keystore` | Đăng nhập Google trên bản debug | Máy mới sinh khoá debug khác → đăng nhập Google báo lỗi. Hoặc chép file này, hoặc thêm SHA-1 debug mới vào OAuth client Android trên Google Cloud. |
| `magic_wallet/dist/app-release.aab` | Bản AAB cũ (12:52 14/11) | Không cần – build lại được, và bản này còn thiếu sửa lỗi thanh trạng thái. |

SHA-1 hiện đăng ký: upload `94:CA:17:17:27:3E:B3:93:B2:C8:EF:22:54:0A:79:23:E5:04:3B:0C`, debug `20:86:EB:4A:A5:91:61:53:F6:53:81:11:C9:F5:EB:87:EF:AD:B3:8E`.

## 3. Cài môi trường (macOS)
- Flutter stable 3.47.x, JDK 17, Android SDK (platform `android-37.0`, compileSdk 37, minSdk 26).
- Xcode (đã chấp nhận license: `sudo xcodebuild -license accept`) – cần cho cả `flutter test` vì sqlite3 build native.
- iOS dùng **Swift Package Manager**, không cần CocoaPods: `flutter config --enable-swift-package-manager`.
- Ổ đĩa: để trống ≥ 10 GB (build iOS + Android + simulator).

## 4. Lệnh thường dùng
```sh
flutter test                                   # 63 unit test
flutter analyze
# Android debug, Pro trọn đời, dữ liệu mẫu (máy thật qua cáp)
flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=155791156180-v34sldhq71c71lbuob9q9fffroeeu22l.apps.googleusercontent.com \
  --dart-define=DEV_PRO_LIFETIME=true
# Bản phát hành CH Play (tăng version trong pubspec.yaml trước)
flutter build appbundle --release --dart-define=GOOGLE_SERVER_CLIENT_ID=155791156180-v34sldhq71c71lbuob9q9fffroeeu22l.apps.googleusercontent.com
# Web (cổng 7357 đã khai báo origin trên Google Cloud)
flutter build web --dart-define=GOOGLE_WEB_CLIENT_ID=155791156180-v34sldhq71c71lbuob9q9fffroeeu22l.apps.googleusercontent.com
cd build/web && python3 -m http.server 7357
# iOS simulator: smoke test bấm qua 4 tab
flutter test integration_test/smoke_test.dart --dart-define=DEMO_SEED=true --dart-define=DEV_PRO_LIFETIME=true -d <id simulator>
```
Cờ: `DEMO_SEED` (dữ liệu mẫu), `DEV_PRO_LIFETIME` (Pro, chỉ bản debug), `GOOGLE_SERVER_CLIENT_ID` (Android), `GOOGLE_WEB_CLIENT_ID` (web), `GOOGLE_IOS_CLIENT_ID` (iOS).

## 5. Trạng thái
**Đã chạy và kiểm chứng:** Android (Redmi Note 11 Pro 5G, HyperOS) – ghi tự động từ thông báo TPBank, đồng bộ Google Sheets giữa điện thoại và web, sao lưu mã hoá, Pro trọn đời bản debug; web; iOS simulator (iPhone 18 Pro, iOS 27.2) – mở app + 4 tab không lỗi.

**Việc còn lại:**
1. Build lại AAB (có sửa thanh trạng thái) rồi làm theo `docs/release/play-store.md` (Play Console, sản phẩm `pro_yearly`/`pro_lifetime`, thêm SHA-1 Play App Signing vào Google Cloud).
2. Điền và đăng `docs/release/privacy-policy.md` lên URL công khai.
3. iOS: tạo OAuth client loại iOS cho bundle `vn.vimathuat.magicWallet`, điền `ios/Flutter/GoogleSignIn.xcconfig`; thử trên iPhone thật (Face ID, thông báo, StoreKit) – cần Apple Developer. Xem `docs/release/ios.md`.
4. `assets/institutions.json`: tên gói app ngân hàng (trừ TPBank) **chưa kiểm chứng** trên máy thật.
5. Google Cloud OAuth consent: chuyển Testing → In production trước khi phát hành.

**Lưu ý đã gặp:** HyperOS chặn `adb shell input tap` (cần bật "USB debugging (Security settings)" nếu muốn điều khiển); adb chập chờn với cáp kém; `flutter drive` trên simulator iOS bị treo khi kết nối – dùng `flutter test integration_test/...` thay thế; Chrome do công cụ tự động mở bị Google chặn đăng nhập – dùng Chrome cá nhân.

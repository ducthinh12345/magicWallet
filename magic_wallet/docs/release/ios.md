# iOS – build và phát hành

> Mã và cấu hình iOS đã viết nhưng **chưa build, chưa chạy thử**: máy phát triển hiện không có Xcode.
> Lần build đầu có thể lộ lỗi cấu hình cần sửa.

## Đã có trong mã
| Hạng mục | Vị trí |
| --- | --- |
| Tên hiển thị "Ví Ma Thuật", Face ID, URL scheme đăng nhập Google | `ios/Runner/Info.plist` |
| iOS 16 trở lên (NFR-15) | `ios/Runner.xcodeproj/project.pbxproj` |
| Đăng nhập Google bằng client iOS | `lib/sync/google.dart` (`GOOGLE_IOS_CLIENT_ID`) + `ios/Flutter/GoogleSignIn.xcconfig` |
| Mua Pro qua App Store (StoreKit 2); hết hạn gói năm phát hiện qua `currentEntitlements` | `lib/pro/billing.dart` |
| Chữ "App Store", cách huỷ gói theo iOS | `lib/ui/pro_screen.dart` |
| Che nội dung trong trình chuyển ứng dụng (thay FLAG_SECURE) | `PrivacyCover` trong `lib/ui/widgets.dart` |
| Không hỏi quyền thông báo khi mở app; chỉ hỏi khi người dùng bấm | `lib/services.dart` |
| Icon iOS (không kênh alpha) | `ios/Runner/Assets.xcassets/AppIcon.appiconset` |

Nguồn tự động trên iOS: email hoá đơn (Apps Script) và nhập sao kê CSV. iOS không cho đọc thông báo của app khác (mục 5.1).

## Chưa làm trên iOS
- S6: Siri / Phím tắt (App Intents) và chia sẻ ảnh chụp màn hình vào app để OCR — cần mã Swift gốc.
- OCR biên lai (S4) — chưa làm trên cả hai nền tảng.

## Các bước để build (trên máy Mac có Xcode)
1. Cài **Xcode** từ App Store, rồi:
   ```sh
   sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
   sudo xcodebuild -runFirstLaunch
   brew install cocoapods
   ```
2. **Google Cloud › Credentials › Create OAuth client ID › iOS**, bundle ID `vn.vimathuat.magicWallet`.
   Sửa `ios/Flutter/GoogleSignIn.xcconfig`: thay `REPLACE_WITH_IOS_CLIENT_PREFIX` bằng phần đầu của client ID
   (`123-abc.apps.googleusercontent.com` → `com.googleusercontent.apps.123-abc`).
3. Mở `ios/Runner.xcworkspace` › Runner › *Signing & Capabilities*: chọn Team (Apple Developer Program, 99 USD/năm),
   thêm capability **In-App Purchase**.
4. Chạy thử:
   ```sh
   cd magic_wallet
   flutter run -d <iPhone> --dart-define=GOOGLE_IOS_CLIENT_ID=<client-ios>.apps.googleusercontent.com
   ```
   Lần đầu Flutter tự tạo `ios/Podfile`. Nếu `pod install` báo phiên bản iOS quá thấp, đặt `platform :ios, '16.0'` trong Podfile.

## App Store Connect
1. Tạo app, bundle ID `vn.vimathuat.magicWallet`.
2. **Gói đăng ký**: nhóm "Pro", Product ID `pro_yearly`, 1 năm. **Mua trong app** (non-consumable): `pro_lifetime`.
   Mã sản phẩm phải trùng với Android (`lib/pro/pro.dart`).
3. **Quyền riêng tư (Privacy Nutrition Label)**: "Data Not Collected" (cùng lý do như mục Data safety trên Play — cần xác nhận lại theo hướng dẫn của Apple).
4. **Mã hoá (Export Compliance)**: app dùng AES để bảo vệ dữ liệu người dùng. Trả lời câu hỏi mã hoá khi nộp bản build,
   hoặc khai `ITSAppUsesNonExemptEncryption` trong Info.plist sau khi pháp chế xác nhận (mục 10.2.2).
5. Build bản phát hành và tải lên TestFlight:
   ```sh
   flutter build ipa --dart-define=GOOGLE_IOS_CLIENT_ID=<client-ios>.apps.googleusercontent.com
   ```
   Tải `build/ios/ipa/*.ipa` lên bằng app Transporter hoặc Xcode Organizer.

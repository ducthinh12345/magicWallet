# Ví Ma Thuật — quản lý chi tiêu local-first

Cài đặt theo tài liệu `../Tài liệu thiết kế nghiệp vụ – Ứng dụng Quản lý Chi tiêu Cá nhân Local-first.md`.
Flutter (Android ưu tiên, iOS, PWA) + Drift/SQLite3MultipleCiphers. Không có backend.

## Chạy

```sh
flutter pub get
flutter test                       # 54 test: nghiệp vụ, thu thập, báo cáo, đồng bộ, sao lưu, mã hoá
flutter run -d chrome --web-port 7357
flutter build apk --debug          # cần JDK 17, Android SDK platform 37
```

Đồng bộ Google cần OAuth client ID của bạn (Google Cloud Console, bật Sheets API + Drive API):

```sh
flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=xxx.apps.googleusercontent.com   # Android: client loại "Web application"
flutter run -d chrome --dart-define=GOOGLE_WEB_CLIENT_ID=xxx.apps.googleusercontent.com
```
Android còn cần một client loại "Android" khớp package `vn.vimathuat.magic_wallet` + SHA-1 của khoá ký.

## Cấu trúc

| Thư mục | Nội dung | Mục tài liệu |
| --- | --- | --- |
| `lib/core` | Đọc "45k/1tr2", định dạng 1.250.000 đ, kỳ tuần/tháng tài chính/quý/năm | US-01 AC4, BR-03/04/05 |
| `lib/data` | 9 bảng + `setting`, UUID v7, xoá mềm, nhật ký đồng bộ, số dư, đối soát, định kỳ | Mục 8, BR-01/07, M01–M03 |
| `lib/capture` | Parser thông báo, lọc OTP, phân loại (quy tắc → từ điển → Naive Bayes), chống trùng 5 phút, ghép nạp ví, nhập sao kê CSV | Mục 5 |
| `assets/institutions.json` | 25 ngân hàng/ví — thêm tổ chức chỉ cần sửa file này | 5.5, NFR-14 |
| `lib/reports` | Báo cáo tuần/tháng/quý/năm, hoàn tiền trừ chi, nhận xét tự động, ngân sách 80/100%, chuyển dư | Mục 7, M05 |
| `lib/sync` | Google Sheets 2 chiều (phát hiện sửa tay bằng chữ ký dòng, xung đột, dòng bị xoá), sao lưu Argon2id + AES-256-GCM lên appDataFolder, giữ 30 bản | Mục 6 |
| `lib/ui` | 4 tab + nút "+", SC-01…SC-11 | Mục 9 |
| `android/.../WalletNotificationListener.kt` | Đọc thông báo app trong whitelist, chạy Dart nền (`captureMain`) | S1/S2 |
| `assets/apps_script.gs` | Script người dùng tự cài để đổ email hoá đơn vào tab "Hộp thư" | S3 phương án A |

## Đã kiểm chứng (cách đo lại)

- `flutter test` → 54/54 xanh.
- Mã hoá DB: `test/encryption_test.dart` đọc bytes file DB thật — không có header `SQLite format 3`, không lộ chuỗi, sai khoá không mở được.
- `flutter build apk --debug` thành công; APK có `lib/arm64-v8a/libsqlite3mc.so`, minSdk 26, không có quyền `READ_SMS`
  (`aapt2 dump xmltree build/app/outputs/flutter-apk/app-debug.apk --file AndroidManifest.xml`).
- Bản web chạy trong Chrome: onboarding → nhập "2tr5" → ghi 45k Cà phê → số dư 2.455.000 đ, báo cáo tháng đúng, console không lỗi.

## Chưa kiểm chứng

- **Chưa chạy trên điện thoại Android thật / emulator**: NotificationListenerService, engine nền, khoá sinh trắc học, FLAG_SECURE, thông báo hẹn giờ.
- **Tên package Android của 25 tổ chức** trong `institutions.json` viết theo hiểu biết, chưa đối chiếu trên máy thật.
- **Thông báo mẫu trong test là tự soạn**, chưa phải thông báo thật thu từ người thử nghiệm → NFR-10 (≥ 99%) chưa đo được. `patterns` của từng tổ chức đang rỗng (dùng parser chung).
- Đồng bộ Google: thuật toán test bằng Sheet giả; **chưa gọi API thật** (cần client ID). Công thức SUMIFS, định dạng cột ngày, bảo vệ cột chưa thử trên Sheets thật.
- iOS: chưa build (máy chưa có Xcode đầy đủ).
- NFR hiệu năng (khởi động ≤ 1,5 s, báo cáo năm 10.000 giao dịch ≤ 1 s) chưa đo.

## Chưa làm (ngoài phạm vi lần này)

Gói Pro + Play Billing/IAP và giới hạn bản miễn phí · OCR biên lai (S4) · iOS Shortcuts (S6) · tạo mẫu bằng bôi đen số tiền, tải gói mẫu ký số (5.3) ·
đa tiền tệ trên UI (DB đã có cột) · xuất PDF · widget màn hình chính (SC-12) · Ví gia đình (M11) · Mục tiêu tiết kiệm (M09), Nợ & cho vay (M10) ·
tiếng Anh · đồng bộ nền khi app đóng (hiện đồng bộ khi mở app và mỗi 30 giây lúc app mở) · kéo về sửa tay ở tab Danh mục/Ngân sách (chỉ tab Giao dịch hai chiều).

## Hạn chế đã biết

- Bản web: SQLite **không mã hoá** (tài liệu yêu cầu IndexedDB mã hoá Web Crypto) và không có thông báo hệ thống.
- File `.vrbackup` là JSON mã hoá (không phải file SQLite mã hoá như tài liệu ghi) — để khôi phục được trên mọi nền tảng.
- Sheet đặt locale `en_US` để công thức dùng dấu phẩy.
- Định kỳ chỉ hiểu `FREQ` + `INTERVAL`; ngày 31 bị kẹp rồi trôi.
- Lệnh chuyển dư ngân sách chỉ mang dư của 1 kỳ liền trước.

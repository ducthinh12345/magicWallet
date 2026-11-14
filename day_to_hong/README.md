# Dây tơ hồng — vị trí, kế hoạch, kỷ niệm của riêng hai người

Thiết kế: `../Tài liệu thiết kế nghiệp vụ – Dây tơ hồng.md`. Flutter, Android trước.
**Không server, không tốn phí vận hành.** Mỗi sợi tơ là một **lịch phụ Google Calendar** của người tạo, chia sẻ quyền sửa
cho Gmail người được mời. Vị trí mã hoá AES-256-GCM (khoá nằm trong mã mời) trong sự kiện 📍; kế hoạch và kỷ niệm là sự kiện
thường, hiện luôn trong app Google Calendar của cả hai. Ảnh kỷ niệm nằm trong Google Drive của người đăng. Lộ trình 30 ngày ở SQLite trên máy.

Phát hành: [`docs/release/play-store.md`](docs/release/play-store.md) · Chính sách: [`docs/release/privacy-policy.md`](docs/release/privacy-policy.md)

## Cấu trúc
| Đường dẫn | Nội dung |
| --- | --- |
| `lib/core/crypto.dart` | `Box` (AES-GCM), `Invite` — mã mời `DTH1.<id lịch>.<khoá>` |
| `lib/core/geo.dart` | `Fix` (gói gọn ~1 m), `Throttle` (≥ 25 m & ≥ 20 s, sai số ≤ 100 m) |
| `lib/data/google.dart` | Scope tối thiểu, lấy token theo email (chạy được trong service nền) |
| `lib/data/sync.dart` | Tạo/mời/nhập mã/rời/mời ra, gửi & đọc vị trí + lộ trình, SOS, kế hoạch, kỷ niệm |
| `lib/data/store.dart` | `Track` (SQLite, dùng chung 2 isolate), `Vault` (Keystore: khoá sợi tơ, email, tạm ẩn, Pro) |
| `lib/app/tracker.dart` | Foreground service loại `location`, đồng bộ mỗi 3 phút, nhịp tim 15 phút |
| `lib/app/pro.dart` | Play Billing `family_lifetime` 299.000 đ |
| `lib/ui/` | Đăng nhập, trang chủ, sợi tơ (Vị trí · Kế hoạch · Kỷ niệm), lộ trình vẽ trên máy, Pro, Cài đặt |
| `test/fake_calendar.dart` | Google Calendar giả có luật quyền như thật, để test trọn luồng hai người |

## Cấu hình Google (một lần, miễn phí — không gắn thẻ)
1. Google Cloud Console › tạo dự án › **bật Google Calendar API và Google Drive API**. **Không** bật thanh toán (dự án không có
   tài khoản thanh toán thì không thể bị tính tiền; vượt hạn mức chỉ bị chặn tạm).
2. OAuth consent screen: loại External, thêm 5 scope trong `lib/data/google.dart`, thêm Gmail thử nghiệm (≤ 100 người khi chưa xác minh).
3. Credentials: tạo OAuth client **Web application** (lấy client ID → `GOOGLE_SERVER_CLIENT_ID`) và client **Android**
   (package `vn.vimathuat.day_to_hong` + SHA-1 upload key; sau lần tải lên Play đầu tiên thêm SHA-1 Play App Signing).

## Chạy / build
```sh
export JAVA_HOME=/Users/user/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
DEFS="--dart-define=GOOGLE_SERVER_CLIENT_ID=….apps.googleusercontent.com --dart-define=PRIVACY_URL=https://…"
flutter run $DEFS
flutter build appbundle --release $DEFS          # thêm --dart-define=DEV_PRO=true cho bản debug thử Pro
```
Thiếu `GOOGLE_SERVER_CLIENT_ID` thì app mở màn hình "Bản build thiếu GOOGLE_SERVER_CLIENT_ID" thay vì sập.
Nếu `flutter build` báo `Cannot lock execution history cache`: một Gradle daemon cũ kẹt khoá → `cd android && ./gradlew --stop`,
còn kẹt thì `./gradlew bundleRelease --no-daemon`.

## Đã kiểm chứng (cách đo lại)
- `flutter analyze` → không lỗi. `flutter test` → 14/14, gồm **luồng hai người trên Calendar giả** (`test/fake_calendar.dart`, có luật
  quyền như Google): tạo → mời → sợi tơ đôi chặn người thứ 3 → Gmail lạ có mã vẫn bị chặn → nhập mã kèm chữ thừa → thấy vị trí và
  lộ trình của nhau → mô tả sự kiện không lộ toạ độ → tạm ẩn ẩn toạ độ → SOS báo đúng một lần → mời ra → xoá sợi tơ.
  Đối chứng: cố tình bỏ chống báo SOS trùng / cho tạm ẩn vẫn gửi toạ độ → test đỏ đúng chỗ.
- `flutter build apk --debug` thành công; manifest (`aapt2 dump xmltree … AndroidManifest.xml`): service `foregroundServiceType=location`,
  có `BILLING`, **không** có `ACCESS_BACKGROUND_LOCATION`, `RECEIVE_BOOT_COMPLETED`, khoá Maps.

## Chưa kiểm chứng
- **Chưa gọi Google Calendar/Drive thật và chưa chạy trên điện thoại** (cần OAuth client ID). Calendar giả mô phỏng theo tài liệu,
  không phải Google: cần thử thật việc `calendarList.insert` khi có ACL, giới hạn độ dài mô tả sự kiện (~3 KB đang dùng),
  `extendedProperties` chứa SOS, đính kèm ảnh.
- Lấy token trong service nền: đã đọc mã plugin (chỉ cần Activity khi phải hỏi quyền), chưa chạy thật.
- Pin, hạn mức thực tế (ước tính ≤ ~1.000 lượt gọi/người/ngày khi chia sẻ cả ngày → dự án chịu được ~1.000 người hoạt động/ngày
  trong hạn mức 1 triệu lượt — chưa đo).

## Hạn chế đã biết
- Vị trí trễ 1–3 phút khi mở app, tới ~3 phút khi chạy nền (đã chốt với người dùng). SOS cũng tới trong vòng vài phút.
- Không bản đồ trong app (Maps SDK bắt buộc thanh toán): xem vị trí/lộ trình bằng nút mở app Google Maps; lộ trình vẽ sơ đồ trên máy.
- SOS lưu dạng rõ (link bản đồ) trong lịch chung để thấy được cả trong Google Calendar.
- Kế hoạch/kỷ niệm dạng thường: Google đọc được như mọi lịch khác (người dùng đã chọn).
- Mời ra một người: Google chặn họ đọc lịch ngay; mã mời cũ vẫn giải mã được bản sao họ đã tải về trước đó.
- Chỉ Android. Không tự bật lại chia sẻ sau khi khởi động lại máy (cố ý: không xin vị trí nền).
- Pro xác minh trên máy (giống Ví Ma Thuật).

# Phát hành Google Play – Ví Ma Thuật

## A. Đã chuẩn bị sẵn trong repo
| Hạng mục | Vị trí | Ghi chú |
| --- | --- | --- |
| Bản phát hành | `build/app/outputs/bundle/release/app-release.aab` | Build lại: lệnh ở mục E |
| Khoá ký (upload key) | `~/.android/vimathuat-upload.jks` + `android/key.properties` | **Không có trong git.** Sao lưu cả 2 vào trình quản lý mật khẩu. SHA-1: `94:CA:17:17:27:3E:B3:93:B2:C8:EF:22:54:0A:79:23:E5:04:3B:0C` |
| Icon | `assets/icon/*.svg` → `dart run flutter_launcher_icons` | Icon thích ứng Android + iOS |
| Chính sách quyền riêng tư | `docs/release/privacy-policy.md` | Điền `[ ]`, luật sư rà, đăng lên một URL công khai |
| Tên gói | `vn.vimathuat.magic_wallet` | Không đổi được sau lần nộp đầu |
| Phiên bản | `pubspec.yaml` → `version: 1.0.0+1` | Mỗi lần tải lên phải tăng số sau dấu `+` |

## B. Việc trên Play Console (theo thứ tự)
1. **Tạo app**: tên "Ví Ma Thuật", ngôn ngữ mặc định Tiếng Việt, loại Ứng dụng, Miễn phí (có mua trong app).
2. **Thử nghiệm › Thử nghiệm nội bộ**: tải `app-release.aab` lên. Lần đầu Play hỏi **Play App Signing** → đồng ý (Google giữ khoá ký chính, bạn giữ upload key).
3. **Lấy SHA-1 của Google** ở *Thiết lập › Tính toàn vẹn của ứng dụng › Ký ứng dụng* ("Chứng chỉ khoá ký ứng dụng"),
   thêm vào Google Cloud: tạo **thêm một OAuth client loại Android** cùng package, SHA-1 đó.
   **Thiếu bước này thì đăng nhập Google hỏng trên bản tải từ Play.** Thêm luôn cả SHA-1 upload key ở bảng trên.
4. **Kiếm tiền › Sản phẩm**:
   - Gói thuê bao: Product ID `pro_yearly`, gói cơ bản tự gia hạn 1 năm, 199.000đ.
   - Sản phẩm trong ứng dụng: Product ID `pro_lifetime`, 499.000đ.
   - Thiết lập › **Thử nghiệm giấy phép**: thêm Gmail của bạn để mua thử không mất tiền.
5. **Nội dung ứng dụng** (mục C, D): Chính sách quyền riêng tư (URL), Quyền truy cập ứng dụng (hướng dẫn cho người duyệt),
   Quảng cáo: *Không*, Xếp hạng nội dung, Đối tượng mục tiêu: *18+*, Data safety, **Tính năng tài chính**, Ứng dụng chính phủ: *Không*.
6. **Trang thông tin** (mục F): mô tả, icon 512×512 (`assets/icon/full.png` thu nhỏ), ảnh nổi bật 1024×500, ≥ 2 ảnh chụp màn hình.
   Chụp màn hình: tạm tắt "Chặn chụp màn hình" trong app (Thêm › Bảo mật).
7. **Thử nghiệm kín** (tài khoản cá nhân mới: ~12 người thử, 14 ngày liên tục — kiểm tra lại quy định lúc nộp) → **Phát hành chính thức**.
8. **Google Cloud › OAuth consent screen**: chuyển *Testing* → *In production*, điền logo, tên miền, URL chính sách; xin xác minh thương hiệu.

## C. Data safety – câu trả lời đề xuất (đối chiếu đúng code hiện tại)
- *Ứng dụng có thu thập hoặc chia sẻ dữ liệu người dùng không?* → **Không**.
  Lý do: mọi xử lý diễn ra trên thiết bị; dữ liệu chỉ gửi tới Google Drive/Sheets **của chính người dùng** theo yêu cầu của họ
  (theo định nghĩa của Play, truyền dữ liệu tới dịch vụ do người dùng chỉ định để họ dùng thì không tính là "thu thập" của nhà phát triển —
  **cần đọc lại hướng dẫn Data safety hiện hành để xác nhận**).
- Dữ liệu được mã hoá khi truyền: **Có** (HTTPS tới googleapis.com).
- Người dùng yêu cầu xoá dữ liệu được: **Có** (Thêm › Xoá toàn bộ dữ liệu; không có tài khoản phía nhà phát triển).

## D. Ghi chú cho người duyệt (dán vào "Quyền truy cập ứng dụng" / phần khai báo quyền)
> Ví Ma Thuật là ứng dụng ghi chép chi tiêu cá nhân. Quyền Truy cập thông báo (NotificationListenerService) chỉ dùng để đọc
> thông báo biến động số dư của các ứng dụng ngân hàng/ví mà người dùng **tự chọn** trong ứng dụng, nhằm tự tạo giao dịch nháp
> chờ người dùng xác nhận. Ứng dụng bỏ qua thông báo của mọi ứng dụng khác, bỏ ngay nội dung có OTP, xử lý hoàn toàn trên thiết bị,
> không gửi nội dung đi đâu. Người dùng phải đồng ý rõ ràng trước khi bật và rút lại được bất cứ lúc nào.
> Ứng dụng không giữ tiền, không chuyển tiền, không kết nối hệ thống ngân hàng. Không cần tài khoản để dùng.

Chuẩn bị thêm **video ngắn** (màn hình điện thoại): bật Ghi tự động → hộp thoại đồng ý → hướng dẫn → cấp quyền → giao dịch vào "Chờ duyệt".

## E. Build lại bản phát hành
```sh
cd magic_wallet
# tăng version trong pubspec.yaml trước, vd 1.0.1+2
flutter build appbundle --release \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=155791156180-v34sldhq71c71lbuob9q9fffroeeu22l.apps.googleusercontent.com
```

## E2. Cấp Pro trọn đời cho máy thử nghiệm nội bộ
Bản **debug** cài qua cáp có thể bật Pro trọn đời không cần mua:
```sh
flutter build apk --debug --dart-define=GOOGLE_SERVER_CLIENT_ID=<client-web> --dart-define=DEV_PRO_LIFETIME=true
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```
Cờ bị khoá bằng `kDebugMode` (`lib/pro/pro.dart`): bản release/AAB **không bao giờ** nhận cờ này dù có truyền vào.
Với bản tải từ CH Play, dùng *Thử nghiệm giấy phép* (mua thử miễn phí) hoặc **mã khuyến mãi** của Play cho `pro_lifetime`.

## F. Trang thông tin – bản nháp
**Tên**: Ví Ma Thuật – Chi tiêu tự động
**Mô tả ngắn (≤ 80 ký tự)**: Ghi chi tiêu tự động từ thông báo ngân hàng. Dữ liệu ở máy bạn.
**Mô tả đầy đủ**:
> Biết tiền đi đâu mà không mất công ghi chép.
> • Tự ghi giao dịch từ thông báo của app ngân hàng, ví điện tử bạn chọn — bạn xác nhận 1 chạm.
> • Gõ nhanh "45k", "1tr2"; danh mục tiếng Việt; nhiều ví; chuyển khoản giữa ví không bị tính là chi.
> • Ngân sách theo tuần/tháng, cảnh báo 80% và 100%, "còn được chi X đ/ngày".
> • Báo cáo tuần, tháng (Pro: quý, năm, bản đồ nhiệt) và nhận xét tự động.
> • Đồng bộ vào Google Sheet của chính bạn; sao lưu mã hoá đầu-cuối lên Google Drive của bạn.
> • Riêng tư: không máy chủ trung gian, không quảng cáo, dữ liệu mã hoá trên máy, khoá bằng vân tay.
> Tên ngân hàng/ví chỉ dùng để mô tả tương thích; Ví Ma Thuật không liên kết hay được bảo trợ bởi tổ chức nào.

Không dùng logo/màu nhận diện ngân hàng, không viết "bảo mật tuyệt đối" hay "được ngân hàng chứng nhận" (mục 10.2.1).

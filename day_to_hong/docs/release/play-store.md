# Phát hành Google Play – Dây tơ hồng

## A. Đã có trong repo
| Hạng mục | Vị trí | Ghi chú |
| --- | --- | --- |
| Khoá ký | `android/key.properties` → `~/.android/vimathuat-upload.jks` | Dùng chung upload key với Ví Ma Thuật. **Không có trong git.** |
| Icon | `assets/icon/*.svg` → `dart run flutter_launcher_icons` | Icon 512×512 cho Play: thu nhỏ `assets/icon/full.png` |
| Tên gói | `vn.vimathuat.day_to_hong` | Không đổi được sau lần nộp đầu |
| OAuth client ID | Google Cloud (README › Cấu hình Google) | Miễn phí, không gắn thanh toán |

## B. Thứ tự trên Play Console
1. Tạo app "Dây tơ hồng", Tiếng Việt, Ứng dụng, Miễn phí (có mua trong app).
2. **Thử nghiệm nội bộ**: tải AAB, đồng ý Play App Signing → lấy SHA-1 ký của Google, tạo thêm OAuth client **Android** với SHA-1 đó
   trong Google Cloud. Thiếu bước này đăng nhập Google hỏng trên bản tải từ Play.
3. **Kiếm tiền › Sản phẩm trong ứng dụng**: `family_lifetime`, 299.000 đ, kích hoạt. Thêm Gmail thử vào *Thử nghiệm giấy phép*.
4. **Nội dung ứng dụng**:
   - Chính sách quyền riêng tư (URL công khai, cùng giá trị `PRIVACY_URL` khi build).
   - **Xoá tài khoản**: app không tạo tài khoản riêng (chỉ đăng nhập Google, không có máy chủ) — kiểm lại câu hỏi này lúc nộp;
     vẫn nêu đường dẫn trong app: Cài đặt › Xoá dữ liệu & rời mọi sợi tơ.
   - **Quyền dịch vụ chạy trên nền trước (Foreground service)**: loại *Location*, mô tả + video (mục D).
   - Không khai báo vị trí nền (app không xin `ACCESS_BACKGROUND_LOCATION`).
   - Quảng cáo: Không. Đối tượng mục tiêu: **13+** (không chọn nhóm dưới 13). Xếp hạng nội dung: điền bảng câu hỏi (có chia sẻ vị trí giữa người dùng).
   - Data safety: mục C.
5. Trang thông tin (mục E), ≥ 2 ảnh chụp màn hình, ảnh nổi bật 1024×500.
6. **Thử nghiệm kín** (tài khoản cá nhân: ~12 người, 14 ngày — kiểm lại quy định lúc nộp). Cần thử theo cặp: hai máy, hai Gmail.
7. Google Cloud › OAuth consent screen: *In production*, logo, tên miền, URL chính sách.

## C. Data safety – trả lời đề xuất (đối chiếu code hiện tại)
- Nhà phát triển **không có máy chủ**: vị trí (đã mã hoá), kế hoạch, kỷ niệm đi thẳng từ máy người dùng tới Google Calendar/Drive
  **của chính người dùng và người họ mời**. Theo định nghĩa của Play, dữ liệu gửi tới dịch vụ do người dùng chỉ định và
  "chia sẻ với người dùng khác theo yêu cầu của người dùng" có thể không tính là thu thập/chia sẻ — **phải đọc lại hướng dẫn
  Data safety hiện hành trước khi khai**. Phương án an toàn: khai *Vị trí chính xác* = thu thập, chia sẻ với người dùng khác do
  người dùng chọn, mục đích chức năng ứng dụng, mã hoá khi truyền, xoá được.
- Ảnh: khai *Ảnh* nếu người duyệt coi việc tải lên Drive của người dùng là thu thập.

## D. Ghi chú cho người duyệt (dán vào khai báo Foreground service / Quyền truy cập ứng dụng)
> Dây tơ hồng cho phép những người thân **đã cùng đồng ý** (mỗi người tự cài app, tự đăng nhập Google và tự chấp nhận lời mời)
> thấy vị trí của nhau để yên tâm về an toàn. Khi người dùng bật "Chia sẻ vị trí của tôi", app chạy foreground service loại
> location với **thông báo cố định** ghi rõ đang chia sẻ với ai, để vị trí tiếp tục cập nhật khi tắt màn hình. Người dùng tắt hoặc
> tạm ẩn bất cứ lúc nào bằng một chạm; người khác thấy trạng thái "đang ẩn". App không ẩn icon, không theo dõi người không dùng app,
> vị trí được mã hoá đầu-cuối. Dữ liệu lưu trong Google Calendar của chính người dùng; không có máy chủ của nhà phát triển. Đăng nhập thử: hai tài khoản Google thử [điền]; A đã mời B, mã mời: [điền].

**Video** (≤ 30 s): bật công tắc → hộp thoại giải thích → hộp thoại hệ thống → thông báo cố định xuất hiện → máy thứ hai thấy vị trí.

## E. Trang thông tin – bản nháp
**Tên**: Dây tơ hồng – Biết người thương đã về
**Mô tả ngắn**: Vị trí, kế hoạch, kỷ niệm chung cho hai người. Không máy chủ, mua một lần.
**Mô tả đầy đủ**:
> "Về tới chưa?" — không cần nhắn nữa.
> • Nối dây với người yêu bằng Gmail: hai bạn thấy vị trí của nhau trên bản đồ.
> • Lộ trình hôm nay: xem đường người thương đã đi, lưu ngay trên máy bạn.
> • Kế hoạch chung: hẹn hò, du lịch… hiện luôn trong Google Calendar của cả hai, có nhắc lịch.
> • Sổ kỷ niệm: ngày đầu gặp nhau, chuyến đi đầu tiên… kèm ảnh.
> • SOS: giữ 2 giây, cả nhà nhận cảnh báo kèm vị trí.
> • Tạm ẩn 1 giờ hoặc tắt hẳn bất cứ lúc nào — luôn có thông báo khi đang chia sẻ.
> • Gói Gia đình 299.000 đ trọn đời: cả nhà tới 10 người, con cái được mời dùng miễn phí.
> • Riêng tư: không máy chủ trung gian — mọi thứ nằm trong Google Calendar/Drive của chính các bạn; vị trí được mã hoá. Không quảng cáo.
> Dây tơ hồng chỉ hoạt động khi mỗi người tự cài app và đồng ý. Không dùng để theo dõi người khác khi họ không biết.

Không viết "bảo mật tuyệt đối", "theo dõi bí mật", "định vị người khác".

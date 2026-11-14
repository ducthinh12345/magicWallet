# Chính sách quyền riêng tư – Ví Ma Thuật

Phiên bản 1.0 · Hiệu lực từ [ngày] · Bên cung cấp: [Tên pháp nhân], [địa chỉ] · Liên hệ: [email hỗ trợ]

> Bản nháp kỹ thuật, mô tả đúng cách ứng dụng đang hoạt động. Cần luật sư rà soát trước khi công bố
> (Luật Bảo vệ dữ liệu cá nhân 2025, Nghị định 13/2023/NĐ-CP).

## 1. Tóm tắt
- Dữ liệu tài chính của bạn **chỉ nằm trên điện thoại của bạn** và, nếu bạn bật, **trong Google Drive / Google Sheets của chính bạn**.
- Chúng tôi **không vận hành máy chủ nhận dữ liệu**, không có SDK quảng cáo, không bán hay chia sẻ dữ liệu.

## 2. Dữ liệu ứng dụng xử lý và mục đích
| Dữ liệu | Nguồn | Mục đích | Lưu ở đâu |
| --- | --- | --- | --- |
| Giao dịch, ví, danh mục, ngân sách, ghi chú | Bạn nhập | Ghi chép, báo cáo | Điện thoại (mã hoá) |
| Nội dung thông báo của app ngân hàng/ví **bạn chọn** | Quyền "Truy cập thông báo" (chỉ khi bạn bật) | Tự ghi giao dịch | Điện thoại, mã hoá, **tự xoá sau 30 ngày** |
| Email đã gắn nhãn "Ví Ma Thuật" | Google Apps Script do **bạn tự cài** trong tài khoản Google của bạn | Tự ghi giao dịch | Google Sheet của bạn → điện thoại |
| File sao kê CSV | Bạn chọn file | Bổ sung giao dịch | Điện thoại |
| Tài khoản Google (quyền `drive.file`, `drive.appdata`) | Bạn đăng nhập | Đồng bộ Sheet, sao lưu | Chỉ các file do ứng dụng tạo trong Drive của bạn |

Ứng dụng **bỏ ngay, không lưu** mọi thông báo/SMS/email chứa mã OTP, mã xác thực, mật khẩu.
Ứng dụng không yêu cầu tên đăng nhập hay mật khẩu ngân hàng, không kết nối hệ thống ngân hàng, không chuyển tiền.

## 3. Bảo mật
- Cơ sở dữ liệu trên máy được mã hoá AES-256; khoá giữ trong Android Keystore / iOS Keychain.
- Bản sao lưu trên Drive được mã hoá đầu-cuối bằng mật khẩu của bạn (Argon2id + AES-256-GCM). Chúng tôi và Google đều không đọc được.
- Khoá ứng dụng bằng vân tay/khuôn mặt/mã PIN; chặn chụp màn hình (có thể tắt).

## 4. Quyền của bạn
- **Rút lại đồng ý** từng nguồn tự động bất cứ lúc nào (Thêm › Ghi tự động).
- **Xem** dữ liệu ứng dụng đã đọc (Thêm › Ghi tự động › Dữ liệu app đã đọc).
- **Xuất** toàn bộ dữ liệu ra CSV/JSON; **xoá** toàn bộ dữ liệu trên máy (Thêm › Xoá toàn bộ dữ liệu).
- **Thu hồi** quyền Google tại myaccount.google.com › Bảo mật › Ứng dụng bên thứ ba.

## 5. Mua gói Pro
Thanh toán do Google Play / Apple App Store xử lý. Chúng tôi không nhận và không lưu thông tin thanh toán hay danh tính người mua.

## 6. Trẻ em
Ứng dụng không dành cho người dưới 16 tuổi.

## 7. Liên hệ và thay đổi
Mọi yêu cầu về dữ liệu cá nhân: [email hỗ trợ], phản hồi trong [số] ngày làm việc. Khi chính sách thay đổi, ứng dụng sẽ thông báo và ghi phiên bản mới.

Ví Ma Thuật không liên kết hay được bảo trợ bởi bất kỳ ngân hàng hoặc ví điện tử nào.

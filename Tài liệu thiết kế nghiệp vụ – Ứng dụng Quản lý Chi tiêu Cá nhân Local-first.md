# Tài liệu thiết kế nghiệp vụ – Ứng dụng Quản lý Chi tiêu Cá nhân Local-first

Nov 11, 2026 · @rd\_team@avividai

## 1. Tổng quan sản phẩm

Sản phẩm là ứng dụng quản lý chi tiêu cá nhân chạy 100% trên thiết bị người dùng, lưu dữ liệu vào Google Drive/Google Sheets của chính họ, và tự động ghi nhận giao dịch từ thông báo ngân hàng, SMS, email hóa đơn và ảnh chụp biên lai. Không có máy chủ trung gian nào của nhà phát triển chạm vào dữ liệu tài chính.

**Tên làm việc:** Ví Ma Thuật (Magic Wallet). **Nền tảng:** Android (ưu tiên, vì đọc được thông báo/SMS), iOS, và PWA cho máy tính.

### 1.1 Mục tiêu kinh doanh

| Mục tiêu | Chỉ số đo | Ngưỡng đạt |
| --- | --- | --- |
| Giảm công sức ghi chép | % giao dịch được ghi tự động | ≥ 70% sau 30 ngày dùng |
| Dễ dùng | Thời gian nhập tay 1 giao dịch | ≤ 5 giây, ≤ 3 lần chạm |
| Người dùng hiểu được tiền đi đâu | Tỷ lệ mở báo cáo tuần | ≥ 50% người dùng hoạt động |
| Tin cậy về bảo mật | Số byte dữ liệu tài chính gửi về server nhà phát triển | 0 |
| Giữ chân | Tỷ lệ còn dùng sau 90 ngày | ≥ 35% |

### 1.2 Phạm vi

**Trong phạm vi (v1.0):** ghi chép thu/chi/chuyển khoản, nhiều ví/tài khoản, danh mục, ngân sách, thu thập tự động, đồng bộ Google Sheets, sao lưu Google Drive, báo cáo tuần/tháng/quý/năm, nhắc nhở, xuất PDF/CSV, khóa sinh trắc học.

**Ngoài phạm vi (v1.0):** kết nối trực tiếp API ngân hàng qua Open Banking (cần server trung gian và giấy phép), đầu tư/chứng khoán, chia sẻ ví nhiều người dùng thời gian thực, thanh toán trong app.

### 1.3 Nguyên tắc thiết kế

1. **Local-first:** app hoạt động đầy đủ khi không có mạng; cloud chỉ là nơi đồng bộ và sao lưu.
2. **Dữ liệu thuộc về người dùng:** Google Sheet là của họ, mở được bằng tay, cột rõ ràng, không định dạng độc quyền.
3. **Tự động trước, nhập tay sau:** mọi nguồn tự động đều đi qua hàng chờ duyệt một chạm, không bao giờ ghi âm thầm.
4. **Một màn hình, một việc:** mỗi màn hình trả lời một câu hỏi ("Tôi còn bao nhiêu?", "Tháng này tiêu vào đâu?").
5. **Quyền tối thiểu:** chỉ xin quyền khi người dùng bật đúng tính năng cần quyền đó.

### 1.4 Mô hình doanh thu: Freemium + Pro

App miễn phí với bộ chức năng cốt lõi; gói Pro mở khóa các tính năng nâng cao, mua một lần (trọn đời) hoặc trả theo năm. Nguyên tắc: không bao giờ khóa sau tường phí các tính năng bảo mật, xuất dữ liệu và sao lưu thủ công, vì dữ liệu thuộc về người dùng.

| Tính năng | Miễn phí | Pro |
| --- | --- | --- |
| Ghi chép thu/chi/chuyển khoản, danh mục, thẻ | Không giới hạn | Không giới hạn |
| Số ví / tài khoản | Tối đa 3 | Không giới hạn |
| Ghi tự động từ thông báo ngân hàng / ví (mục 5.5) | 1 ngân hàng hoặc ví | Toàn bộ 25 tổ chức |
| Quét biên lai OCR | 10 lần/tháng | Không giới hạn |
| Đọc email hóa đơn qua Apps Script | Không | Có |
| Tự xác nhận giao dịch khi tin cậy ≥ 95% | Không | Có |
| Quy tắc phân loại tự đặt | 5 quy tắc | Không giới hạn |
| Ngân sách | 1 ngân sách tổng + 3 danh mục | Không giới hạn, chuyển dư sang kỳ sau |
| Báo cáo | Tuần, Tháng | Tuần, Tháng, Quý, Năm, khoảng tùy chọn, bản đồ nhiệt |
| Nhận xét tự động | Báo cáo tuần | Mọi báo cáo + tổng kết năm |
| Xuất PDF báo cáo, lưu PDF định kỳ lên Drive | Không | Có |
| Xuất CSV / JSON toàn bộ dữ liệu | Có | Có |
| Đồng bộ Google Sheets | Có | Có |
| Sao lưu Drive | Thủ công | Tự động hằng ngày, giữ 30 bản |
| Đa tiền tệ (cần cho PayPal) | Không | Có |
| Mục tiêu tiết kiệm, nợ & cho vay | 1 mục tiêu | Không giới hạn |
| Khóa app, mã hóa, chế độ riêng tư | Có | Có |
| Widget, giao diện màu | Widget cơ bản | Toàn bộ widget và chủ đề màu |
| Ví gia đình (ví, ngân sách, báo cáo chung) | Không | Chỉ Pro: chủ nhóm có Pro tạo nhóm, mời tối đa 5 thành viên |

**Giá đề xuất (cần xác nhận qua khảo sát):** Pro năm 199.000đ; Pro trọn đời mua một lần 499.000đ; dùng thử Pro 14 ngày không cần thẻ.

**Quy tắc cấp phép (không cần server):**

- BR-08: Thanh toán qua Google Play Billing và Apple In-App Purchase; quyền Pro xác minh bằng biên nhận của kho ứng dụng ngay trên máy, nhà phát triển không lưu thông tin người mua.
- BR-09: Quyền Pro gắn với tài khoản Google Play / Apple ID, khôi phục được bằng nút "Khôi phục giao dịch mua" trên máy mới.
- BR-10: Hết hạn Pro năm thì dữ liệu giữ nguyên và vẫn xem được; chỉ các tính năng Pro dừng hoạt động (ví thứ 4 trở đi chuyển sang chỉ đọc, ghi tự động quay về 1 nguồn do người dùng chọn).
- BR-11: Bản PWA máy tính mở khóa Pro bằng mã kích hoạt ký số tạo trong app di động, kiểm tra chữ ký offline.

## 2. Ràng buộc & kiến trúc tổng thể

Điều kiện tiên quyết được đáp ứng bằng kiến trúc local-first: mọi xử lý (thu thập, phân loại, báo cáo) chạy trên thiết bị; Google Sheets và Drive của chính người dùng thay vai trò "cloud". Nhà phát triển không vận hành backend, database hay API nào.

&#91;embedded content: kiến trúc tổng thể · thiết bị và tài khoản Google\]

Giao dịch đi từ nguồn thu thập qua bộ xử lý vào SQLite; bộ đồng bộ đẩy và kéo dữ liệu hai chiều với Google Sheets, sao lưu mã hóa lên Drive; Apps Script trong tài khoản người dùng ghi email hóa đơn vào Sheet để app kéo về.

### 2.1 Quyết định kiến trúc

| Mã | Quyết định | Lý do | Đánh đổi |
| --- | --- | --- | --- |
| AD-01 | SQLite trên máy là nguồn dữ liệu chính, Sheet là bản sao | Chạy offline, nhanh, không phụ thuộc hạn mức API | Cần cơ chế đồng bộ và xử lý xung đột |
| AD-02 | OAuth trực tiếp từ app (PKCE), không qua backend | Token và dữ liệu không đi qua bên thứ ba | Không có push server; đồng bộ theo lịch nền |
| AD-03 | Không dùng Open Banking API | Mọi Open Banking đều cần server trung gian và giấy phép | Phải đọc thông báo / email / sao kê thay thế |
| AD-04 | OCR và phân loại bằng mô hình trên máy | Ảnh hóa đơn không rời thiết bị | Độ chính xác thấp hơn AI cloud một chút |
| AD-05 | Email đọc bằng Apps Script trong tài khoản người dùng | Tránh scope Gmail bị hạn chế; vẫn không có server chung | Người dùng cài script 1 lần theo hướng dẫn trong app |
| AD-06 | Một mã nguồn Flutter cho Android, iOS, PWA | Giảm chi phí phát triển và bảo trì | Phần đọc thông báo phải viết module gốc Android |

## 3. Chân dung người dùng & hành trình

Ba nhóm người dùng chính có chung một nỗi đau: không biết tiền đi đâu vì ghi chép quá mất công. Thiết kế ưu tiên nhóm A, vì đây là nhóm đông nhất và dễ bỏ app nhất.

| Persona | Mô tả | Nhu cầu chính | Nỗi đau | Tính năng then chốt |
| --- | --- | --- | --- | --- |
| A. Nhân viên văn phòng trẻ (22–30 tuổi) | Lương 10–25 triệu/tháng, chi tiêu qua QR, thẻ, ví điện tử | Biết cuối tháng còn bao nhiêu | Lười nhập tay, bỏ app sau 2 tuần | Ghi tự động từ thông báo, widget màn hình chính |
| B. Người quản lý tài chính gia đình (30–45 tuổi) | Nhiều tài khoản, nhiều khoản cố định | Kiểm soát ngân sách theo danh mục | Dữ liệu rải rác nhiều ngân hàng | Đa ví, ngân sách, báo cáo quý/năm, Google Sheet để cùng xem |
| C. Freelancer / chủ shop nhỏ | Thu nhập không đều, lẫn chi cá nhân và công việc | Tách chi cá nhân và công việc | Cuối năm khó tổng hợp | Thẻ (tag), xuất Excel/PDF, báo cáo năm |

### 3.1 Hành trình chính (persona A)

1. **Cài đặt (≤ 2 phút):** mở app → chọn tiền tệ VND → tạo ví đầu tiên kèm số dư → (tùy chọn) đăng nhập Google để đồng bộ.
2. **Bật tự động:** app gợi ý "Ghi chi tiêu tự động từ thông báo ngân hàng?" → giải thích quyền bằng hình minh họa → người dùng cấp quyền.
3. **Hằng ngày:** quét QR thanh toán → ngân hàng gửi thông báo → app tạo giao dịch nháp, đoán danh mục → thông báo "Đã ghi 45.000đ – Ăn uống. Đúng không?" → chạm 1 lần để xác nhận hoặc sửa.
4. **Cuối tuần:** nhận báo cáo tuần (thông báo tối Chủ nhật): tổng chi, so với tuần trước, top 3 danh mục.
5. **Cuối tháng:** xem báo cáo tháng, điều chỉnh ngân sách tháng sau; Google Sheet đã cập nhật sẵn để chia sẻ với vợ/chồng nếu muốn.

### 3.2 Các ca sử dụng chính

| Mã | Ca sử dụng | Tác nhân |
| --- | --- | --- |
| UC-01 | Ghi một giao dịch nhanh | Người dùng |
| UC-02 | Tự động ghi giao dịch từ thông báo / SMS | Hệ thống (trên máy) |
| UC-03 | Quét biên lai bằng camera | Người dùng |
| UC-04 | Duyệt hàng chờ giao dịch tự động | Người dùng |
| UC-05 | Đặt và theo dõi ngân sách | Người dùng |
| UC-06 | Xem báo cáo theo kỳ | Người dùng |
| UC-07 | Đồng bộ Google Sheets / sao lưu Drive | Hệ thống (trên máy) |
| UC-08 | Khôi phục dữ liệu trên máy mới | Người dùng |
| UC-09 | Nhập dữ liệu từ sao kê CSV/Excel | Người dùng |
| UC-10 | Xuất báo cáo PDF/CSV | Người dùng |

## 4. Yêu cầu chức năng chi tiết

Hệ thống gồm 10 module; MoSCoW cho biết thứ tự ưu tiên: M = bắt buộc cho v1.0, S = nên có, C = có thể có. Mỗi user story có tiêu chí chấp nhận (AC) để QA kiểm thử.

| Mã | Module | Chức năng chính | Ưu tiên |
| --- | --- | --- | --- |
| M01 | Giao dịch | Thêm/sửa/xóa thu, chi, chuyển khoản; giao dịch định kỳ; tách hóa đơn; ghi chú, ảnh đính kèm, thẻ | M |
| M02 | Ví & tài khoản | Tiền mặt, ngân hàng, thẻ tín dụng, ví điện tử; số dư tự tính; đối soát số dư | M |
| M03 | Danh mục | 2 cấp (cha/con), icon + màu, bộ mặc định tiếng Việt, gộp/ẩn danh mục | M |
| M04 | Thu thập tự động | Thông báo, SMS, email, OCR biên lai, nhập sao kê, phím tắt/chia sẻ | M |
| M05 | Ngân sách | Theo tháng/tuần, theo danh mục, cảnh báo 80%/100%, chuyển dư sang kỳ sau | M |
| M06 | Báo cáo | Tuần/tháng/quý/năm, so sánh kỳ trước, xu hướng, xuất PDF/CSV | M |
| M07 | Đồng bộ Google | Ghi Google Sheets, sao lưu mã hóa Drive, khôi phục | M |
| M08 | Nhắc nhở & thông báo | Nhắc hóa đơn định kỳ, tổng kết tuần, cảnh báo ngân sách | S |
| M09 | Mục tiêu tiết kiệm | Đặt mục tiêu, tiến độ, gợi ý số tiền mỗi tháng | S |
| M10 | Nợ & cho vay | Theo dõi khoản cho mượn/vay, hạn trả | C |
| M11 | Gia đình (chỉ Pro) | Nhóm gia đình dùng chung một Google Sheet do chủ nhóm tạo và chia sẻ quyền qua Google Drive; mỗi thành viên dùng app trên máy riêng, chọn ví nào chia sẻ vào nhóm; ví cá nhân không chia sẻ thì không rời máy; vai trò Chủ nhóm / Thành viên ghi / Chỉ xem; ngân sách và báo cáo chung của gia đình; mỗi thành viên phải tự đồng ý khi tham gia và rời nhóm bất kỳ lúc nào | S (v1.5, Pro) |

### 4.1 User story trọng yếu

**US-01 – Ghi nhanh một khoản chi.** Là người dùng, tôi muốn ghi một khoản chi trong vài giây để không bỏ cuộc.

- AC1: Nút "+" luôn hiển thị ở màn hình chính và widget; bàn phím số mở sẵn khi vào màn hình nhập.
- AC2: Danh mục được gợi ý từ 5 danh mục dùng nhiều nhất theo khung giờ (ví dụ 11–13h gợi ý "Ăn trưa").
- AC3: Lưu thành công với tối thiểu 2 trường: số tiền + danh mục; ngày mặc định là hôm nay, ví mặc định là ví dùng gần nhất.
- AC4: Hỗ trợ nhập rút gọn: "45k" = 45.000, "1tr2" = 1.200.000.

**US-02 – Tự động ghi từ thông báo ngân hàng.** Là người dùng, tôi muốn app tự đọc thông báo biến động số dư để không phải nhập tay.

- AC1: Chỉ đọc thông báo từ các ứng dụng nằm trong danh sách người dùng chọn (whitelist).
- AC2: Giao dịch tạo ra có trạng thái "Chờ duyệt", không cộng vào báo cáo cho đến khi xác nhận (hoặc tự xác nhận nếu người dùng bật và độ tin cậy ≥ 95%).
- AC3: Không tạo trùng khi cùng một giao dịch đến từ cả SMS và thông báo (xem quy tắc chống trùng ở mục 5).
- AC4: Nội dung thông báo gốc chỉ lưu trên máy, tự xóa sau 30 ngày.

**US-03 – Cảnh báo ngân sách.** Là người dùng, tôi muốn được báo khi sắp vượt ngân sách để kịp điều chỉnh.

- AC1: Thông báo khi đạt 80% và 100% ngân sách danh mục; mỗi ngưỡng báo 1 lần mỗi kỳ.
- AC2: Màn hình ngân sách hiển thị "Còn được chi X đ/ngày" cho số ngày còn lại của kỳ.

**US-04 – Đồng bộ Google Sheets.** Là người dùng, tôi muốn dữ liệu nằm trong Google Sheet của tôi để tự xem, lọc, chia sẻ.

- AC1: Lần đầu kết nối, app tạo file "Ví Riêng – Dữ liệu" trong thư mục riêng của app trên Drive.
- AC2: Giao dịch mới xuất hiện trên Sheet trong ≤ 60 giây khi có mạng; khi offline, xếp hàng và đẩy lên khi có mạng.
- AC3: Sửa trực tiếp trên Sheet (cột được phép sửa) được kéo về app ở lần đồng bộ kế tiếp.

**US-05 – Báo cáo theo kỳ.** Là người dùng, tôi muốn xem báo cáo tuần/tháng/quý/năm để hiểu thói quen chi tiêu.

- AC1: Chuyển kỳ bằng thanh chọn (Tuần | Tháng | Quý | Năm) và vuốt trái/phải để sang kỳ trước/sau.
- AC2: Mỗi báo cáo có: tổng thu, tổng chi, chênh lệch, % thay đổi so với kỳ trước, cơ cấu theo danh mục, xu hướng theo thời gian.
- AC3: Tạo báo cáo cho 10.000 giao dịch trong ≤ 1 giây trên máy tầm trung.

### 4.2 Quy tắc nghiệp vụ

| Mã | Quy tắc |
| --- | --- |
| BR-01 | Chuyển khoản giữa 2 ví của chính người dùng không tính là thu hay chi trong báo cáo. |
| BR-02 | Thanh toán thẻ tín dụng: khoản chi ghi nhận tại thời điểm quẹt thẻ; khoản trả nợ thẻ là chuyển khoản. |
| BR-03 | Tuần bắt đầu Thứ Hai (cấu hình được); quý theo năm dương lịch Q1 = T1–T3. |
| BR-04 | Ngày bắt đầu tháng tài chính cấu hình được (ví dụ ngày nhận lương 5 hằng tháng). |
| BR-05 | Số tiền lưu dạng số nguyên theo đơn vị nhỏ nhất của tiền tệ (VND: đồng) để tránh sai số làm tròn. |
| BR-06 | Giao dịch đa tiền tệ quy đổi theo tỷ giá người dùng nhập hoặc tỷ giá tải về khi có mạng, lưu cả số gốc và số quy đổi. |
| BR-07 | Xóa giao dịch là xóa mềm (soft delete) 30 ngày để đồng bộ và cho phép hoàn tác. |

## 5. Thu thập chi tiêu tự động (không cần nhập tay)

Không dùng server, app vẫn tự ghi được phần lớn giao dịch bằng cách đọc dữ liệu ngay trên máy: thông báo biến động số dư là nguồn chính trên Android, email hóa đơn và Google Apps Script là nguồn chính trên iOS. Mọi nguồn đều đổ vào một hàng chờ duyệt chung.

### 5.1 Các nguồn thu thập

| Nguồn | Nền tảng | Cơ chế kỹ thuật (chạy trên máy/tài khoản của người dùng) | Độ phủ dự kiến | Lưu ý |
| --- | --- | --- | --- | --- |
| S1. Thông báo ứng dụng ngân hàng / ví điện tử | Android | NotificationListenerService đọc thông báo từ app trong whitelist, parser trích số tiền, số dư, nội dung | Cao (60–80%) | Người dùng phải bật "Truy cập thông báo"; cần tuân thủ chính sách Google Play và khai báo rõ mục đích |
| S2. SMS biến động số dư | Android | Đọc qua thông báo SMS (S1) thay vì quyền READ\_SMS | Trung bình | Google Play chỉ cấp READ\_SMS cho app SMS mặc định, nên v1.0 không xin quyền này |
| S3. Email hóa đơn / biến động (ngân hàng, Shopee, Grab…) | Mọi nền tảng | Phương án A: Google Apps Script cài vào tài khoản Google của chính người dùng, chạy định kỳ, đọc nhãn Gmail đã lọc và ghi vào tab "Inbox" của Sheet; app kéo về. Phương án B: app gọi Gmail API trực tiếp | Trung bình | Phương án B dùng scope bị hạn chế, cần thẩm định bảo mật của Google; v1.0 chọn A |
| S4. Quét biên lai / hóa đơn bằng camera | Mọi nền tảng | OCR trên máy (Google ML Kit / Apple Vision), trích tổng tiền, ngày, tên cửa hàng | Theo nhu cầu | Không gửi ảnh lên cloud OCR |
| S5. Nhập sao kê ngân hàng | Mọi nền tảng | Nhập file CSV/XLSX/PDF tải từ internet banking; mẫu ánh xạ cột lưu lại cho lần sau | Bổ sung theo tháng | Dùng để đối soát và lấp chỗ thiếu |
| S6. iOS Shortcuts / chia sẻ | iOS | App Intents: "Ghi chi tiêu" từ Siri, Shortcuts; tự động hóa Shortcuts khi giao dịch Apple Pay/Wallet; chia sẻ ảnh chụp màn hình giao dịch vào app để OCR | Trung bình | iOS không cho app đọc thông báo/SMS của app khác |
| S7. Giao dịch định kỳ | Mọi nền tảng | Lịch nội bộ tự sinh giao dịch (tiền nhà, điện, Netflix) | Ổn định | Tạo ở trạng thái chờ duyệt vào ngày đến hạn |

### 5.2 Luồng xử lý chung

1. **Thu nhận:** nguồn S1–S7 tạo bản ghi thô (raw event) gồm nguồn, thời điểm, nội dung gốc.
2. **Phân tích (parse):** bộ mẫu cho từng ngân hàng (regex + quy tắc) trích: số tiền, dấu +/−, số dư sau giao dịch, 4 số cuối tài khoản, nội dung chuyển khoản, tên đơn vị nhận.
3. **Gán ví:** khớp 4 số cuối tài khoản / tên app nguồn với ví đã khai báo.
4. **Phân loại:** (a) quy tắc người dùng tự đặt, (b) từ điển nhà bán phổ biến tại Việt Nam đóng gói sẵn trong app, (c) mô hình học cục bộ từ các lần người dùng sửa danh mục.
5. **Chống trùng:** cùng số tiền, cùng ví, lệch thời gian ≤ 5 phút giữa hai nguồn → gộp thành một, giữ nguồn có nhiều thông tin hơn.
6. **Hàng chờ duyệt:** giao dịch hiện ở thẻ "Chờ duyệt" kèm điểm tin cậy; người dùng xác nhận 1 chạm, vuốt để bỏ qua, hoặc bật "Tự xác nhận khi tin cậy ≥ 95%".
7. **Học lại:** mỗi lần sửa danh mục, app hỏi "Áp dụng cho các giao dịch tương tự?" và lưu thành quy tắc.

### 5.3 Cập nhật bộ mẫu ngân hàng mà không cần server

Mẫu nhận dạng thông báo được đóng gói trong app và cập nhật theo phiên bản app trên kho ứng dụng. Tùy chọn nâng cao: người dùng bật "Tải gói mẫu mới" để app tải một file JSON tĩnh, đã ký số, từ kho công khai (ví dụ GitHub Releases); file chỉ chứa mẫu, app không gửi dữ liệu gì đi. Người dùng cũng tự tạo mẫu mới bằng cách bôi đen số tiền trong một thông báo mẫu.

### 5.4 Ngoại lệ

- Không nhận dạng được: lưu vào "Chưa xác định" kèm nội dung gốc để người dùng tự điền hoặc tạo mẫu.
- Số dư sau giao dịch lệch với số dư app tính: hiển thị cảnh báo đối soát và đề xuất giao dịch điều chỉnh.
- Giao dịch hoàn tiền: nhận diện từ khóa "hoàn tiền", "refund" và ghi là thu nhập thuộc danh mục gốc, trừ vào chi tiêu trong báo cáo.

### 5.5 Danh sách ngân hàng & ví điện tử hỗ trợ đầu tiên

Bản v1.0 hỗ trợ 25 tổ chức: 17 ngân hàng và 8 ví điện tử. Mỗi tổ chức cần một bộ mẫu nhận dạng riêng, thu từ thông báo thật của người thử nghiệm ở giai đoạn Khám phá (NFR-14: ≤ 1 ngày công/mẫu, tổng khoảng 25 ngày công).

| STT | Nhóm | Tổ chức | Tên hiển thị trong app | Ghi chú nghiệp vụ |
| --- | --- | --- | --- | --- |
| 1 | Big 4 (vốn Nhà nước) | Ngân hàng TMCP Ngoại thương Việt Nam | Vietcombank |  |
| 2 | Big 4 (vốn Nhà nước) | Ngân hàng TMCP Đầu tư và Phát triển Việt Nam | BIDV |  |
| 3 | Big 4 (vốn Nhà nước) | Ngân hàng TMCP Công Thương Việt Nam | VietinBank |  |
| 4 | Big 4 (vốn Nhà nước) | Ngân hàng Nông nghiệp và Phát triển Nông thôn Việt Nam | Agribank | Kiểm tra cả kênh SMS biến động số dư, phổ biến với nhóm khách hàng này |
| 5 | TMCP tư nhân | Ngân hàng TMCP Quân đội | MB Bank |  |
| 6 | TMCP tư nhân | Ngân hàng TMCP Kỹ thương Việt Nam | Techcombank |  |
| 7 | TMCP tư nhân | Ngân hàng TMCP Việt Nam Thịnh Vượng | VPBank | Cake là ngân hàng số của VPBank: mẫu và ví khai báo riêng |
| 8 | TMCP tư nhân | Ngân hàng TMCP Á Châu | ACB |  |
| 9 | TMCP tư nhân | Ngân hàng TMCP Tiên Phong | TPBank |  |
| 10 | TMCP tư nhân | Ngân hàng TMCP Sài Gòn Thương Tín | Sacombank |  |
| 11 | TMCP tư nhân | Ngân hàng TMCP Quốc tế Việt Nam | VIB |  |
| 12 | TMCP tư nhân | Ngân hàng TMCP Phát triển TP.HCM | HDBank |  |
| 13 | TMCP tư nhân | Ngân hàng TMCP Hàng Hải Việt Nam | MSB | TNEX được MSB bảo trợ: mẫu và ví khai báo riêng |
| 14 | TMCP tư nhân | Ngân hàng TMCP Lộc Phát Việt Nam | LPBank |  |
| 15 | Ngân hàng số | Timo (hợp tác với BVBank) | Timo |  |
| 16 | Ngân hàng số | Cake by VPBank | Cake |  |
| 17 | Ngân hàng số | TNEX (bảo trợ bởi MSB) | TNEX |  |
| 18 | Ví đa năng | MoMo | MoMo |  |
| 19 | Ví đa năng | ZaloPay | ZaloPay |  |
| 20 | Ví đa năng | VNPAY | VNPAY | Phân biệt thanh toán QR qua app ngân hàng (đã có thông báo ngân hàng) với giao dịch từ ví VNPAY để chống trùng |
| 21 | Ví đa năng | ShopeePay | ShopeePay | Kết hợp email đơn hàng Shopee để lấy tên sản phẩm |
| 22 | Ví đa năng | Viettel Money | Viettel Money |  |
| 23 | Ví & cổng thanh toán khác | Payoo | Payoo |  |
| 24 | Ví & cổng thanh toán khác | VNPT Money | VNPT Money |  |
| 25 | Ví & cổng thanh toán khác | PayPal | PayPal | Giao dịch bằng ngoại tệ: cần đa tiền tệ (BR-06) |

**Quy tắc riêng cho ví điện tử:**

- Nạp tiền vào ví từ ngân hàng, hoặc rút từ ví về ngân hàng, là chuyển khoản giữa hai ví của người dùng (BR-01), không tính là chi tiêu.
- Một giao dịch nạp ví thường sinh 2 thông báo (ngân hàng báo trừ tiền, ví báo cộng tiền): bộ chống trùng ghép cặp chúng thành 1 chuyển khoản, cùng số tiền, lệch ≤ 5 phút.
- Thanh toán bằng ví liên kết trực tiếp tài khoản ngân hàng (không qua số dư ví): ghi nhận chi ở ví ngân hàng, thông báo của ví chỉ dùng để bổ sung tên đơn vị bán.
- Bộ mẫu theo dõi tỷ lệ nhận dạng của từng tổ chức; dưới 95% trong 7 ngày thì app gợi ý người dùng gửi mẫu hoặc tự tạo mẫu.

## 6. Tích hợp Google Drive & Google Sheets

App kết nối thẳng từ thiết bị tới Google API bằng OAuth 2.0 + PKCE, chỉ xin quyền `drive.file` và `drive.appdata`, nên chỉ thấy đúng các file do app tạo, không đọc được phần còn lại trong Drive của người dùng. Nhà phát triển chỉ cần đăng ký OAuth client trên Google Cloud; không có máy chủ nào nhận token hay dữ liệu.

### 6.1 Phân vai lưu trữ

| Nơi lưu | Vai trò | Định dạng | Ai đọc được |
| --- | --- | --- | --- |
| SQLite mã hóa trên máy (SQLCipher) | Nguồn dữ liệu chính, chạy offline | Bảng quan hệ | Chỉ app trên máy |
| Google Sheets "Ví Riêng – Dữ liệu" | Bản sao dễ đọc, để xem, lọc, chia sẻ, chỉnh sửa có kiểm soát | Bảng tính | Người dùng và người họ chia sẻ |
| Drive appDataFolder | Bản sao lưu đầy đủ, mã hóa đầu-cuối | File .vrbackup (SQLite mã hóa AES-256-GCM) | Chỉ app, với mật khẩu sao lưu của người dùng |
| Drive thư mục "Ví Riêng/Báo cáo" | Lưu báo cáo PDF xuất định kỳ | PDF | Người dùng |

### 6.2 Cấu trúc Google Sheet

| Tab | Nội dung | Người dùng sửa được? |
| --- | --- | --- |
| Giao dịch | Mỗi dòng 1 giao dịch: ID, Ngày, Loại, Số tiền, Ví, Danh mục, Danh mục con, Ghi chú, Thẻ, Nguồn, Cập nhật lúc | Có: Ngày, Số tiền, Danh mục, Ghi chú, Thẻ |
| Ví | Danh sách ví và số dư | Không (app tính) |
| Danh mục | Cây danh mục, màu, icon | Có |
| Ngân sách | Ngân sách theo kỳ và danh mục | Có |
| Tổng hợp tháng | Bảng tổng hợp chi theo danh mục × tháng, dùng công thức SUMIFS, kèm biểu đồ | Không (công thức) |
| Hộp thư | Giao dịch thô do Apps Script đọc từ email đổ vào | Không |
| \_meta | Phiên bản schema, thời điểm đồng bộ cuối | Không (ẩn, khóa) |

### 6.3 Cơ chế đồng bộ

1. Mỗi thay đổi trong app ghi vào bảng nhật ký thay đổi (change log) cục bộ.
2. Khi có mạng (và theo lịch nền 15 phút/lần, hoặc chỉ khi dùng Wi-Fi nếu người dùng chọn), app đẩy thay đổi bằng `spreadsheets.values.batchUpdate`, gom tối đa 500 dòng mỗi lần để tiết kiệm hạn mức API.
3. App kéo về các dòng có "Cập nhật lúc" mới hơn lần đồng bộ cuối.
4. Xung đột: so sánh thời điểm cập nhật từng dòng, bản mới hơn thắng; nếu cùng sửa trong 60 giây, hỏi người dùng chọn.
5. Dòng bị xóa trên Sheet không bị xóa ngay trong app; app đánh dấu và hỏi xác nhận để tránh mất dữ liệu do xóa nhầm.
6. Lỗi hạn mức (HTTP 429) hoặc mất mạng: thử lại theo exponential backoff, dữ liệu vẫn an toàn trong hàng đợi.

### 6.4 Sao lưu & khôi phục

- Sao lưu tự động hằng ngày lên appDataFolder, giữ 30 bản gần nhất; sao lưu thủ công bất kỳ lúc nào.
- File sao lưu được mã hóa bằng khóa dẫn xuất từ mật khẩu sao lưu (Argon2id); mất mật khẩu thì không ai khôi phục được, kể cả nhà phát triển. App cấp mã khôi phục 24 ký tự khi bật sao lưu.
- Khôi phục trên máy mới: đăng nhập Google → chọn bản sao lưu → nhập mật khẩu → app dựng lại SQLite; nếu không có bản sao lưu, có thể dựng lại từ Google Sheet.
- Chế độ không dùng Google: người dùng vẫn dùng đủ tính năng, sao lưu ra file cục bộ hoặc chia sẻ qua bất kỳ dịch vụ nào.

## 7. Báo cáo tuần / tháng / quý / năm

Mọi báo cáo được tính ngay trên máy từ SQLite, trả lời 3 câu hỏi theo thứ tự: tiêu bao nhiêu, tiêu vào đâu, và so với trước thì tốt hơn hay tệ hơn. Kỳ càng dài thì báo cáo càng thiên về xu hướng thay vì chi tiết.

### 7.1 Nội dung theo từng kỳ

| Thành phần | Tuần | Tháng | Quý | Năm |
| --- | --- | --- | --- | --- |
| Tổng thu, tổng chi, chênh lệch | Có | Có | Có | Có |
| % thay đổi so với kỳ trước | So tuần trước | So tháng trước và cùng kỳ năm trước | So quý trước | So năm trước |
| Cơ cấu chi theo danh mục | Top 5 (thanh ngang) | Biểu đồ vòng + danh sách đầy đủ | Thanh ngang | Thanh ngang |
| Xu hướng theo thời gian | Cột theo ngày | Cột theo ngày + đường lũy kế so với ngân sách | Cột theo tháng | Cột theo tháng, 12 tháng |
| Ngân sách: đã dùng / còn lại | Theo tuần | Theo danh mục | Tổng hợp 3 tháng | Tổng hợp 12 tháng |
| Giao dịch lớn nhất | Top 3 | Top 5 | Top 10 | Top 10 |
| Tỷ lệ tiết kiệm (thu − chi) / thu | — | Có | Có | Có |
| Nhận xét tự động | 1–2 câu | 3 câu | 3 câu | Bản tổng kết năm |
| Bản đồ nhiệt chi tiêu theo ngày trong tuần × giờ | — | Có | — | Có |
| Chi cố định vs chi biến đổi | — | Có | Có | Có |

### 7.2 Nhận xét tự động (chạy trên máy, không dùng AI cloud)

Câu nhận xét được sinh từ mẫu câu + ngưỡng thống kê, ví dụ:

- "Ăn uống tuần này 1,2 triệu, cao hơn 35% so với trung bình 4 tuần."
- "Bạn đã dùng 82% ngân sách Mua sắm khi tháng mới qua 60%."
- "Năm 2026 bạn tiết kiệm được 18% thu nhập, tăng 4 điểm so với 2025."

Quy tắc: chỉ nêu điểm bất thường khi lệch ≥ 20% và giá trị tuyệt đối ≥ 200.000đ, tối đa 3 câu mỗi báo cáo để tránh nhiễu.

### 7.3 Phân phối báo cáo

- Thông báo trên máy: báo cáo tuần tối Chủ nhật 20:00, báo cáo tháng sáng ngày 1, quý và năm vào ngày đầu kỳ mới (giờ và kênh cấu hình được).
- Xuất PDF và CSV, lưu vào máy hoặc thư mục "Ví Riêng/Báo cáo" trên Drive.
- Tab "Tổng hợp tháng" trên Google Sheet cập nhật theo dữ liệu đồng bộ, dùng được cho bảng điều khiển Looker Studio nếu người dùng muốn.

### 7.4 Bộ lọc & tùy chọn

Lọc theo ví, danh mục, thẻ, khoảng số tiền; khoảng thời gian tùy chọn; ẩn/hiện chuyển khoản nội bộ; chọn ngày bắt đầu tháng tài chính (BR-04).

## 8. Mô hình dữ liệu

Cơ sở dữ liệu SQLite cục bộ gồm 9 bảng; mọi bảng có `id` dạng UUID v7 (sắp xếp được theo thời gian, sinh trên máy không cần server), `created_at`, `updated_at`, `deleted_at` để hỗ trợ đồng bộ và xóa mềm.

| Bảng | Trường chính | Quan hệ |
| --- | --- | --- |
| wallet (Ví) | name, type (cash / bank / credit / ewallet), currency, opening\_balance, account\_last4, source\_app\_package, icon, color, archived | 1 – n transaction |
| category (Danh mục) | name, type (expense / income), parent\_id, icon, color, is\_fixed\_cost, sort\_order | tự tham chiếu (cha/con); 1 – n transaction |
| transaction (Giao dịch) | wallet\_id, to\_wallet\_id, type (expense / income / transfer), amount (số nguyên), currency, fx\_rate, amount\_base, category\_id, occurred\_at, note, merchant, status (pending / confirmed / ignored), source (manual / notification / email / ocr / import / recurring), raw\_event\_id, confidence | n – 1 wallet, n – 1 category, n – n tag |
| tag (Thẻ) | name, color | n – n transaction qua transaction\_tag |
| budget (Ngân sách) | category\_id (null = tổng), period (week / month / quarter / year), amount, rollover, start\_date | n – 1 category |
| recurring\_rule (Định kỳ) | template giao dịch, rrule (chuẩn iCalendar), next\_run\_at, auto\_confirm | sinh transaction |
| raw\_event (Sự kiện thô) | source, source\_app, received\_at, content\_encrypted, parse\_status, expires\_at (30 ngày) | 1 – 1 transaction |
| classification\_rule (Quy tắc phân loại) | match\_field, match\_type (contains / regex / exact), pattern, category\_id, wallet\_id, priority | áp dụng khi phân loại |
| sync\_log (Nhật ký đồng bộ) | entity, entity\_id, op (insert / update / delete), changed\_at, synced\_at, remote\_row | phục vụ đồng bộ Sheets |

Chỉ mục cần có: `transaction(occurred_at)`, `transaction(category_id, occurred_at)`, `transaction(wallet_id, occurred_at)`, `transaction(status)` để báo cáo năm chạy dưới 1 giây.

Cài đặt người dùng (tiền tệ, ngày đầu tuần, ngày đầu tháng tài chính, giờ gửi báo cáo, mức tự xác nhận) lưu trong bảng key–value `setting`, cũng được đồng bộ vào bản sao lưu.

## 9. Thiết kế UX/UI & màn hình

Giao diện dùng 4 tab dưới cùng cộng một nút "+" nổi ở giữa; người dùng mới đến được mọi việc thường ngày trong tối đa 2 lần chạm từ màn hình chính.

### 9.1 Điều hướng

| Tab | Câu hỏi nó trả lời | Thành phần chính |
| --- | --- | --- |
| Tổng quan | "Tôi còn bao nhiêu, tháng này ổn không?" | Tổng số dư các ví; thanh tiến độ chi tháng so với ngân sách; thẻ "Chờ duyệt (n)"; 5 giao dịch gần nhất; nhận xét nhanh |
| Giao dịch | "Tôi đã tiêu những gì?" | Danh sách nhóm theo ngày, tổng mỗi ngày; tìm kiếm; bộ lọc; vuốt trái để xóa, vuốt phải để nhân bản |
| (+) Thêm | "Ghi nhanh" | Bàn phím số lớn, lưới danh mục gợi ý, chọn ví, ngày, ghi chú, chụp biên lai |
| Báo cáo | "Tiền đi đâu?" | Thanh chọn Tuần / Tháng / Quý / Năm, biểu đồ, so sánh kỳ trước |
| Thêm (Cài đặt) | "Thiết lập" | Ví, danh mục, ngân sách, nguồn tự động, Google, bảo mật, xuất dữ liệu |

### 9.2 Danh sách màn hình

| Mã | Màn hình | Ghi chú thiết kế |
| --- | --- | --- |
| SC-01 | Chào mừng & thiết lập nhanh (3 bước) | Có nút "Bỏ qua", mọi bước làm lại được trong Cài đặt |
| SC-02 | Tổng quan | Số lớn, ít chữ; màu xanh/vàng/đỏ theo mức dùng ngân sách |
| SC-03 | Thêm/sửa giao dịch | Mở bàn phím ngay; lưu bằng nút lớn ở góc dưới bên phải |
| SC-04 | Hàng chờ duyệt | Dạng thẻ; vuốt phải = xác nhận, vuốt trái = bỏ qua, chạm = sửa; nút "Xác nhận tất cả" |
| SC-05 | Danh sách giao dịch | Cuộn vô hạn, tổng theo ngày dính đầu nhóm |
| SC-06 | Báo cáo | Vuốt ngang đổi kỳ; chạm vào lát biểu đồ để xem giao dịch trong danh mục đó |
| SC-07 | Ngân sách | Thanh tiến độ mỗi danh mục, "còn X đ/ngày" |
| SC-08 | Ví & đối soát | Nhập số dư thực tế → app đề xuất giao dịch điều chỉnh |
| SC-09 | Nguồn tự động | Bật/tắt từng nguồn, chọn app ngân hàng, xem mẫu, kiểm tra thử với thông báo mẫu |
| SC-10 | Kết nối Google | Trạng thái đồng bộ, lần đồng bộ cuối, mở Sheet, sao lưu/khôi phục |
| SC-11 | Bảo mật | Khóa app (PIN / vân tay / Face ID), ẩn số tiền, thời gian tự khóa |
| SC-12 | Widget màn hình chính | 2 cỡ: "Chi hôm nay + nút +" và "Ngân sách tháng" |

### 9.3 Hệ thống thiết kế

- **Màu ý nghĩa:** chi = đỏ cam, thu = xanh lá, chuyển khoản = xám xanh; không dùng màu làm tín hiệu duy nhất, luôn có dấu +/− và icon.
- **Chữ số:** font có chữ số đều độ rộng (tabular figures), dấu chấm phân cách hàng nghìn theo chuẩn Việt Nam: 1.250.000 đ.
- **Chế độ sáng/tối** theo hệ thống; cỡ chữ theo cài đặt trợ năng của máy.
- **Chế độ riêng tư:** chạm 2 lần vào số dư để ẩn thành "•••" khi dùng nơi công cộng.
- **Ngôn ngữ:** Tiếng Việt mặc định, Tiếng Anh; văn phong ngắn, thân thiện, không thuật ngữ kế toán.
- **Trạng thái rỗng:** mỗi màn hình trống có một câu hướng dẫn và một nút hành động, ví dụ "Chưa có giao dịch. Bật ghi tự động?".

## 10. Bảo mật & quyền riêng tư

Dữ liệu tài chính chỉ tồn tại ở hai nơi: trên thiết bị (mã hóa) và trong tài khoản Google của chính người dùng. Nhà phát triển không vận hành máy chủ nhận dữ liệu, không có SDK quảng cáo, và chỉ thu thập báo lỗi khi người dùng đồng ý (đã lọc bỏ mọi số tiền, nội dung).

### 10.1 Biện pháp kiểm soát

| Rủi ro | Biện pháp |
| --- | --- |
| Mất/trộm điện thoại | SQLite mã hóa SQLCipher AES-256; khóa lưu trong Android Keystore / iOS Keychain (Secure Enclave); khóa app bằng PIN/sinh trắc học, tự khóa sau 1 phút ở nền |
| Lộ token Google | Token lưu trong Keystore/Keychain; OAuth PKCE, không có client secret trong app; người dùng thu hồi được bất kỳ lúc nào trong tài khoản Google |
| Lộ bản sao lưu trên Drive | Mã hóa đầu-cuối bằng khóa từ mật khẩu sao lưu (Argon2id + AES-256-GCM); Google cũng không đọc được |
| Đọc trộm thông báo ngoài phạm vi | Chỉ xử lý thông báo từ app trong whitelist; nội dung thô mã hóa và tự xóa sau 30 ngày; có màn hình "Dữ liệu app đã đọc" để người dùng tự kiểm tra |
| Chụp màn hình / xem trộm trong trình chuyển app | Bật FLAG\_SECURE (Android) và che nội dung khi vào nền (iOS) — có thể tắt |
| Mã độc can thiệp app | Phát hiện root/jailbreak và cảnh báo (không chặn); ký số gói mẫu ngân hàng (mục 5.3); kiểm tra chữ ký trước khi nạp |
| Ghi log lộ dữ liệu | Log không bao giờ chứa số tiền, nội dung, số tài khoản; build release tắt log chi tiết |
| Mạng bị nghe lén | Chỉ HTTPS tới googleapis.com; certificate pinning cho domain Google |

### 10.2 Tuân thủ

Sản phẩm được thiết kế để không phải xin giấy phép hoạt động tài chính: app không giữ tiền, không thực hiện thanh toán, không kết nối hệ thống ngân hàng, không thu dữ liệu về nhà phát triển. Các nghĩa vụ còn lại tập trung vào dữ liệu cá nhân, bảo vệ người tiêu dùng, sở hữu trí tuệ và chính sách kho ứng dụng.

#### 10.2.1 Văn bản pháp luật và yêu cầu thiết kế tương ứng

| Văn bản | Điểm áp dụng cho sản phẩm | Yêu cầu thiết kế bắt buộc |
| --- | --- | --- |
| Luật Bảo vệ dữ liệu cá nhân 2025 (hiệu lực 01/01/2026) và Nghị định 13/2023/NĐ-CP | Thông tin tài khoản, giao dịch tài chính là dữ liệu cá nhân nhạy cảm; dù xử lý trên máy, nhà phát triển vẫn là bên cung cấp công cụ xử lý | Xin đồng ý riêng, rõ ràng cho từng nguồn tự động (thông báo, email, camera); thông báo mục đích bằng tiếng Việt trước khi cấp quyền; rút lại đồng ý bất kỳ lúc nào; xóa toàn bộ dữ liệu trong 2 chạm; không thu dữ liệu vượt mục đích |
| Luật Bảo vệ quyền lợi người tiêu dùng 2023 | Bán gói Pro, gia hạn tự động, dùng thử | Hiển thị giá đã gồm thuế, chu kỳ gia hạn, cách hủy ngay trên màn hình mua; nhắc trước khi hết dùng thử 3 ngày; điều khoản sử dụng bằng tiếng Việt; không dùng thiết kế đánh lừa (dark pattern) để giữ người dùng |
| Luật Giao dịch điện tử 2023 | Điều khoản, đồng ý, biên nhận mua hàng dưới dạng điện tử | Lưu bằng chứng đồng ý (phiên bản điều khoản, thời điểm) trên máy và trong bản sao lưu |
| Luật An ninh mạng 2018 và Nghị định 53/2022/NĐ-CP | Nghĩa vụ lưu trữ dữ liệu tại Việt Nam áp dụng cho doanh nghiệp thu thập dữ liệu người dùng | Kiến trúc không thu dữ liệu giúp giảm nghĩa vụ; pháp chế xác nhận phạm vi áp dụng, nhất là với báo lỗi ẩn danh |
| Nghị định 52/2024/NĐ-CP về thanh toán không dùng tiền mặt | Hoạt động trung gian thanh toán, ví điện tử phải có giấy phép của Ngân hàng Nhà nước | App chỉ ghi chép, không chuyển tiền, không giữ số dư, không khởi tạo lệnh thanh toán; không thêm tính năng "chuyển tiền" hay "thanh toán hộ" khi chưa có đánh giá pháp lý |
| Luật Sở hữu trí tuệ | Tên, logo của 17 ngân hàng và 8 ví là nhãn hiệu của họ | Chỉ dùng tên dạng chữ để mô tả tương thích; không dùng logo, màu nhận diện nếu chưa được cho phép; ghi rõ "không liên kết hay được bảo trợ bởi ngân hàng" |
| Luật Quảng cáo | Truyền thông, mô tả trên kho ứng dụng | Không quảng cáo "bảo mật tuyệt đối", "được ngân hàng chứng nhận"; mọi tuyên bố phải đúng với thiết kế |
| Quy định về thuế, hóa đơn | Doanh thu bán gói Pro qua Google Play / App Store | Kế toán xác định nghĩa vụ thuế của pháp nhân phát hành và phần thuế do kho ứng dụng khấu trừ |

#### 10.2.2 Chính sách nền tảng

- **Google Play:** khai báo quyền Truy cập thông báo kèm video minh họa; Data Safety form; khai báo tính năng tài chính (Financial Features declaration); chính sách thanh toán bắt buộc dùng Play Billing.
- **Apple App Store:** Privacy Nutrition Label; gói đăng ký tuân thủ hướng dẫn In-App Purchase; khai báo mã hóa (Export Compliance) vì app dùng AES.
- **Google API Services User Data Policy (Limited Use):** chỉ dùng `drive.file`, `drive.appdata`; xác minh màn hình đồng ý OAuth; không chuyển dữ liệu Google cho bên thứ ba.

#### 10.2.3 Những điều app không bao giờ làm

- Không đọc, lưu hay hiển thị lại mã OTP: parser loại bỏ ngay thông báo/SMS chứa OTP, mã xác thực, mật khẩu, kể cả từ ngân hàng trong whitelist.
- Không yêu cầu tên đăng nhập, mật khẩu internet banking; không giả lập đăng nhập hay thu thập dữ liệu từ app/website ngân hàng.
- Không can thiệp, dịch ngược ứng dụng ngân hàng, ví điện tử.
- Không gửi dữ liệu tài chính tới máy chủ của nhà phát triển hoặc bên thứ ba; không SDK quảng cáo.
- Không bán, cho thuê hay chia sẻ dữ liệu người dùng.

#### 10.2.4 Ví gia đình (M11) và dữ liệu của người khác

- Mỗi thành viên tự đồng ý khi tham gia, thấy rõ ví nào của mình được chia sẻ, và rời nhóm hay thu hồi chia sẻ được bất kỳ lúc nào.
- Chủ nhóm không xem được ví cá nhân chưa chia sẻ của thành viên.
- Thành viên dưới 16 tuổi chỉ tham gia khi có sự đồng ý của cha mẹ/người giám hộ; app không được nhắm tới trẻ em.

#### 10.2.5 Hồ sơ pháp lý cần có trước khi phát hành

- [ ] Chính sách quyền riêng tư và Điều khoản sử dụng bằng tiếng Việt và tiếng Anh, có phiên bản và ngày hiệu lực.
- [ ] Hồ sơ đánh giá tác động xử lý dữ liệu cá nhân, nếu pháp chế xác định là bắt buộc.
- [ ] Rà soát pháp lý về việc đọc thông báo ngân hàng và tên nhãn hiệu trong danh sách mục 5.5.
- [ ] Đăng ký pháp nhân phát hành, tài khoản nhà phát triển Google Play / Apple đứng tên pháp nhân.
- [ ] Quy trình tiếp nhận yêu cầu của người dùng và cơ quan chức năng (email hỗ trợ, thời hạn phản hồi).

*Lưu ý: bảng trên là phân tích nghiệp vụ dựa trên hiểu biết đến giữa năm 2026, không phải ý kiến pháp lý. Văn bản pháp luật có thể đã được sửa đổi hoặc có nghị định hướng dẫn mới; luật sư cần xác nhận trước khi phát hành.*

## 11. Yêu cầu phi chức năng

Các ngưỡng dưới đây đo trên máy tầm trung (Android 4 GB RAM, iPhone 3 đời trước) với 10.000 giao dịch, và là tiêu chí nghiệm thu bắt buộc.

| Mã | Nhóm | Yêu cầu | Ngưỡng |
| --- | --- | --- | --- |
| NFR-01 | Hiệu năng | Mở app (khởi động nguội) | ≤ 1,5 giây |
| NFR-02 | Hiệu năng | Lưu một giao dịch | ≤ 100 ms |
| NFR-03 | Hiệu năng | Tạo báo cáo năm | ≤ 1 giây |
| NFR-04 | Hiệu năng | Từ lúc nhận thông báo ngân hàng đến khi có giao dịch nháp | ≤ 3 giây |
| NFR-05 | Tài nguyên | Pin tiêu thụ nền mỗi ngày | ≤ 1% |
| NFR-06 | Tài nguyên | Dung lượng cài đặt | ≤ 40 MB (gồm mô hình OCR) |
| NFR-07 | Khả dụng | Hoạt động offline | 100% tính năng trừ đồng bộ |
| NFR-08 | Tin cậy | Mất dữ liệu khi app bị tắt đột ngột | 0 giao dịch (SQLite WAL, ghi theo transaction) |
| NFR-09 | Tin cậy | Tỷ lệ phiên không crash | ≥ 99,8% |
| NFR-10 | Độ chính xác | Trích đúng số tiền từ thông báo ngân hàng được hỗ trợ | ≥ 99% |
| NFR-11 | Độ chính xác | Đoán đúng danh mục sau 30 ngày dùng | ≥ 85% |
| NFR-12 | Khả dụng | Người mới ghi được giao dịch đầu tiên không cần hướng dẫn | ≥ 90% người thử nghiệm |
| NFR-13 | Trợ năng | Chuẩn WCAG 2.1 AA: tương phản, TalkBack/VoiceOver, vùng chạm ≥ 44×44 pt | Đạt |
| NFR-14 | Bảo trì | Thêm mẫu một ngân hàng mới | ≤ 1 ngày công, không sửa code lõi |
| NFR-15 | Tương thích | Hệ điều hành hỗ trợ | Android 8.0+, iOS 16+, trình duyệt Chrome/Edge/Safari bản mới (PWA) |

### 11.1 Công nghệ đề xuất

Flutter (một mã nguồn cho Android, iOS, web) + Drift/SQLCipher cho cơ sở dữ liệu; module gốc Kotlin cho NotificationListenerService; Google ML Kit / Apple Vision cho OCR; googleapis cho Drive/Sheets; mô hình phân loại nhẹ (Naive Bayes hoặc TF-Lite < 2 MB) chạy trên máy. Bản PWA dùng IndexedDB mã hóa (Web Crypto) và không có nguồn S1/S2.

## 12. Lộ trình, rủi ro & KPI

Sản phẩm đi qua 4 giai đoạn trong khoảng 34 tuần với đội 5–6 người (1 BA/PO, 1 UX, 2 mobile dev, 1 QA, 0,5 bảo mật); mỗi cổng là điểm quyết định đi tiếp hay điều chỉnh.

&#91;embedded content: lộ trình · 4 giai đoạn, 3 cổng kiểm soát\]

MVP ra trước trên Android vì đây là nền tảng duy nhất đọc được thông báo ngân hàng, tính năng tạo khác biệt của sản phẩm.

### 12.1 Rủi ro chính

| Rủi ro | Khả năng | Tác động | Biện pháp giảm thiểu |
| --- | --- | --- | --- |
| Google Play hạn chế quyền đọc thông báo | Trung bình | Cao | Khai báo rõ mục đích, video minh họa khi nộp; phát hành thêm bản APK trên trang chính thức |
| Ngân hàng đổi định dạng thông báo | Cao | Trung bình | Gói mẫu cập nhật được (mục 5.3), người dùng tự tạo mẫu, cảnh báo khi tỷ lệ nhận dạng giảm |
| Hạn mức Google Sheets API (60 lần ghi/phút/người dùng) | Thấp | Trung bình | Gom lô 500 dòng, backoff, đồng bộ nền |
| Người dùng quên mật khẩu sao lưu | Trung bình | Cao | Mã khôi phục 24 ký tự; dựng lại từ Google Sheet |
| iOS không đọc được thông báo, tỷ lệ tự động thấp | Chắc chắn | Trung bình | Apps Script email, OCR ảnh chụp màn hình, Shortcuts; truyền thông rõ khác biệt giữa hai nền tảng |
| Người dùng sửa sai cấu trúc Sheet | Trung bình | Trung bình | Khóa cột hệ thống, tab \_meta, kiểm tra schema trước khi kéo về |

### 12.2 KPI theo dõi sau ra mắt

Vì không có server, KPI được đo bằng số liệu tổng hợp của kho ứng dụng, khảo sát trong app và phân tích ẩn danh chỉ khi người dùng bật (chỉ đếm sự kiện, không số tiền): tỷ lệ giao dịch tự động ≥ 70%, giữ chân 90 ngày ≥ 35%, điểm đánh giá ≥ 4,5 sao, tỷ lệ phiên không crash ≥ 99,8%.

### 12.3 Câu hỏi còn mở

- [x] Chốt danh sách 10 ngân hàng / ví điện tử hỗ trợ đầu tiên.

  Đã chốt: 17 ngân hàng và 8 ví điện tử, xem mục 5.5.
- [x] Mô hình doanh thu: mua một lần, gói Pro, hay miễn phí mã nguồn mở.

  Đã chốt: Freemium + gói Pro (mua một lần hoặc theo năm), xem mục 1.4.
- [x] Có hỗ trợ ví chung cho gia đình qua Sheet chia sẻ từ v1.5 hay không.

  Đã chốt: có, từ v1.5, chỉ dành cho gói Pro (module M11, mục 1.4).
- [x] Pháp chế xác nhận nghĩa vụ theo Nghị định 13/2023/NĐ-CP.

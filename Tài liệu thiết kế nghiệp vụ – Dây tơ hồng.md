# Tài liệu thiết kế nghiệp vụ – Dây tơ hồng

Ứng dụng cho hai người (rồi cả gia đình) chia sẻ **vị trí, kế hoạch trên lịch và kỷ niệm**, có sự đồng ý của mỗi người.
Phiên bản 2.0 · 2026-11-14. Thay bản 1.0 (Firebase): chủ sản phẩm yêu cầu **không phát sinh bất kỳ chi phí vận hành nào**.

## 1. Tổng quan sản phẩm

**Giá trị cốt lõi.** Một "sợi tơ" giữa các tài khoản Google: thấy nhau đang ở đâu và lộ trình hôm nay, có chung một cuốn lịch
kế hoạch, và một cuốn sổ kỷ niệm. Không máy chủ trung gian: dữ liệu nằm trong Google Calendar/Drive **của chính người dùng**.
Mua một lần, dùng mãi.

### 1.1 Mục tiêu kinh doanh
| Mục tiêu | Chỉ số | Mốc |
| --- | --- | --- |
| Lan truyền theo cặp | ≥ 60 % người cài mời được người thứ hai trong 48 giờ | 3 tháng |
| Gắn bó | ≥ 3 kế hoạch hoặc kỷ niệm / sợi tơ / tháng | 3 tháng |
| Chuyển đổi Pro | ≥ 4 % sợi tơ hoạt động mua Gói Gia đình | 6 tháng |
| Chi phí vận hành | **0 đ** — không tài khoản thanh toán trên Google Cloud | luôn luôn |

### 1.2 Phạm vi v1
Android (CH Play) · đăng nhập Google · sợi tơ đôi (miễn phí) · Gói Gia đình (Pro 299.000 đ trọn đời) · vị trí cập nhật 1–3 phút ·
lộ trình hôm nay · tạm ẩn · SOS · **kế hoạch chung** · **kỷ niệm chung (kèm ảnh)** · rời/mời ra · xoá dữ liệu.
**Ngoài phạm vi:** iOS, bản đồ trong app, vị trí thời gian thực từng giây, chat, vùng an toàn, nhắc kỷ niệm hằng năm.

### 1.3 Nguyên tắc thiết kế
1. **Đồng ý & minh bạch.** Mỗi người tự cài, tự đăng nhập, tự nhập mã mời, tự bật chia sẻ. Đang chia sẻ luôn có thông báo cố định.
2. **Đối xứng.** Ai thấy ai thì người đó cũng thấy mình đang được xem. Không chế độ xem lén.
3. **Không máy chủ, không chi phí.** Dùng hạ tầng Google mà người dùng vốn có (Calendar, Drive). Nhà phát triển không giữ dữ liệu nào.
4. **Chỉ Gmail được mời.** Google kiểm quyền (ACL lịch); app kiểm mã mời (khoá giải mã vị trí).
5. **Vị trí là dữ liệu nhạy cảm nhất → mã hoá.** Kế hoạch/kỷ niệm dạng thường để hiện được trong Google Calendar (chủ sản phẩm đã chọn).

### 1.4 Mô hình doanh thu
| | Miễn phí – *Sợi tơ đôi* | Pro – *Gói Gia đình* (299.000 đ trọn đời) |
| --- | --- | --- |
| Tạo sợi tơ | 1 sợi tơ, **2 người** | tối đa **5 sợi tơ**, mỗi sợi **10 người** |
| Tham gia sợi tơ người khác tạo | Không giới hạn | Không giới hạn |
| Vị trí, lộ trình, SOS, tạm ẩn, kế hoạch, kỷ niệm | Có | Có |

- **BR-P1:** Chỉ người **tạo** sợi tơ gia đình cần Pro; người được mời dùng miễn phí.
- **BR-P2:** Google Play Billing, sản phẩm không tiêu hao `family_lifetime`; khôi phục trên máy mới cùng tài khoản Play.
- **BR-P3:** Mất Pro → sợi tơ gia đình vẫn chạy, không thêm được người.
- **BR-P4:** SOS, tạm ẩn, rời sợi tơ, xoá dữ liệu không bao giờ bị khoá sau tường phí.

## 2. Kiến trúc

### 2.1 Quyết định kiến trúc
| # | Quyết định | Lý do | Phương án bị loại |
| --- | --- | --- | --- |
| AD-1 | Mỗi sợi tơ = **một lịch phụ Google Calendar** của người tạo, chia sẻ quyền `writer` cho Gmail được mời | Calendar API miễn phí ("All standard use… at no additional cost"), Google tự kiểm quyền | Firebase (vượt hạn mức miễn phí ~20–25 người → phải trả tiền); Drive (`drive.file` không đọc được file người khác chia sẻ, `drive` đầy đủ phải qua CASA tốn phí) |
| AD-2 | Vị trí: **một sự kiện 📍 / người**, ngày 01/01/2000, mô tả = AES-256-GCM | Không làm rối lịch; Google không đọc được toạ độ | Ghi mỗi điểm thành một sự kiện (tốn hạn mức, rác lịch) |
| AD-3 | Khoá sợi tơ nằm trong **mã mời** `DTH1.<id lịch>.<khoá>` gửi qua kênh chat người dùng chọn | Không cần máy chủ trao khoá. Lộ mã vẫn cần đúng Gmail mới đọc được lịch | Trao khoá X25519 qua máy chủ (bản 1.0) |
| AD-4 | **Hỏi định kỳ** (3 phút nền, 1 phút khi mở app) thay cho đẩy | Calendar chỉ đẩy về webhook HTTPS (cần server) | Push qua FCM/Cloud Functions (tốn phí) |
| AD-5 | Lộ trình: người gửi kèm **≤ 60 điểm trong 2 giờ gần nhất**; người nhận lưu SQLite 30 ngày | Hỏi 3 phút/lần không mất điểm khi người xem tắt app < 2 giờ | Lưu lộ trình trên Google |
| AD-6 | Foreground service loại `location`, **không** xin vị trí nền | Minh bạch, tránh tờ khai vị trí nền của Play | — |
| AD-7 | Không Google Maps SDK: mở app Google Maps bằng link, lộ trình vẽ sơ đồ trên máy | Maps SDK **bắt buộc bật thanh toán** | Maps SDK; OpenStreetMap (chính sách tile cấm dùng nặng trong app) |
| AD-8 | Ảnh kỷ niệm: Drive của người đăng (`drive.file`), chia sẻ riêng từng thành viên, đính kèm vào sự kiện | Miễn phí (15 GB của người dùng), scope không hạn chế | Lưu ảnh trong app (không chia sẻ được) |

```
Máy Linh ──Calendar API──► Lịch phụ "Dây tơ hồng 💞" (Google Calendar của Linh, ACL: minh@gmail.com = writer) ◄── Máy Minh
                           ├─ 📍 Linh  (01/01/2000, mô tả = AES-GCM{tên, toạ độ, lộ trình 2 giờ, tạm ẩn})
                           ├─ 📍 Minh
                           ├─ 🆘 SOS — Minh cần giúp đỡ   (30 phút, link bản đồ dạng rõ + bản mã)
                           ├─ "Đi xem phim" 19:00 thứ Bảy (kế hoạch — hiện trong Google Calendar, có nhắc)
                           └─ 💗 Ngày đầu gặp nhau (cả ngày, ghi chú, ảnh trong Drive của người đăng)
Mã mời DTH1.… (id lịch + khoá) ──Zalo/Messenger──► Minh dán vào app → calendarList.insert (Google kiểm ACL)
```

### 2.2 Quyền Google (đều không thuộc nhóm "hạn chế" → xác minh OAuth miễn phí, không CASA)
`calendar.app.created` (tạo/xoá lịch của mình) · `calendar.acls` (chia sẻ) · `calendar.calendarlist` (thêm lịch được mời) ·
`calendar.events` (ghi sự kiện trên lịch người khác chia sẻ) · `drive.file` (ảnh app tự tải lên).

### 2.3 Hạn mức (miễn phí)
1.000.000 lượt gọi/ngày/dự án, 600 lượt/phút/người. Một người chia sẻ cả ngày ≈ 480 lượt gửi + 480 lượt đọc / sợi tơ ⇒
dự án chịu được **~1.000 người hoạt động/ngày** (ước tính, chưa đo). Vượt hạn mức: app chậm/lỗi tạm thời, **không phát sinh tiền**
vì dự án không gắn tài khoản thanh toán. Khi gần chạm trần: giãn nhịp lên 5 phút (đã thoả thuận 2–5 phút).

## 3. Hành trình chính (Linh mời Minh)
1. Linh cài app → Đăng nhập Google → cấp quyền Lịch + Drive (hộp thoại Google).
2. *Nối dây tơ hồng* › *Tạo sợi tơ & mời bằng Gmail* → nhập Gmail Minh → app tạo lịch, chia sẻ cho Minh, mở share sheet kèm mã mời.
3. Minh cài app, đăng nhập **đúng Gmail đó** → *Tôi có mã mời* → dán cả tin nhắn → vào sợi tơ.
4. Cả hai bật *Chia sẻ vị trí* → thấy nhau trong 1–3 phút. Kế hoạch Linh thêm hiện luôn trong Google Calendar của Minh.

## 4. Yêu cầu chức năng

| Mã | User story | Tiêu chí chấp nhận chính |
| --- | --- | --- |
| US-01 | Đăng nhập Google | Chỉ Google; email lưu trên máy; không có tài khoản phía nhà phát triển |
| US-02 | Tạo sợi tơ & mời bằng Gmail | Email chuẩn hoá; từ chối email của mình; sợi tơ đủ người → báo lỗi; app không tự gửi tin — người dùng chọn kênh |
| US-03 | Nhập mã mời | Tìm mã trong cả đoạn tin nhắn; Gmail không được mời → "Gmail này chưa được mời hoặc đã bị gỡ"; mã sai → báo rõ |
| US-04 | Chia sẻ liên tục | Thông báo cố định ghi tên người đang xem; điểm ≥ 25 m & ≥ 20 s, sai số ≤ 100 m; gửi mỗi 3 phút nếu có điểm mới, nhịp tim 15 phút lấy vị trí mới |
| US-05 | Xem vị trí | "Cập nhật x phút trước"; > 30 phút ghi "có thể đã tắt máy"; chạm → mở Google Maps |
| US-06 | Lộ trình hôm nay | Từ SQLite trên máy; sơ đồ + km + giờ; nút mở Google Maps chỉ đường qua ≤ 8 điểm |
| US-07 | Tạm ẩn 1 giờ / đến khi bật lại | Không gửi toạ độ lẫn lộ trình; người khác thấy "đang ẩn"; hết giờ tự bật lại và báo |
| US-08 | SOS (giữ 2 giây) | Gửi tới mọi sợi tơ kể cả khi tạm ẩn; người nhận được báo đúng một lần trong ≤ 3 phút; nhắc gọi 113/115 |
| US-09 | Kế hoạch chung | Thêm (tên, giờ, nơi, ghi chú) → hiện trong Google Calendar của mọi thành viên, có nhắc mặc định; sự kiện tạo thẳng trong Google Calendar cũng hiện trong app; nhấn giữ để xoá |
| US-10 | Kỷ niệm chung | Tên, ngày, ghi chú, ảnh tuỳ chọn; xếp mới → cũ; ảnh chỉ thành viên xem được |
| US-11 | Rời / mời ra / xoá sợi tơ | Chủ xoá = xoá cả lịch; mời ra = gỡ ACL (Google chặn ngay) |
| US-12 | Gói Gia đình | Mua 299.000 đ một lần; khôi phục |
| US-13 | Xoá dữ liệu | Rời/xoá mọi sợi tơ, xoá SQLite + Keystore, thu hồi quyền Google; báo số sợi tơ chưa xoá được |

### 4.1 Quy tắc nghiệp vụ
| Mã | Quy tắc |
| --- | --- |
| BR-01 | Sợi tơ đôi ≤ 2 người, gia đình ≤ 10 (đếm cả người đã mời chưa nhập mã) |
| BR-02 | Đọc/ghi lịch do Google quyết định theo ACL; app không có quyền gì hơn người dùng |
| BR-03 | Chỉ người tạo mời/mời ra/xoá sợi tơ |
| BR-04 | Mỗi người chỉ ghi sự kiện 📍 của mình (gắn `who` = email) |
| BR-05 | Lộ trình trên máy giữ 30 ngày |
| BR-06 | Toạ độ, tên trong 📍 luôn mã hoá; kế hoạch/kỷ niệm dạng thường; SOS kèm link bản đồ dạng rõ |

## 5. Mô hình dữ liệu
| Nơi | Dữ liệu | Định dạng |
| --- | --- | --- |
| Google Calendar (lịch phụ của chủ) | Sự kiện 📍, 🆘, kế hoạch, 💗 | `extendedProperties.shared.dth` ∈ {loc, sos, plan, memory}, `who` = email |
| Google Drive (của người đăng) | Ảnh kỷ niệm | quyền reader cho từng thành viên |
| Keystore trên máy | Danh sách sợi tơ {id lịch, khoá, chủ?, gia đình?}, email, tạm ẩn, Pro | `flutter_secure_storage` |
| SQLite trên máy | `points(circle, uid, t, lat, lng, acc)`, `seen(id)` (chống báo SOS trùng) | WAL, dùng chung 2 isolate |

## 6. Màn hình
SC-01 Đăng nhập · SC-02 Giải thích quyền vị trí (trước hộp thoại hệ thống) · SC-03 Trang chủ (công tắc chia sẻ, tạm ẩn, sợi tơ, SOS) ·
SC-04 Sợi tơ: tab *Vị trí · Kế hoạch · Kỷ niệm* · SC-05 Lộ trình · SC-06 Mời / nhập mã · SC-07 Pro · SC-08 Cài đặt.

## 7. Bảo mật, quyền riêng tư & chính sách
- AES-256-GCM, nonce ngẫu nhiên mỗi lần; khoá 256 bit sinh trên máy chủ sợi tơ, chỉ đi qua mã mời.
- **Rủi ro đã chấp nhận:** ai có mã mời *và* đăng nhập được Gmail được mời thì đọc được — đúng chủ đích. Người bị mời ra mất quyền đọc lịch
  ngay nhưng vẫn giữ khoá cũ (không còn gì để giải mã vì không đọc được lịch).
- Google Play: chính sách theo dõi người khác (stalkerware) → thông báo cố định, không ẩn icon, người được xem phải tự cài & nhập mã;
  Foreground service loại location cần khai báo + video; Data safety: **nhà phát triển không thu thập dữ liệu** (đi thẳng tới Google
  của người dùng) — cần đọc lại định nghĩa hiện hành để khai đúng; không tạo tài khoản riêng.
- Google OAuth: dưới 100 người dùng thử không cần xác minh; phát hành rộng cần **xác minh scope nhạy cảm (miễn phí, 3–5 ngày)**:
  trang chủ + chính sách trên tên miền đã xác minh, video demo.
- Pháp luật VN: Nghị định 13/2023/NĐ-CP, Luật Bảo vệ dữ liệu cá nhân 2025 — vị trí là dữ liệu nhạy cảm → đồng ý rõ ràng, rút lại được. Cần luật sư rà.

## 8. Phi chức năng
| Mã | Yêu cầu |
| --- | --- |
| NFR-01 | Độ trễ vị trí ≤ 3 phút (nền), ≤ 1 phút khi người xem mở app — **đã thoả thuận** |
| NFR-02 | Pin: chia sẻ cả ngày ≤ 5 %/ngày khi đứng yên phần lớn thời gian (chưa đo) |
| NFR-03 | Chi phí vận hành = 0 đ; ≤ 1.000 lượt gọi API/người/ngày |
| NFR-04 | Android 8.0+ (minSdk 26) |
| NFR-05 | Không SDK quảng cáo/phân tích |

## 9. Rủi ro & lộ trình
| Mã | Rủi ro | Giảm thiểu |
| --- | --- | --- |
| R1 | Play từ chối vì chính sách theo dõi | Nguyên tắc 1.3, mô tả rõ, video |
| R2 | Hãng điện thoại giết service nền | Hướng dẫn tắt tối ưu pin; trạng thái "cập nhật x phút trước" trung thực |
| R3 | Chạm hạn mức 1 triệu lượt/ngày khi app lớn | Giãn nhịp 5 phút; nhiều dự án OAuth theo vùng (cân nhắc khi > 1.000 người hoạt động) |
| R4 | Google đổi chính sách giá Calendar API (đã báo "later in 2026" cho phần *vượt* hạn mức) | Không gắn thanh toán → chỉ bị chặn, không mất tiền; theo dõi thông báo Google |
| R5 | Người dùng xoá nhầm sự kiện 📍 trong Google Calendar | App tự tạo lại ở lần gửi sau |
| R6 | Lộ mã mời qua app chat | Vẫn cần đúng Gmail được mời |

**v1.1:** nhắc kỷ niệm hằng năm, ảnh thu nhỏ trong app, giãn nhịp tự động theo hạn mức · **v1.2:** iOS.

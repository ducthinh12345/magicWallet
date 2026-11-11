/**
 * Ví Ma Thuật — đọc email hoá đơn/biến động số dư vào tab "Hộp thư" (phương án A, mục 5.1 S3).
 * Chạy trong tài khoản Google của chính bạn; không gửi dữ liệu đi đâu ngoài file Sheet này.
 *
 * Cài: mở file "Ví Riêng – Dữ liệu" → Tiện ích mở rộng → Apps Script → dán mã → chọn hàm setup → Chạy.
 */
var LABEL = 'Ví Ma Thuật';
var DONE_LABEL = 'Ví Ma Thuật/đã đọc';
var TAB = 'Hộp thư';
// Giống app: bỏ email chứa OTP/mã xác thực/mật khẩu (mục 10.2.3).
var SENSITIVE = /\bOTP\b|m[ãa] x[áa]c (th[ựu]c|nh[ậa]n)|m[ậa]t kh[ẩa]u|passcode|verification code/i;

function setup() {
  GmailApp.getUserLabelByName(LABEL) || GmailApp.createLabel(LABEL);
  GmailApp.getUserLabelByName(DONE_LABEL) || GmailApp.createLabel(DONE_LABEL);
  ScriptApp.getProjectTriggers().forEach(function (t) {
    if (t.getHandlerFunction() === 'pullEmails') ScriptApp.deleteTrigger(t);
  });
  ScriptApp.newTrigger('pullEmails').timeBased().everyMinutes(15).create();
  pullEmails();
}

function pullEmails() {
  var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(TAB);
  if (!sheet) throw new Error('Không thấy tab "' + TAB + '". Hãy kết nối Google trong app trước.');
  var label = GmailApp.getUserLabelByName(LABEL);
  var done = GmailApp.getUserLabelByName(DONE_LABEL);
  var threads = GmailApp.search('label:"' + LABEL + '" -label:"' + DONE_LABEL + '"', 0, 50);
  var tz = Session.getScriptTimeZone();
  threads.forEach(function (thread) {
    thread.getMessages().forEach(function (m) {
      var body = m.getPlainBody().replace(/\s+/g, ' ').trim().slice(0, 2000);
      if (SENSITIVE.test(body) || SENSITIVE.test(m.getSubject())) return;
      sheet.appendRow([
        Utilities.formatDate(m.getDate(), tz, 'yyyy-MM-dd HH:mm'),
        // Dấu ' giữ nguyên là chữ, tránh nội dung email bị Sheets hiểu thành công thức.
        "'" + m.getFrom(),
        "'" + m.getSubject(),
        "'" + body,
        '',
      ]);
    });
    thread.addLabel(done);
    thread.removeLabel(label);
  });
}

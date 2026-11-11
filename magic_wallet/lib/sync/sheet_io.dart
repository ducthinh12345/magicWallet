import 'dart:async';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:http/http.dart' as http;

/// Thao tác tối thiểu với một spreadsheet. Tách ra để test thuật toán đồng bộ bằng bản giả trong bộ nhớ.
abstract class SheetIO {
  /// Đọc toàn bộ giá trị của một tab (dòng 1 là tiêu đề).
  Future<List<List<Object?>>> read(String tab);

  /// Ghi đè từng dòng: khoá là số dòng (1-based).
  Future<void> writeRows(String tab, Map<int, List<Object?>> rows);

  Future<void> append(String tab, List<List<Object?>> rows);

  /// Xoá hẳn các dòng (1-based) khỏi tab.
  Future<void> deleteRows(String tab, List<int> rowNumbers);

  /// Xoá trắng rồi ghi lại cả tab (dùng cho tab do app tính: Ví, Danh mục, Ngân sách, Tổng hợp).
  Future<void> replaceAll(String tab, List<List<Object?>> rows);
}

/// Hạn mức Sheets ~60 lần ghi/phút/người dùng: gom tối đa 500 dòng mỗi lần gọi (6.3 bước 2).
const batchRows = 500;

/// Thử lại khi 429/5xx/mất mạng theo exponential backoff (6.3 bước 6).
Future<T> withBackoff<T>(Future<T> Function() call, {int tries = 4}) async {
  var delay = const Duration(seconds: 1);
  for (var i = 1; ; i++) {
    try {
      return await call();
    } on sheets.DetailedApiRequestError catch (e) {
      final retry = e.status == 429 || (e.status ?? 0) >= 500;
      if (!retry || i >= tries) rethrow;
    } on http.ClientException {
      // package:http gói lỗi mạng (SocketException) vào ClientException — và chạy được cả trên web.
      if (i >= tries) rethrow;
    } on TimeoutException {
      if (i >= tries) rethrow;
    }
    await Future<void>.delayed(delay);
    delay *= 2;
  }
}

class GoogleSheetIO implements SheetIO {
  final sheets.SheetsApi api;
  final String spreadsheetId;
  final Map<String, int> sheetIds; // tên tab → sheetId số, cần cho deleteDimension
  GoogleSheetIO(this.api, this.spreadsheetId, this.sheetIds);

  String _q(String tab) => "'${tab.replaceAll("'", "''")}'";

  @override
  Future<List<List<Object?>>> read(String tab) async {
    final r = await withBackoff(
      () => api.spreadsheets.values.get(
        spreadsheetId,
        _q(tab),
        valueRenderOption: 'UNFORMATTED_VALUE',
        dateTimeRenderOption: 'FORMATTED_STRING',
      ),
    );
    return [for (final row in r.values ?? const []) List<Object?>.from(row)];
  }

  @override
  Future<void> writeRows(String tab, Map<int, List<Object?>> rows) async {
    final entries = rows.entries.toList();
    for (var i = 0; i < entries.length; i += batchRows) {
      final chunk = entries.skip(i).take(batchRows);
      await withBackoff(
        () => api.spreadsheets.values.batchUpdate(
          sheets.BatchUpdateValuesRequest(
            valueInputOption: 'USER_ENTERED',
            data: [
              for (final e in chunk) sheets.ValueRange(range: '${_q(tab)}!A${e.key}', values: [e.value]),
            ],
          ),
          spreadsheetId,
        ),
      );
    }
  }

  @override
  Future<void> append(String tab, List<List<Object?>> rows) async {
    for (var i = 0; i < rows.length; i += batchRows) {
      final chunk = rows.skip(i).take(batchRows).toList();
      await withBackoff(
        () => api.spreadsheets.values.append(
          sheets.ValueRange(values: chunk),
          spreadsheetId,
          '${_q(tab)}!A1',
          valueInputOption: 'USER_ENTERED',
          insertDataOption: 'INSERT_ROWS',
        ),
      );
    }
  }

  @override
  Future<void> deleteRows(String tab, List<int> rowNumbers) async {
    if (rowNumbers.isEmpty) return;
    // Xoá từ dưới lên để số dòng phía trên không bị dịch.
    final sorted = [...rowNumbers]..sort((a, b) => b.compareTo(a));
    await withBackoff(
      () => api.spreadsheets.batchUpdate(
        sheets.BatchUpdateSpreadsheetRequest(
          requests: [
            for (final r in sorted)
              sheets.Request(
                deleteDimension: sheets.DeleteDimensionRequest(
                  range: sheets.DimensionRange(sheetId: sheetIds[tab], dimension: 'ROWS', startIndex: r - 1, endIndex: r),
                ),
              ),
          ],
        ),
        spreadsheetId,
      ),
    );
  }

  @override
  Future<void> replaceAll(String tab, List<List<Object?>> rows) async {
    await withBackoff(() => api.spreadsheets.values.clear(sheets.ClearValuesRequest(), spreadsheetId, _q(tab)));
    if (rows.isEmpty) return;
    await withBackoff(
      () => api.spreadsheets.values.update(
        sheets.ValueRange(values: rows),
        spreadsheetId,
        '${_q(tab)}!A1',
        valueInputOption: 'USER_ENTERED',
      ),
    );
  }
}

// ---------------- Tạo file lần đầu (US-04 AC1) ----------------

const tabTxn = 'Giao dịch';
const tabWallet = 'Ví';
const tabCategory = 'Danh mục';
const tabBudget = 'Ngân sách';
const tabSummary = 'Tổng hợp tháng';
const tabInbox = 'Hộp thư';
const tabMeta = '_meta';
const schemaVersion = 1;

const txnHeader = [
  'ID',
  'Ngày',
  'Loại',
  'Số tiền',
  'Ví',
  'Danh mục',
  'Danh mục con',
  'Ghi chú',
  'Thẻ',
  'Nguồn',
  'Cập nhật lúc',
  '_sig',
];
const inboxHeader = ['Thời gian', 'Người gửi', 'Tiêu đề', 'Nội dung', 'Đã xử lý'];

/// Tạo "Ví Riêng – Dữ liệu" trong thư mục "Ví Riêng" của app. Trả về (spreadsheetId, tên tab → sheetId).
// locale en_US: để công thức SUMIFS dùng dấu phẩy, không phụ thuộc dấu phân cách theo locale (chưa thử với vi_VN).
Future<(String, Map<String, int>)> createSpreadsheet(sheets.SheetsApi api, drive.DriveApi driveApi) async {
  sheets.Sheet tab(String title, int id, {bool hidden = false}) => sheets.Sheet(
    properties: sheets.SheetProperties(title: title, sheetId: id, hidden: hidden),
  );
  final created = await withBackoff(
    () => api.spreadsheets.create(
      sheets.Spreadsheet(
        properties: sheets.SpreadsheetProperties(title: 'Ví Riêng – Dữ liệu', locale: 'en_US', timeZone: 'Asia/Ho_Chi_Minh'),
        sheets: [
          tab(tabTxn, 0),
          tab(tabWallet, 1),
          tab(tabCategory, 2),
          tab(tabBudget, 3),
          tab(tabSummary, 4),
          tab(tabInbox, 5),
          tab(tabMeta, 6, hidden: true),
        ],
      ),
    ),
  );
  final id = created.spreadsheetId!;
  final ids = {for (final s in created.sheets!) s.properties!.title!: s.properties!.sheetId!};

  await withBackoff(
    () => api.spreadsheets.batchUpdate(
      sheets.BatchUpdateSpreadsheetRequest(
        requests: [
          // Định dạng cột Ngày để đọc/ghi ổn định và lọc được theo ngày trên Sheet.
          sheets.Request(
            repeatCell: sheets.RepeatCellRequest(
              range: sheets.GridRange(sheetId: ids[tabTxn], startColumnIndex: 1, endColumnIndex: 2, startRowIndex: 1),
              cell: sheets.CellData(
                userEnteredFormat: sheets.CellFormat(
                  numberFormat: sheets.NumberFormat(type: 'DATE_TIME', pattern: 'yyyy-mm-dd hh:mm'),
                ),
              ),
              fields: 'userEnteredFormat.numberFormat',
            ),
          ),
          // Ẩn cột _sig — app dùng để phát hiện dòng bị sửa tay.
          sheets.Request(
            updateDimensionProperties: sheets.UpdateDimensionPropertiesRequest(
              range: sheets.DimensionRange(sheetId: ids[tabTxn], dimension: 'COLUMNS', startIndex: 11, endIndex: 12),
              properties: sheets.DimensionProperties(hiddenByUser: true),
              fields: 'hiddenByUser',
            ),
          ),
          // Khoá cột hệ thống (ID, Loại, Ví, Nguồn, Cập nhật lúc) và tab _meta: chỉ cảnh báo khi sửa (12.1).
          for (final col in [0, 2, 4, 9, 10, 11])
            sheets.Request(
              addProtectedRange: sheets.AddProtectedRangeRequest(
                protectedRange: sheets.ProtectedRange(
                  range: sheets.GridRange(sheetId: ids[tabTxn], startColumnIndex: col, endColumnIndex: col + 1),
                  warningOnly: true,
                  description: 'Cột do app quản lý',
                ),
              ),
            ),
          sheets.Request(
            addProtectedRange: sheets.AddProtectedRangeRequest(
              protectedRange: sheets.ProtectedRange(range: sheets.GridRange(sheetId: ids[tabMeta]), warningOnly: true),
            ),
          ),
        ],
      ),
      id,
    ),
  );

  final io = GoogleSheetIO(api, id, ids);
  await io.replaceAll(tabTxn, [txnHeader]);
  await io.replaceAll(tabInbox, [inboxHeader]);

  // Đưa file vào thư mục "Ví Riêng" (drive.file chỉ thấy thư mục do app tạo).
  final folder = await withBackoff(
    () => driveApi.files.create(
      drive.File(name: 'Ví Riêng', mimeType: 'application/vnd.google-apps.folder'),
      $fields: 'id',
    ),
  );
  await withBackoff(() => driveApi.files.update(drive.File(), id, addParents: folder.id, removeParents: 'root'));
  return (id, ids);
}

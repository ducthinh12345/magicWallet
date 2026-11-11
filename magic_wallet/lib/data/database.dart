import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:sqlite3/common.dart' show CommonDatabase;
import 'package:uuid/uuid.dart';

part 'database.g.dart';

/// UUID v7: sinh trên máy, sắp xếp được theo thời gian (mục 8).
String newId() => const Uuid().v7();

/// Cột chung cho mọi bảng đồng bộ được.
mixin Syncable on Table {
  TextColumn get id => text().clientDefault(newId)();
  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();
  DateTimeColumn get updatedAt => dateTime().clientDefault(DateTime.now)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Wallet')
class Wallets extends Table with Syncable {
  TextColumn get name => text()();
  TextColumn get type => text()(); // cash / bank / credit / ewallet
  TextColumn get currency => text().withDefault(const Constant('VND'))();
  IntColumn get openingBalance => integer().withDefault(const Constant(0))();
  TextColumn get accountLast4 => text().nullable()();
  TextColumn get sourceAppPackage => text().nullable()();
  TextColumn get icon => text().withDefault(const Constant('👛'))();
  IntColumn get color => integer().withDefault(const Constant(0xFF607D8B))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
}

@DataClassName('Category')
class Categories extends Table with Syncable {
  TextColumn get name => text()();
  TextColumn get type => text()(); // expense / income
  TextColumn get parentId => text().nullable()();
  TextColumn get icon => text().withDefault(const Constant('🏷️'))();
  IntColumn get color => integer().withDefault(const Constant(0xFF9E9E9E))();
  BoolColumn get isFixedCost => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get hidden => boolean().withDefault(const Constant(false))();
}

@DataClassName('Txn')
@TableIndex(name: 'idx_txn_occurred', columns: {#occurredAt})
@TableIndex(name: 'idx_txn_cat', columns: {#categoryId, #occurredAt})
@TableIndex(name: 'idx_txn_wallet', columns: {#walletId, #occurredAt})
@TableIndex(name: 'idx_txn_status', columns: {#status})
class Transactions extends Table with Syncable {
  TextColumn get walletId => text()();
  TextColumn get toWalletId => text().nullable()();
  TextColumn get type => text()(); // expense / income / transfer
  IntColumn get amount => integer()(); // luôn dương, dấu do `type` quyết định
  TextColumn get currency => text().withDefault(const Constant('VND'))();
  RealColumn get fxRate => real().withDefault(const Constant(1))();
  IntColumn get amountBase => integer()();
  TextColumn get categoryId => text().nullable()();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get merchant => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('confirmed'))(); // pending / confirmed / ignored
  TextColumn get source => text().withDefault(const Constant('manual'))();
  TextColumn get rawEventId => text().nullable()();
  RealColumn get confidence => real().nullable()();
}

@DataClassName('Tag')
class Tags extends Table with Syncable {
  TextColumn get name => text().unique()();
  IntColumn get color => integer().withDefault(const Constant(0xFF9E9E9E))();
}

@DataClassName('TxnTag')
class TransactionTags extends Table {
  TextColumn get transactionId => text()();
  TextColumn get tagId => text()();
  @override
  Set<Column> get primaryKey => {transactionId, tagId};
}

@DataClassName('Budget')
class Budgets extends Table with Syncable {
  TextColumn get categoryId => text().nullable()(); // null = ngân sách tổng
  TextColumn get period => text()(); // week / month / quarter / year
  IntColumn get amount => integer()();
  BoolColumn get rollover => boolean().withDefault(const Constant(false))();
  DateTimeColumn get startDate => dateTime().clientDefault(DateTime.now)();
}

@DataClassName('RecurringRule')
class RecurringRules extends Table with Syncable {
  TextColumn get walletId => text()();
  TextColumn get type => text()();
  IntColumn get amount => integer()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get rrule => text()(); // tập con iCalendar: FREQ=...;INTERVAL=...
  DateTimeColumn get nextRunAt => dateTime()();
  BoolColumn get autoConfirm => boolean().withDefault(const Constant(false))();
}

/// Nội dung thông báo gốc. Cả DB đã mã hoá (sqlite3mc), tự xoá sau 30 ngày (US-02 AC4).
@DataClassName('RawEvent')
class RawEvents extends Table with Syncable {
  TextColumn get source => text()(); // notification / email / import / ...
  TextColumn get sourceApp => text().nullable()();
  DateTimeColumn get receivedAt => dateTime()();
  TextColumn get content => text()();
  TextColumn get parseStatus => text()(); // parsed / unknown / dropped_otp / duplicate
  DateTimeColumn get expiresAt => dateTime()();
}

@DataClassName('ClassificationRule')
class ClassificationRules extends Table with Syncable {
  TextColumn get matchField => text()(); // merchant / note
  TextColumn get matchType => text()(); // contains / regex / exact
  TextColumn get pattern => text()();
  TextColumn get categoryId => text()();
  TextColumn get walletId => text().nullable()();
  IntColumn get priority => integer().withDefault(const Constant(0))();
}

@DataClassName('SyncEntry')
class SyncLog extends Table {
  IntColumn get seq => integer().autoIncrement()();
  TextColumn get entity => text()();
  TextColumn get entityId => text()();
  TextColumn get op => text()(); // insert / update / delete
  DateTimeColumn get changedAt => dateTime()();
  DateTimeColumn get syncedAt => dateTime().nullable()();
  IntColumn get remoteRow => integer().nullable()();
}

@DataClassName('Setting')
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(
  tables: [
    Wallets,
    Categories,
    Transactions,
    Tags,
    TransactionTags,
    Budgets,
    RecurringRules,
    RawEvents,
    ClassificationRules,
    SyncLog,
    Settings,
  ],
)
class AppDb extends _$AppDb {
  AppDb(super.e);

  /// Mở DB thật trên máy, mã hoá bằng khoá hex 256-bit lấy từ Keystore/Keychain.
  /// Web không có sqlite3mc: dùng sqlite3.wasm thường (xem README, mục hạn chế).
  factory AppDb.open(String hexKey) => AppDb(
    driftDatabase(
      name: 'magic_wallet',
      native: DriftNativeOptions(setup: (db) => applyKey(db, hexKey)),
      web: DriftWebOptions(sqlite3Wasm: Uri.parse('sqlite3.wasm'), driftWorker: Uri.parse('drift_worker.js')),
    ),
  );

  /// Đặt khoá sqlite3mc trước mọi truy vấn khác, rồi bật WAL (NFR-08: tắt đột ngột không mất giao dịch).
  static void applyKey(CommonDatabase db, String hexKey) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hexKey)) throw ArgumentError('Khoá DB phải là 64 ký tự hex');
    db.execute("PRAGMA hexkey = '$hexKey';");
    db.execute('PRAGMA journal_mode = WAL;');
  }

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await seedCategories();
    },
  );

  Future<void> seedCategories() async {
    var order = 0;
    Future<void> add(String type, String icon, String name, int color, List<String> children, {bool fixed = false}) async {
      final parentId = newId();
      await into(categories).insert(
        CategoriesCompanion.insert(
          id: Value(parentId),
          name: name,
          type: type,
          icon: Value(icon),
          color: Value(color),
          isFixedCost: Value(fixed),
          sortOrder: Value(order++),
        ),
      );
      for (final c in children) {
        await into(categories).insert(
          CategoriesCompanion.insert(
            name: c,
            type: type,
            parentId: Value(parentId),
            icon: Value(icon),
            color: Value(color),
            isFixedCost: Value(fixed),
            sortOrder: Value(order++),
          ),
        );
      }
    }

    await add('expense', '🍜', 'Ăn uống', 0xFFE64A19, ['Ăn sáng', 'Ăn trưa', 'Ăn tối', 'Cà phê']);
    await add('expense', '🛵', 'Di chuyển', 0xFF1976D2, ['Xăng xe', 'Gửi xe', 'Taxi/Grab']);
    await add('expense', '🛍️', 'Mua sắm', 0xFF8E24AA, ['Quần áo', 'Đồ gia dụng']);
    await add('expense', '💡', 'Hóa đơn', 0xFFF9A825, ['Điện', 'Nước', 'Internet', 'Điện thoại'], fixed: true);
    await add('expense', '🏠', 'Nhà ở', 0xFF5D4037, ['Tiền nhà'], fixed: true);
    await add('expense', '🎬', 'Giải trí', 0xFFD81B60, []);
    await add('expense', '💊', 'Sức khỏe', 0xFF00897B, []);
    await add('expense', '📚', 'Giáo dục', 0xFF3949AB, []);
    await add('expense', '👨‍👩‍👧', 'Gia đình', 0xFF6D4C41, []);
    await add('expense', '🎁', 'Quà tặng', 0xFFC2185B, []);
    await add('expense', '📦', 'Khác', 0xFF757575, []);
    await add('income', '💰', 'Lương', 0xFF2E7D32, []);
    await add('income', '🎉', 'Thưởng', 0xFF388E3C, []);
    await add('income', '💵', 'Thu khác', 0xFF43A047, []);
  }

  // ---- Cài đặt key–value ----
  Future<String?> getSetting(String key) async =>
      (await (select(settings)..where((s) => s.key.equals(key))).getSingleOrNull())?.value;

  Future<void> setSetting(String key, String value) =>
      into(settings).insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value));

  Stream<String?> watchSetting(String key) =>
      (select(settings)..where((s) => s.key.equals(key))).watchSingleOrNull().map((s) => s?.value);
}

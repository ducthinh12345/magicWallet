import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services.dart';
import '../sync/backup.dart';
import '../sync/sheet_io.dart';
import '../sync/sheets_sync.dart';
import 'widgets.dart';

/// Lưu/chia sẻ file qua bảng chia sẻ của hệ thống (Android/iOS) hoặc tải xuống (web).
Future<void> shareBytes(Uint8List bytes, String name, String mime) => SharePlus.instance.share(
  ShareParams(
    files: [XFile.fromData(bytes, name: name, mimeType: mime)],
    fileNameOverrides: [name],
  ),
);

String _csvCell(Object? v) {
  // Ép chữ cho ô bắt đầu bằng = + - @ để Excel không chạy như công thức.
  final s = '${safeCell(v) ?? ''}';
  return s.contains(RegExp(r'[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
}

/// Xuất CSV giao dịch (UC-10). Cùng cột với tab "Giao dịch" trên Sheet, bỏ cột _sig.
Future<void> exportTxnsCsv(BuildContext context, {DateTime? from, DateTime? to, required String name}) async {
  final s = Services.I;
  final q = s.db.select(s.db.transactions)
    ..where((t) => t.deletedAt.isNull() & t.status.equals('confirmed'))
    ..orderBy([(t) => OrderingTerm.asc(t.occurredAt)]);
  if (from != null) q.where((t) => t.occurredAt.isBiggerOrEqualValue(from));
  if (to != null) q.where((t) => t.occurredAt.isSmallerThanValue(to));
  final txns = await q.get();
  final cats = {for (final c in await s.repo.allCategories()) c.id: c};
  final wallets = {for (final w in await s.db.select(s.db.wallets).get()) w.id: w};
  final buf = StringBuffer('﻿'); // BOM để Excel đọc đúng tiếng Việt
  buf.writeln(txnHeader.take(11).join(','));
  for (final t in txns) {
    final row = SheetsSync.txnRow(t, cats, wallets, await s.repo.tagsOf(t.id)).take(11);
    // txnRow đã thêm dấu ' cho Sheet; CSV tự xử lý lại nên bỏ dấu đó trước.
    buf.writeln(row.map((v) => _csvCell(v is String && v.startsWith("'") ? v.substring(1) : v)).join(','));
  }
  final file = 'vi-rieng-${name.replaceAll(RegExp(r'[^\w\-]+'), '_')}.csv';
  await shareBytes(Uint8List.fromList(utf8.encode(buf.toString())), file, 'text/csv');
  if (context.mounted) toast(context, 'Đã xuất ${txns.length} giao dịch');
}

/// Xuất JSON toàn bộ dữ liệu, không mã hoá — miễn phí cho mọi người dùng (1.4: dữ liệu thuộc về người dùng).
Future<void> exportAllJson(BuildContext context) async {
  final ok = await confirm(
    context,
    'File JSON không mã hoá, chứa toàn bộ dữ liệu tài chính. Chỉ lưu ở nơi bạn tin cậy.',
    ok: 'Xuất',
  );
  if (!ok) return;
  final data = await DbSnapshot(Services.I.db).export();
  await shareBytes(
    Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent(' ').convert(data))),
    'vi-rieng-${DateTime.now().toIso8601String().substring(0, 10)}.json',
    'application/json',
  );
}

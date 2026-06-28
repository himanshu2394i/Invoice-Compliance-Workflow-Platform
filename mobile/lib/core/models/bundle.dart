import 'package:hive/hive.dart';

part 'bundle.g.dart';

@HiveType(typeId: 0)
class QueuedPhoto extends HiveObject {
  @HiveField(0)
  String localId;

  @HiveField(1)
  String localPath; // absolute path to compressed JPEG on device

  @HiveField(2)
  String documentType; // e.g. "INVOICE" or "GATE_ENTRY_NOTE"

  @HiveField(3)
  String label; // human-readable, e.g. "Tax Invoice", "Gate Entry / Discrepancy Note"

  @HiveField(4)
  bool isPrimary; // true for the invoice photo, false for supporting docs

  QueuedPhoto({
    required this.localId,
    required this.localPath,
    required this.documentType,
    required this.label,
    required this.isPrimary,
  });
}

@HiveType(typeId: 1)
class QueuedBundle extends HiveObject {
  @HiveField(0)
  String localId; // UUID generated on device

  @HiveField(1)
  String invoiceNumber;

  @HiveField(2)
  String entityGstin; // seller GSTIN — uniquely identifies the Meridian entity

  @HiveField(3)
  String buyerGstin;

  @HiveField(4)
  String buyerName;

  @HiveField(5)
  String invoiceDate; // ISO-8601 date string "YYYY-MM-DD"

  @HiveField(6)
  double taxableAmount;

  @HiveField(7)
  double totalAmount;

  @HiveField(8)
  List<QueuedPhoto> photos;

  @HiveField(9)
  String status; // "pending" | "syncing" | "synced" | "failed"

  @HiveField(10)
  String? syncError;

  @HiveField(11)
  int createdAtMs; // milliseconds since epoch

  QueuedBundle({
    required this.localId,
    required this.invoiceNumber,
    required this.entityGstin,
    required this.buyerGstin,
    required this.buyerName,
    required this.invoiceDate,
    required this.taxableAmount,
    required this.totalAmount,
    required this.photos,
    this.status = 'pending',
    this.syncError,
    required this.createdAtMs,
  });
}

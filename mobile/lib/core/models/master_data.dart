/// Master-data DTOs: principals, invoice-series registry entries, and buyer
/// branches. Mirrors backend/internal/db/distributor.go JSON field names.
class Principal {
  final String id;
  final String name;
  final String? code;

  const Principal({required this.id, required this.name, this.code});

  factory Principal.fromJson(Map<String, dynamic> json) => Principal(
        id: json['id'] as String,
        name: json['name'] as String,
        code: json['code'] as String?,
      );
}

class SeriesEntry {
  final String id;
  final String seriesPrefix;
  final String? entityId;
  final String? entityName;
  final String? principalId;
  final String? principalName;

  const SeriesEntry({
    required this.id,
    required this.seriesPrefix,
    this.entityId,
    this.entityName,
    this.principalId,
    this.principalName,
  });

  factory SeriesEntry.fromJson(Map<String, dynamic> json) => SeriesEntry(
        id: json['id'] as String,
        seriesPrefix: json['series_prefix'] as String,
        entityId: json['entity_id'] as String?,
        entityName: json['entity_name'] as String?,
        principalId: json['principal_id'] as String?,
        principalName: json['principal_name'] as String?,
      );
}

class BuyerBranch {
  final String id;
  final String buyerId;
  final String name;
  final String? code;
  final String? gateEntryPrefix;

  const BuyerBranch({
    required this.id,
    required this.buyerId,
    required this.name,
    this.code,
    this.gateEntryPrefix,
  });

  factory BuyerBranch.fromJson(Map<String, dynamic> json) => BuyerBranch(
        id: json['id'] as String,
        buyerId: json['buyer_id'] as String,
        name: json['name'] as String,
        code: json['code'] as String?,
        gateEntryPrefix: json['gate_entry_prefix'] as String?,
      );
}

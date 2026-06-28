class BuyerRequirement {
  final String id;
  final String buyerId;
  final String documentType;
  final String label;
  final bool isBuyerGenerated;
  final int sortOrder;

  const BuyerRequirement({
    required this.id,
    required this.buyerId,
    required this.documentType,
    required this.label,
    required this.isBuyerGenerated,
    required this.sortOrder,
  });

  factory BuyerRequirement.fromJson(Map<String, dynamic> json) => BuyerRequirement(
        id: json['id'] as String,
        buyerId: json['buyer_id'] as String,
        documentType: json['document_type'] as String,
        label: json['label'] as String,
        isBuyerGenerated: json['is_buyer_generated'] as bool? ?? false,
        sortOrder: json['sort_order'] as int? ?? 0,
      );
}

class BuyerWithRequirements {
  final Map<String, dynamic>? buyer;
  final List<BuyerRequirement> requirements;

  const BuyerWithRequirements({this.buyer, required this.requirements});

  factory BuyerWithRequirements.fromJson(Map<String, dynamic> json) {
    final rawReqs = json['requirements'] as List<dynamic>? ?? [];
    return BuyerWithRequirements(
      buyer: json['buyer'] as Map<String, dynamic>?,
      requirements: rawReqs
          .map((r) => BuyerRequirement.fromJson(r as Map<String, dynamic>))
          .toList(),
    );
  }
}

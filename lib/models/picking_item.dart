class StockLocation {
  final String code;
  final double qty;

  StockLocation({required this.code, required this.qty});

  factory StockLocation.fromJson(Map<String, dynamic> json) {
    return StockLocation(
      code: json['code'] ?? '',
      qty: ((json['qty'] ?? 0) as num).toDouble(),
    );
  }
}

class PickingItem {
  final int id;
  final String partNo;
  final String partName;
  final String model;
  final int qtyPlan;
  final int qtyPicked;
  final String status;
  final String location;
  final String? expectedLocation;
  final List<StockLocation> stockLocations;
  final double progress;
  final String source;
  final String? poNo;
  final int? deliveryOrderId;
  final String? doNo;
  final int? tripNo;

  PickingItem({
    required this.id,
    required this.partNo,
    required this.partName,
    required this.model,
    required this.qtyPlan,
    required this.qtyPicked,
    required this.status,
    required this.location,
    this.expectedLocation,
    this.stockLocations = const [],
    required this.progress,
    required this.source,
    this.poNo,
    this.deliveryOrderId,
    this.doNo,
    this.tripNo,
  });

  int get qtyRemaining => (qtyPlan - qtyPicked).clamp(0, qtyPlan);

  String get locationDisplay {
    if (expectedLocation != null && expectedLocation!.isNotEmpty) {
      return '📍 $expectedLocation';
    }
    if (stockLocations.isNotEmpty) {
      return stockLocations.map((l) => '${l.code} (${l.qty.toInt()})').join(', ');
    }
    return '-';
  }

  factory PickingItem.fromJson(Map<String, dynamic> json) {
    final rawStockLocations = json['stock_locations'] as List? ?? [];
    return PickingItem(
      id: json['id'],
      partNo: json['part_no'] ?? 'N/A',
      partName: json['part_name'] ?? 'N/A',
      model: json['model'] ?? '-',
      qtyPlan: json['qty_plan'] ?? 0,
      qtyPicked: json['qty_picked'] ?? 0,
      status: json['status'] ?? 'pending',
      location: json['location'] ?? '-',
      expectedLocation: json['expected_location'],
      stockLocations: rawStockLocations.map((l) => StockLocation.fromJson(l as Map<String, dynamic>)).toList(),
      progress: ((json['progress'] ?? 0) as num).toDouble(),
      source: json['source'] ?? 'daily_plan',
      poNo: json['po_no'],
      deliveryOrderId: json['delivery_order_id'],
      doNo: json['do_no'],
      tripNo: json['trip_no'],
    );
  }
}

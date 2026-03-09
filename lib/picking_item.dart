class PickingItem {
  final int id;
  final String partNo;
  final String partName;
  final String model;
  final int qtyPlan;
  final int qtyPicked;
  final String status;
  final String location;
  final double progress;
  final String source; // 'daily_plan' or 'po'
  final String? poNo; // PO number if source == 'po'
  final int? salesOrderId;
  final String? soNo;
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
    required this.progress,
    required this.source,
    this.poNo,
    this.salesOrderId,
    this.soNo,
    this.tripNo,
  });

  factory PickingItem.fromJson(Map<String, dynamic> json) {
    return PickingItem(
      id: json['id'],
      partNo: json['part_no'],
      partName: json['part_name'],
      model: json['model'],
      qtyPlan: json['qty_plan'],
      qtyPicked: json['qty_picked'],
      status: json['status'],
      location: json['location'] ?? '-',
      progress: (json['progress'] as num).toDouble(),
      source: json['source'] ?? 'daily_plan',
      poNo: json['po_no'],
      salesOrderId: json['sales_order_id'],
      soNo: json['so_no'],
      tripNo: json['trip_no'],
    );
  }
}

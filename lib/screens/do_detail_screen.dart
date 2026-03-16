import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import 'scanner_screen.dart';

class DoDetailScreen extends StatefulWidget {
  final int deliveryOrderId;
  final String doNo;
  final String date;

  const DoDetailScreen({
    super.key,
    required this.deliveryOrderId,
    required this.doNo,
    required this.date,
  });

  @override
  State<DoDetailScreen> createState() => _DoDetailScreenState();
}

class _DoDetailScreenState extends State<DoDetailScreen> {
  final _api = ApiService();
  Map<String, dynamic>? _doInfo;
  List<Map<String, dynamic>> _items = [];
  bool _loading = false;
  String? _scannedLocation;

  @override
  void initState() {
    super.initState();
    _fetchDetail();
  }

  Future<void> _fetchDetail() async {
    setState(() => _loading = true);
    try {
      final res = await _api.getDeliveryOrderDetail(widget.deliveryOrderId, widget.date);
      if (res['auth_expired'] == true) {
        if (mounted) Navigator.pop(context);
        return;
      }
      if (res['success'] == true) {
        setState(() {
          _doInfo = res['delivery_order'] as Map<String, dynamic>?;
          _items = (res['items'] as List).cast<Map<String, dynamic>>();
        });
      } else {
        _showError(res['message'] ?? 'Failed to load DO detail');
      }
    } catch (e) {
      _showError('Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700),
    );
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.green.shade700),
    );
  }

  // ─── SCAN FLOW ──────────────────────────────────────────────────

  void _startScan() async {
    // Step 1: Scan Location
    final location = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => const ScannerScreen(
          title: 'Scan Location',
          hintText: 'Scan lokasi gudang / rak',
          manualLabel: 'Location Code',
        ),
      ),
    );
    if (location == null || location.isEmpty) return;

    final locationCode = location.toUpperCase().trim();
    setState(() => _scannedLocation = locationCode);

    // Validate location against backend
    if (!mounted) return;
    _showLoading();

    final locRes = await _api.scanLocation(
      deliveryOrderId: widget.deliveryOrderId,
      date: widget.date,
      locationCode: locationCode,
    );

    if (mounted) Navigator.pop(context); // dismiss loading

    if (locRes['success'] != true) {
      _showError(locRes['message'] ?? 'Invalid location');
      setState(() => _scannedLocation = null);
      return;
    }

    final partsAtLocation = (locRes['parts'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (partsAtLocation.isEmpty) {
      _showError('No parts with stock at $locationCode for this DO');
      return;
    }

    if (!mounted) return;

    // Show snackbar with info
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$locationCode — ${partsAtLocation.length} parts available. Scan part now.'),
        backgroundColor: Colors.indigo,
        duration: const Duration(seconds: 2),
      ),
    );

    // Step 2: Scan Part
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    final partCode = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => const ScannerScreen(
          title: 'Scan Part',
          hintText: 'Scan barcode / QR part',
          manualLabel: 'Part No / Barcode',
        ),
      ),
    );
    if (partCode == null || partCode.isEmpty) return;

    // Validate part against backend
    if (!mounted) return;
    _showLoading();

    final partRes = await _api.scanPart(
      deliveryOrderId: widget.deliveryOrderId,
      date: widget.date,
      locationCode: locationCode,
      partCode: partCode.toUpperCase().trim(),
    );

    if (mounted) Navigator.pop(context); // dismiss loading

    if (partRes['success'] != true) {
      final altLocations = partRes['alternative_locations'] as List?;
      if (altLocations != null && altLocations.isNotEmpty) {
        _showAlternativeLocations(partCode, altLocations.cast<Map<String, dynamic>>());
      } else {
        _showError(partRes['message'] ?? 'Part not valid');
      }
      return;
    }

    // Step 3: Show pick dialog
    final part = partRes['part'] as Map<String, dynamic>;
    final pick = partRes['pick'] as Map<String, dynamic>;
    final stock = partRes['stock'] as Map<String, dynamic>;
    final maxPick = (partRes['max_pick'] ?? 0) as int;

    _showPickDialog(
      partNo: part['part_no'] ?? partCode,
      partName: part['part_name'] ?? '',
      locationCode: locationCode,
      qtyPlan: (pick['qty_plan'] ?? 0) as int,
      qtyPicked: (pick['qty_picked'] ?? 0) as int,
      qtyRemaining: (pick['qty_remaining'] ?? 0) as int,
      stockAvailable: ((stock['qty_available'] ?? 0) as num).toDouble(),
      batchNo: stock['batch_no']?.toString(),
      maxPick: maxPick,
    );
  }

  void _showLoading() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );
  }

  void _showAlternativeLocations(String partCode, List<Map<String, dynamic>> locations) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('No stock at $_scannedLocation', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$partCode has stock at:', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
            const SizedBox(height: 8),
            ...locations.map((loc) => Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(loc['location_code'] ?? '', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade800)),
                  Text('${((loc['qty'] ?? 0) as num).toInt()} pcs',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade700)),
                ],
              ),
            )),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  // ─── Quick pick from list (tap item) ────────────────────────────

  void _quickPick(Map<String, dynamic> item) async {
    final partNo = item['part_no'] ?? '';
    final partName = item['part_name'] ?? '';
    final qtyPlan = (item['qty_plan'] ?? 0) as int;
    final qtyPicked = (item['qty_picked'] ?? 0) as int;
    final qtyRemaining = (item['qty_remaining'] ?? 0) as int;
    final stockLocations = (item['stock_locations'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    if (qtyRemaining <= 0) return;

    // If no location scanned yet, ask to scan
    if (_scannedLocation == null) {
      _showError('Scan location first');
      _startScan();
      return;
    }

    // Check if stock exists at scanned location
    final stockAtLoc = stockLocations.firstWhere(
      (s) => (s['location_code'] ?? '').toString().toUpperCase() == _scannedLocation,
      orElse: () => <String, dynamic>{},
    );

    final stockQty = ((stockAtLoc['qty_available'] ?? stockAtLoc['qty'] ?? 0) as num).toDouble();
    final batchNo = stockAtLoc['batch_no']?.toString();

    if (stockAtLoc.isEmpty || stockQty <= 0) {
      // Show warning but still allow pick
      _showPickDialog(
        partNo: partNo,
        partName: partName,
        locationCode: _scannedLocation!,
        qtyPlan: qtyPlan,
        qtyPicked: qtyPicked,
        qtyRemaining: qtyRemaining,
        stockAvailable: stockQty,
        batchNo: batchNo,
        maxPick: qtyRemaining,
        noStockWarning: true,
      );
      return;
    }

    _showPickDialog(
      partNo: partNo,
      partName: partName,
      locationCode: _scannedLocation!,
      qtyPlan: qtyPlan,
      qtyPicked: qtyPicked,
      qtyRemaining: qtyRemaining,
      stockAvailable: stockQty,
      batchNo: batchNo,
      maxPick: qtyRemaining < stockQty.toInt() ? qtyRemaining : stockQty.toInt(),
    );
  }

  // ─── PICK DIALOG ────────────────────────────────────────────────

  void _showPickDialog({
    required String partNo,
    required String partName,
    required String locationCode,
    required int qtyPlan,
    required int qtyPicked,
    required int qtyRemaining,
    required double stockAvailable,
    String? batchNo,
    required int maxPick,
    bool noStockWarning = false,
  }) {
    final qtyController = TextEditingController(text: maxPick > 0 ? maxPick.toString() : '');
    bool submitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(partNo, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
              if (partName.isNotEmpty)
                Text(partName, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(height: 8),
              // Location info
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.location_on, size: 16, color: Colors.indigo.shade700),
                    const SizedBox(width: 6),
                    Text(locationCode,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
                    const Spacer(),
                    Text('Stock: ${stockAvailable.toInt()}',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade700)),
                  ],
                ),
              ),
              if (noStockWarning) ...[
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: Text('No stock found at this location for this part',
                      style: TextStyle(fontSize: 11, color: Colors.amber.shade800, fontWeight: FontWeight.bold)),
                ),
              ],
              if (batchNo != null && batchNo.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Batch: $batchNo', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ],
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Status row
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _infoCol('Plan', qtyPlan.toString(), Colors.indigo),
                    _infoCol('Picked', qtyPicked.toString(), Colors.green),
                    _infoCol('Remaining', qtyRemaining.toString(), Colors.orange),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                autofocus: true,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  labelText: 'Quantity to pick',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.pop(ctx),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: submitting
                  ? null
                  : () async {
                      final qty = int.tryParse(qtyController.text) ?? 0;
                      if (qty <= 0) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('Quantity must be > 0')),
                        );
                        return;
                      }

                      setDialogState(() => submitting = true);

                      final res = await _api.updatePick(
                        date: widget.date,
                        partNo: partNo,
                        qty: qty,
                        location: locationCode,
                        deliveryOrderId: widget.deliveryOrderId,
                        batchNo: batchNo,
                      );

                      if (res['auth_expired'] == true) {
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) Navigator.pop(context);
                        return;
                      }

                      if (ctx.mounted) Navigator.pop(ctx);

                      if (res['success'] == true) {
                        final data = res['data'] as Map<String, dynamic>? ?? {};
                        final applied = (data['applied_qty'] ?? qty) as int;
                        final doCompleted = data['do_completed'] == true;
                        final msg = doCompleted
                            ? 'Picked $applied x $partNo — DO completed! DN created.'
                            : 'Picked $applied x $partNo @ $locationCode';
                        _showSuccess(msg);
                        _fetchDetail();

                        if (doCompleted) {
                          // Show completion dialog
                          await Future.delayed(const Duration(milliseconds: 500));
                          if (mounted) {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                title: Row(
                                  children: [
                                    Icon(Icons.check_circle, color: Colors.green.shade600, size: 28),
                                    const SizedBox(width: 8),
                                    const Text('DO Complete!'),
                                  ],
                                ),
                                content: Text('All parts picked. Delivery Note has been created for ${widget.doNo}.'),
                                actions: [
                                  ElevatedButton(
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      Navigator.pop(context); // Back to DO list
                                    },
                                    child: const Text('BACK TO LIST'),
                                  ),
                                ],
                              ),
                            );
                          }
                        }
                      } else {
                        _showError(res['message'] ?? 'Pick failed');
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: submitting
                  ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('PICK', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoCol(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color)),
        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade500)),
      ],
    );
  }

  // ─── BUILD ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final qtyPlan = (_doInfo?['qty_plan'] ?? 0) as int;
    final qtyPicked = (_doInfo?['qty_picked'] ?? 0) as int;
    final progress = ((_doInfo?['progress'] ?? 0) as num).toDouble();
    final customer = _doInfo?['customer'] as Map<String, dynamic>? ?? {};

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.doNo, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(onPressed: _fetchDetail, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          // DO info header
          if (_doInfo != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Colors.indigo.shade50,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(customer['name'] ?? '-',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text('$qtyPicked / $qtyPlan picked',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: progress >= 100 ? Colors.green.shade100 : Colors.indigo.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('${progress.round()}%',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: progress >= 100 ? Colors.green.shade800 : Colors.indigo.shade800,
                            )),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress / 100,
                      minHeight: 6,
                      backgroundColor: Colors.grey.shade200,
                      color: progress >= 100 ? Colors.green : Colors.indigo,
                    ),
                  ),
                ],
              ),
            ),

          // Location badge
          if (_scannedLocation != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.indigo.shade700,
              child: Row(
                children: [
                  const Icon(Icons.location_on, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Location: $_scannedLocation',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _scannedLocation = null),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(40),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('Clear', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),

          // Parts list
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey.shade300),
                            const SizedBox(height: 12),
                            Text('No picking items', style: TextStyle(color: Colors.grey.shade500)),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _fetchDetail,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _items.length,
                          itemBuilder: (context, index) => _buildItemCard(_items[index]),
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startScan,
        label: const Text('SCAN', style: TextStyle(fontWeight: FontWeight.bold)),
        icon: const Icon(Icons.qr_code_scanner),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildItemCard(Map<String, dynamic> item) {
    final partNo = item['part_no'] ?? 'N/A';
    final partName = item['part_name'] ?? '';
    final qtyPlan = (item['qty_plan'] ?? 0) as int;
    final qtyPicked = (item['qty_picked'] ?? 0) as int;
    final qtyRemaining = (item['qty_remaining'] ?? 0) as int;
    final status = item['status'] ?? 'pending';
    final expectedLocation = item['expected_location']?.toString();
    final stockLocations = (item['stock_locations'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final isCompleted = status == 'completed';

    final statusColor = isCompleted
        ? Colors.green
        : status == 'picking'
            ? Colors.orange
            : Colors.grey;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isCompleted ? Colors.green.shade50 : Colors.white,
      elevation: isCompleted ? 0 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: isCompleted ? null : () => _quickPick(item),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(partNo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.indigo)),
                        if (partName.isNotEmpty)
                          Text(partName, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('$qtyPicked / $qtyPlan',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      if (qtyRemaining > 0)
                        Text('$qtyRemaining left',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange.shade700)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Tags row
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: statusColor.withAlpha(30), borderRadius: BorderRadius.circular(4)),
                    child: Text(status.toUpperCase(),
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: statusColor)),
                  ),
                  if (expectedLocation != null && expectedLocation.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(4)),
                      child: Text('Default: $expectedLocation',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
                    ),
                  ...stockLocations.map((loc) {
                    final code = loc['location_code'] ?? '';
                    final qty = ((loc['qty'] ?? 0) as num).toInt();
                    final isScanned = _scannedLocation != null && code.toUpperCase() == _scannedLocation;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isScanned ? Colors.green.shade100 : Colors.green.shade50,
                        borderRadius: BorderRadius.circular(4),
                        border: isScanned ? Border.all(color: Colors.green.shade400) : null,
                      ),
                      child: Text('$code ($qty)',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: isScanned ? Colors.green.shade800 : Colors.green.shade700,
                          )),
                    );
                  }),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
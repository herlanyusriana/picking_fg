import 'dart:convert';
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

  void _showLoading() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );
  }

  // Parse QR scan result — could be JSON payload or plain location code
  String _parseLocationCode(String raw) {
    final trimmed = raw.trim();
    if (trimmed.startsWith('{')) {
      try {
        final json = jsonDecode(trimmed) as Map<String, dynamic>;
        // Support both old format (LOCATION) and new format (location_code)
        final code = json['location_code'] ?? json['LOCATION'] ?? json['location'] ?? json['code'];
        if (code != null) {
          return code.toString().toUpperCase().trim();
        }
      } catch (_) {}
    }
    return trimmed.toUpperCase();
  }

  // Parse QR scan result for part — could be JSON or plain part_no/barcode
  String _parsePartCode(String raw) {
    final trimmed = raw.trim();
    if (trimmed.startsWith('{')) {
      try {
        final json = jsonDecode(trimmed) as Map<String, dynamic>;
        return (json['part_no'] ?? json['barcode'] ?? json['code'] ?? trimmed).toString().toUpperCase().trim();
      } catch (_) {}
    }
    return trimmed.toUpperCase();
  }

  // Merge stock locations by location_code (sum qty across batches)
  List<Map<String, dynamic>> _mergeStockLocations(List<Map<String, dynamic>> locations) {
    final Map<String, Map<String, dynamic>> merged = {};
    for (final loc in locations) {
      final code = (loc['location_code'] ?? '').toString().toUpperCase();
      if (code.isEmpty) continue;
      if (merged.containsKey(code)) {
        merged[code]!['qty'] = ((merged[code]!['qty'] as num) + ((loc['qty'] ?? 0) as num)).toDouble();
      } else {
        merged[code] = {
          'location_code': code,
          'qty': ((loc['qty'] ?? 0) as num).toDouble(),
          'batch_no': loc['batch_no'],
        };
      }
    }
    return merged.values.toList()..sort((a, b) => ((b['qty'] as num)).compareTo(a['qty'] as num));
  }

  // ─── FLOW: Tap Part → Show Locations → Scan Location → Scan Part → Qty ───

  void _onTapPart(Map<String, dynamic> item) {
    final qtyRemaining = (item['qty_remaining'] ?? 0) as int;
    if (qtyRemaining <= 0) return;

    final rawLocations = (item['stock_locations'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final stockLocations = _mergeStockLocations(rawLocations);
    final partNo = item['part_no'] ?? '';
    final partName = item['part_name'] ?? '';
    final expectedLocation = item['expected_location']?.toString();

    if (stockLocations.isEmpty) {
      _showError('No stock available for $partNo');
      return;
    }

    // Show location picker bottom sheet
    _showLocationPicker(
      partNo: partNo,
      partName: partName,
      expectedLocation: expectedLocation,
      stockLocations: stockLocations,
      item: item,
    );
  }

  void _showLocationPicker({
    required String partNo,
    required String partName,
    required String? expectedLocation,
    required List<Map<String, dynamic>> stockLocations,
    required Map<String, dynamic> item,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(partNo, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
                      if (partName.isNotEmpty)
                        Text(partName, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('Scan lokasi di bawah ini:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
            const SizedBox(height: 12),

            // Location list
            ...stockLocations.map((loc) {
              final code = loc['location_code'] ?? '';
              final qty = ((loc['qty'] ?? 0) as num).toInt();
              final batch = loc['batch_no']?.toString();
              final isDefault = expectedLocation != null && code.toUpperCase() == expectedLocation.toUpperCase();

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: isDefault ? Colors.indigo.shade50 : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      Navigator.pop(ctx);
                      _proceedWithLocation(code, item);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          Icon(Icons.location_on, color: isDefault ? Colors.indigo : Colors.grey.shade600, size: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(code, style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: isDefault ? Colors.indigo.shade800 : Colors.black87,
                                    )),
                                    if (isDefault) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: Colors.indigo.shade100,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text('DEFAULT', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.indigo.shade700)),
                                      ),
                                    ],
                                  ],
                                ),
                                if (batch != null && batch.isNotEmpty)
                                  Text('Batch: $batch', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green.shade200),
                            ),
                            child: Text('$qty pcs', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.green.shade700)),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.chevron_right, color: Colors.grey.shade400),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),

            const SizedBox(height: 8),

            // Scan location button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _scanLocationForPart(item);
                },
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan Lokasi Lain'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            SizedBox(height: MediaQuery.of(ctx).viewInsets.bottom + 8),
          ],
        ),
      ),
    );
  }

  // User tapped a location from the list — scan location to confirm
  void _proceedWithLocation(String locationCode, Map<String, dynamic> item) async {
    // Scan location barcode to confirm
    final scanned = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => ScannerScreen(
          title: 'Scan Lokasi: $locationCode',
          hintText: 'Scan barcode lokasi $locationCode',
          manualLabel: 'Location Code',
        ),
      ),
    );
    if (scanned == null || scanned.isEmpty) return;

    final scannedCode = _parseLocationCode(scanned);

    // Verify scanned matches expected
    if (scannedCode != locationCode.toUpperCase()) {
      if (!mounted) return;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Lokasi tidak cocok', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          content: Text('Expected: $locationCode\nScanned: $scannedCode\n\nLanjut dengan $scannedCode?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('BATAL')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('LANJUT')),
          ],
        ),
      );
      if (proceed != true) return;
    }

    // Validate location via API
    if (!mounted) return;
    _showLoading();

    final locRes = await _api.scanLocation(
      deliveryOrderId: widget.deliveryOrderId,
      date: widget.date,
      locationCode: scannedCode,
    );

    if (mounted) Navigator.pop(context); // dismiss loading

    if (locRes['success'] != true) {
      _showError(locRes['message'] ?? 'Invalid location');
      return;
    }

    // Proceed to scan part
    if (!mounted) return;
    _scanPartAtLocation(scannedCode, item);
  }

  // User chose "Scan Lokasi Lain" — free scan
  void _scanLocationForPart(Map<String, dynamic> item) async {
    final scanned = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => const ScannerScreen(
          title: 'Scan Location',
          hintText: 'Scan lokasi gudang / rak',
          manualLabel: 'Location Code',
        ),
      ),
    );
    if (scanned == null || scanned.isEmpty) return;

    final locationCode = _parseLocationCode(scanned);

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
      return;
    }

    if (!mounted) return;
    _scanPartAtLocation(locationCode, item);
  }

  // Scan part barcode at confirmed location
  void _scanPartAtLocation(String locationCode, Map<String, dynamic> item) async {
    final partNo = item['part_no'] ?? '';

    final scanned = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => ScannerScreen(
          title: 'Scan Part: $partNo',
          hintText: 'Scan barcode part $partNo',
          manualLabel: 'Part No / Barcode',
        ),
      ),
    );
    if (scanned == null || scanned.isEmpty) return;

    if (!mounted) return;
    _showLoading();

    final partRes = await _api.scanPart(
      deliveryOrderId: widget.deliveryOrderId,
      date: widget.date,
      locationCode: locationCode,
      partCode: _parsePartCode(scanned),
    );

    if (mounted) Navigator.pop(context); // dismiss loading

    if (partRes['success'] != true) {
      final altLocations = partRes['alternative_locations'] as List?;
      if (altLocations != null && altLocations.isNotEmpty) {
        _showAlternativeLocations(scanned, altLocations.cast<Map<String, dynamic>>());
      } else {
        _showError(partRes['message'] ?? 'Part not valid');
      }
      return;
    }

    // Show pick qty dialog
    final part = partRes['part'] as Map<String, dynamic>;
    final pick = partRes['pick'] as Map<String, dynamic>;
    final stock = partRes['stock'] as Map<String, dynamic>;
    final maxPick = (partRes['max_pick'] ?? 0) as int;

    _showPickDialog(
      partNo: part['part_no'] ?? partNo,
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

  void _showAlternativeLocations(String partCode, List<Map<String, dynamic>> locations) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('No stock at this location', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
              if (batchNo != null && batchNo.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Batch: $batchNo', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ],
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                                      Navigator.pop(context);
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
    final rawLocations = (item['stock_locations'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final stockLocations = _mergeStockLocations(rawLocations);
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
        onTap: isCompleted ? null : () => _onTapPart(item),
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
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('$code ($qty)',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.green.shade700)),
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
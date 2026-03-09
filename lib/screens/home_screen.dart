import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../models/picking_item.dart';
import 'login_screen.dart';
import 'scanner_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DateTime _selectedDate = DateTime.now();
  List<PickingItem> _items = [];
  bool _loading = false;
  String _userName = '';
  final _api = ApiService();

  @override
  void initState() {
    super.initState();
    _loadUser();
    _fetchData();
  }

  void _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _userName = prefs.getString('user_name') ?? 'User');
  }

  String get _dateStr => DateFormat('yyyy-MM-dd').format(_selectedDate);

  Future<void> _fetchData() async {
    setState(() => _loading = true);
    try {
      final res = await _api.getPickingList(_dateStr);
      if (res['auth_expired'] == true) {
        _handleAuthExpired();
        return;
      }
      if (res['success'] == true) {
        setState(() {
          _items = (res['data'] as List).map((i) => PickingItem.fromJson(i)).toList();
        });
      } else {
        _showError(res['message'] ?? 'Failed to load data');
      }
    } catch (e) {
      _showError('Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _handleAuthExpired() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session expired. Please login again.'), backgroundColor: Colors.orange),
      );
    }
  }

  void _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('LOGOUT')),
        ],
      ),
    );
    if (confirm != true) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
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



  // ---- SCAN FLOW ----
  void _startScan() async {
    final scannedValue = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const ScannerScreen()),
    );

    if (scannedValue == null || scannedValue.isEmpty) return;

    // Lookup part via API
    _processScannedPart(scannedValue);
  }

  void _processScannedPart(String partNo) async {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    final res = await _api.lookupPart(partNo, _dateStr);

    if (mounted) Navigator.pop(context); // dismiss loading

    if (res['auth_expired'] == true) {
      _handleAuthExpired();
      return;
    }

    if (res['success'] != true) {
      _showError(res['message'] ?? 'Part not found');
      return;
    }

    final part = res['part'];
    final picks = (res['picks'] as List).cast<Map<String, dynamic>>();

    if (picks.length == 1) {
      // Single SO - show pick dialog directly
      _showPickDialog(
        partNo: part['part_no'],
        partName: part['part_name'],
        doNo: picks[0]['do_no'],
        deliveryOrderId: picks[0]['delivery_order_id'],
        qtyPlan: picks[0]['qty_plan'],
        qtyPicked: picks[0]['qty_picked'],
        qtyRemaining: picks[0]['qty_remaining'],
      );
    } else {
      // Multiple SOs - let user choose
      _showSoSelector(part, picks);
    }
  }

  void _showSoSelector(Map<String, dynamic> part, List<Map<String, dynamic>> picks) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Text(part['part_no'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
              Text(part['part_name'], style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
              const SizedBox(height: 12),
              const Text('Select Delivery Order:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              ...picks.map((pick) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(pick['do_no'] ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('Plan: ${pick['qty_plan']} | Picked: ${pick['qty_picked']} | Remaining: ${pick['qty_remaining']}'),
                  trailing: pick['trip_no'] != null
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(6)),
                          child: Text('T${pick['trip_no']}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.orange.shade900)),
                        )
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    _showPickDialog(
                      partNo: part['part_no'],
                      partName: part['part_name'],
                      doNo: pick['do_no'],
                      deliveryOrderId: pick['delivery_order_id'],
                      qtyPlan: pick['qty_plan'],
                      qtyPicked: pick['qty_picked'],
                      qtyRemaining: pick['qty_remaining'],
                    );
                  },
                ),
              )),
            ],
          ),
        ),
      ),
    );
  }

  void _showPickDialog({
    required String partNo,
    required String partName,
    required String? doNo,
    required int? deliveryOrderId,
    required int qtyPlan,
    required int qtyPicked,
    required int qtyRemaining,
  }) {
    final qtyController = TextEditingController(text: qtyRemaining > 0 ? qtyRemaining.toString() : '1');
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
              Text(partName, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              if (doNo != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(doNo, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade500)),
                ),
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
                        date: _dateStr,
                        partNo: partNo,
                        qty: qty,
                        deliveryOrderId: deliveryOrderId,
                      );

                      if (res['auth_expired'] == true) {
                        if (ctx.mounted) Navigator.pop(ctx);
                        _handleAuthExpired();
                        return;
                      }

                      if (ctx.mounted) Navigator.pop(ctx);

                      if (res['success'] == true) {
                        final data = res['data'];
                        final applied = (data?['applied_qty'] ?? qty) as int;
                        final rejected = (data?['rejected_qty'] ?? 0) as int;
                        final status = data?['status'] ?? 'ok';
                        final msg = rejected > 0
                            ? 'Picked $applied/$qty x $partNo ($status). Rejected: $rejected'
                            : 'Picked $applied x $partNo ($status)';
                        _showSuccess(msg);
                        _fetchData();
                      } else if (res['require_do_selection'] == true && (res['options'] is List)) {
                        _showDoSelectorForRetry(
                          partNo: partNo,
                          partName: partName,
                          qty: qty,
                          options: (res['options'] as List).cast<dynamic>(),
                        );
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

  void _showDoSelectorForRetry({
    required String partNo,
    required String partName,
    required int qty,
    required List<dynamic> options,
  }) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(partNo, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
              Text(partName, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(height: 12),
              const Text('Part ini ada di beberapa DO. Pilih DO:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...options.map((optRaw) {
                final opt = Map<String, dynamic>.from(optRaw as Map);
                final doId = opt['delivery_order_id'] as int?;
                return Card(
                  child: ListTile(
                    title: Text(opt['do_no']?.toString() ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('Trip: ${opt['trip_no'] ?? '-'} | Remaining: ${opt['qty_remaining'] ?? 0}'),
                    onTap: doId == null
                        ? null
                        : () async {
                            Navigator.pop(ctx);
                            final res = await _api.updatePick(
                              date: _dateStr,
                              partNo: partNo,
                              qty: qty,
                              deliveryOrderId: doId,
                            );

                            if (res['auth_expired'] == true) {
                              _handleAuthExpired();
                              return;
                            }

                            if (res['success'] == true) {
                              final data = res['data'];
                              final applied = (data?['applied_qty'] ?? qty) as int;
                              final rejected = (data?['rejected_qty'] ?? 0) as int;
                              final status = data?['status'] ?? 'ok';
                              final msg = rejected > 0
                                  ? 'Picked $applied/$qty x $partNo ($status). Rejected: $rejected'
                                  : 'Picked $applied x $partNo ($status)';
                              _showSuccess(msg);
                              _fetchData();
                            } else {
                              _showError(res['message'] ?? 'Pick failed');
                            }
                          },
                  ),
                );
              }),
            ],
          ),
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

  // ---- GROUPING ----
  Map<int?, List<PickingItem>> _getGroupedItems() {
    final Map<int?, List<PickingItem>> grouped = {};
    for (var item in _items) {
      final key = item.deliveryOrderId ?? 0;
      grouped.putIfAbsent(key, () => []).add(item);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _getGroupedItems();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Picking FG GCI', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(onPressed: _fetchData, icon: const Icon(Icons.refresh)),
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: Column(
        children: [
          // Date header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.indigo.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Hello, $_userName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Text(DateFormat('EEEE, d MMM yyyy').format(_selectedDate), style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime(2023),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) {
                      setState(() => _selectedDate = picked);
                      _fetchData();
                    }
                  },
                  icon: const Icon(Icons.calendar_month, size: 18),
                  label: const Text('Date'),
                ),
              ],
            ),
          ),

          // Stats row
          if (_items.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.white,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _statChip('SO', grouped.length.toString(), Colors.indigo),
                  _statChip('Parts', _items.length.toString(), Colors.grey.shade700),
                  _statChip('Pending', _items.where((i) => i.status == 'pending').length.toString(), Colors.grey),
                  _statChip('Picking', _items.where((i) => i.status == 'picking').length.toString(), Colors.orange),
                  _statChip('Done', _items.where((i) => i.status == 'completed').length.toString(), Colors.green),
                ],
              ),
            ),

          // List
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
                            Text('No picking plan for this date', style: TextStyle(color: Colors.grey.shade500)),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _fetchData,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: grouped.keys.length,
                          itemBuilder: (context, index) {
                            final soId = grouped.keys.elementAt(index);
                            final items = grouped[soId]!;
                            return _buildSoCard(items);
                          },
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

  Widget _statChip(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color)),
        Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey.shade500)),
      ],
    );
  }

  Widget _buildSoCard(List<PickingItem> items) {
    final first = items.first;
    final soNo = first.doNo ?? (first.source == 'po' ? first.poNo : 'Daily Plan');
    final tripNo = first.tripNo;
    final totalQty = items.fold(0, (sum, item) => sum + item.qtyPlan);
    final totalPicked = items.fold(0, (sum, item) => sum + item.qtyPicked);
    final progress = totalQty > 0 ? totalPicked / totalQty : 0.0;
    final isCompleted = items.every((item) => item.status == 'completed');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 1,
      child: ExpansionTile(
        initiallyExpanded: !isCompleted,
        backgroundColor: Colors.indigo.withAlpha(5),
        title: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          soNo ?? 'Unknown',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (tripNo != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(4)),
                          child: Text('T$tripNo', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.orange.shade900)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${items.length} parts | $totalPicked / $totalQty picked',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (isCompleted)
              const Icon(Icons.check_circle, color: Colors.green, size: 28)
            else
              SizedBox(
                width: 36,
                height: 36,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 3,
                      backgroundColor: Colors.grey.shade200,
                      color: Colors.indigo,
                    ),
                    Text('${(progress * 100).round()}', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
          ],
        ),
        children: items.map((item) {
          final statusColor = item.status == 'completed'
              ? Colors.green
              : item.status == 'picking'
                  ? Colors.orange
                  : Colors.grey;

          return Column(
            children: [
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                title: Text(item.partNo, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo, fontSize: 13)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.partName, style: const TextStyle(fontSize: 11)),
                    Row(
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 3),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(color: statusColor.withAlpha(30), borderRadius: BorderRadius.circular(4)),
                          child: Text(item.status.toUpperCase(), style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: statusColor)),
                        ),
                      ],
                    ),
                  ],
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${item.qtyPicked} / ${item.qtyPlan}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    if (item.qtyRemaining > 0)
                      Text('${item.qtyRemaining} left', style: TextStyle(fontSize: 10, color: Colors.orange.shade700, fontWeight: FontWeight.bold)),
                  ],
                ),
                onTap: item.status == 'completed' ? null : () => _showPickDialog(
                  partNo: item.partNo,
                  partName: item.partName,
                  doNo: item.doNo,
                  deliveryOrderId: item.deliveryOrderId,
                  qtyPlan: item.qtyPlan,
                  qtyPicked: item.qtyPicked,
                  qtyRemaining: item.qtyRemaining,
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

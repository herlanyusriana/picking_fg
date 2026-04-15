import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'login_screen.dart';
import 'do_detail_screen.dart';

class DoListScreen extends StatefulWidget {
  const DoListScreen({super.key});

  @override
  State<DoListScreen> createState() => _DoListScreenState();
}

class _DoListScreenState extends State<DoListScreen> {
  DateTime _selectedDate = DateTime.now();
  List<Map<String, dynamic>> _orders = [];
  bool _loading = false;
  String _userName = '';
  final _api = ApiService();

  @override
  void initState() {
    super.initState();
    _loadUser();
    _fetchOrders();
  }

  void _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _userName = prefs.getString('user_name') ?? 'User');
  }

  String get _dateStr => DateFormat('yyyy-MM-dd').format(_selectedDate);

  Future<void> _fetchOrders() async {
    setState(() => _loading = true);
    try {
      final res = await _api.getDeliveryOrders(_dateStr);
      if (res['auth_expired'] == true) {
        _handleAuthExpired();
        return;
      }
      if (res['success'] == true) {
        setState(() {
          _orders = (res['data'] as List).cast<Map<String, dynamic>>();
        });
      } else {
        _showError(res['message'] ?? 'Failed to load orders');
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
        const SnackBar(
          content: Text('Session expired. Please login again.'),
          backgroundColor: Colors.orange,
        ),
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

  void _openDo(Map<String, dynamic> order) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DoDetailScreen(
          deliveryOrderId: order['id'],
          doNo: order['do_no'] ?? 'N/A',
          date: _dateStr,
        ),
      ),
    );
    _fetchOrders();
  }

  @override
  Widget build(BuildContext context) {
    final totalPlan = _orders.fold<int>(0, (sum, o) => sum + ((o['qty_plan'] ?? 0) as int));
    final totalPicked = _orders.fold<int>(0, (sum, o) => sum + ((o['qty_picked'] ?? 0) as int));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Picking FG', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(onPressed: _fetchOrders, icon: const Icon(Icons.refresh)),
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: Column(
        children: [
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
                    Text(
                      DateFormat('EEEE, d MMM yyyy').format(_selectedDate),
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
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
                      _fetchOrders();
                    }
                  },
                  icon: const Icon(Icons.calendar_month, size: 18),
                  label: const Text('Date'),
                ),
              ],
            ),
          ),
          if (_orders.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Colors.white,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _statChip('DO', _orders.length.toString(), Colors.indigo),
                  _statChip('Plan', totalPlan.toString(), Colors.grey.shade700),
                  _statChip('Picked', totalPicked.toString(), Colors.green),
                  _statChip(
                    'Progress',
                    totalPlan > 0 ? '${(totalPicked / totalPlan * 100).round()}%' : '0%',
                    Colors.orange,
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _orders.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.local_shipping_outlined, size: 64, color: Colors.grey.shade300),
                            const SizedBox(height: 12),
                            Text(
                              'No delivery orders for this date',
                              style: TextStyle(color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _fetchOrders,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _orders.length,
                          itemBuilder: (context, index) => _buildDoCard(_orders[index]),
                        ),
                      ),
          ),
        ],
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

  Widget _buildDoCard(Map<String, dynamic> order) {
    final doNo = order['do_no'] ?? 'N/A';
    final tripNo = order['trip_no'];
    final customer = order['customer'] as Map<String, dynamic>? ?? {};
    final customerName = customer['name'] ?? '-';
    final customerCode = customer['code'] ?? '';
    final itemsCount = order['items_count'] ?? 0;
    final qtyPlan = (order['qty_plan'] ?? 0) as int;
    final qtyPicked = (order['qty_picked'] ?? 0) as int;
    final progress = ((order['progress'] ?? 0) as num).toDouble();
    final allCompleted = order['all_completed'] == true;
    final deliveryNote = order['delivery_note'] as Map<String, dynamic>?;
    final hasDeliveryNote = order['has_delivery_note'] == true || deliveryNote != null;
    final dnNo = deliveryNote?['dn_no']?.toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: allCompleted ? 0 : 2,
      color: allCompleted ? Colors.green.shade50 : Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openDo(order),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: allCompleted
                    ? const Icon(Icons.check_circle, color: Colors.green, size: 40)
                    : Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            value: progress / 100,
                            strokeWidth: 4,
                            backgroundColor: Colors.grey.shade200,
                            color: Colors.indigo,
                          ),
                          Text(
                            '${progress.round()}%',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            doNo,
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (tripNo != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'T$tripNo',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade900,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$customerName${customerCode.isNotEmpty ? ' ($customerCode)' : ''}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$itemsCount parts  •  $qtyPicked / $qtyPlan picked',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (hasDeliveryNote) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade100),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.receipt_long, size: 16, color: Colors.blue.shade700),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                dnNo != null && dnNo.isNotEmpty
                                    ? 'Delivery Note sudah dibuat: $dnNo'
                                    : 'Delivery Note sudah dibuat di web',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.blue.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}

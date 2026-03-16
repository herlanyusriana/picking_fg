import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

class ApiService {
  Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final response = await http
          .post(
            Uri.parse('${AppConfig.baseUrl}/auth/login'),
            body: {'login': username, 'password': password},
          )
          .timeout(AppConfig.requestTimeout);
      return json.decode(response.body);
    } on SocketException {
      return {'success': false, 'message': 'No internet connection'};
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  Future<Map<String, String>> _authHeaders() async {
    final token = await getToken();
    return {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
  }

  Future<Map<String, dynamic>> _handleResponse(http.Response response) async {
    if (response.statusCode == 401) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('token');
      return {'success': false, 'message': 'Session expired. Please login again.', 'auth_expired': true};
    }
    return json.decode(response.body);
  }

  // ─── Legacy flat list ───────────────────────────────────────────

  Future<Map<String, dynamic>> getPickingList(String date) async {
    try {
      final headers = await _authHeaders();
      final response = await http
          .get(
            Uri.parse('${AppConfig.baseUrl}/picking-fg?date=$date'),
            headers: headers,
          )
          .timeout(AppConfig.requestTimeout);
      return _handleResponse(response);
    } on SocketException {
      return {'success': false, 'message': 'No internet connection'};
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  Future<Map<String, dynamic>> lookupPart(String partNo, String date) async {
    try {
      final headers = await _authHeaders();
      final encodedPartNo = Uri.encodeQueryComponent(partNo);
      final response = await http
          .get(
            Uri.parse('${AppConfig.baseUrl}/picking-fg/lookup?part_no=$encodedPartNo&date=$date'),
            headers: headers,
          )
          .timeout(AppConfig.requestTimeout);
      return _handleResponse(response);
    } on SocketException {
      return {'success': false, 'message': 'No internet connection'};
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // ─── DO-based picking flow ──────────────────────────────────────

  /// List Delivery Orders with picking tasks for a date.
  Future<Map<String, dynamic>> getDeliveryOrders(String date) async {
    try {
      final headers = await _authHeaders();
      final response = await http
          .get(
            Uri.parse('${AppConfig.baseUrl}/picking-fg/delivery-orders?date=$date'),
            headers: headers,
          )
          .timeout(AppConfig.requestTimeout);
      return _handleResponse(response);
    } on SocketException {
      return {'success': false, 'message': 'No internet connection'};
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  /// Get DO detail with parts to pick.
  Future<Map<String, dynamic>> getDeliveryOrderDetail(int doId, String date) async {
    try {
      final headers = await _authHeaders();
      final response = await http
          .get(
            Uri.parse('${AppConfig.baseUrl}/picking-fg/delivery-orders/$doId?date=$date'),
            headers: headers,
          )
          .timeout(AppConfig.requestTimeout);
      return _handleResponse(response);
    } on SocketException {
      return {'success': false, 'message': 'No internet connection'};
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  /// Scan location — validate and get parts with stock at this location for a DO.
  Future<Map<String, dynamic>> scanLocation({
    required int deliveryOrderId,
    required String date,
    required String locationCode,
  }) async {
    try {
      final headers = await _authHeaders();
      final response = await http
          .post(
            Uri.parse('${AppConfig.baseUrl}/picking-fg/scan-location'),
            headers: headers,
            body: json.encode({
              'delivery_order_id': deliveryOrderId,
              'date': date,
              'location_code': locationCode,
            }),
          )
          .timeout(AppConfig.requestTimeout);
      return _handleResponse(response);
    } on SocketException {
      return {'success': false, 'message': 'No internet connection'};
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  /// Scan part — validate part against DO and location.
  Future<Map<String, dynamic>> scanPart({
    required int deliveryOrderId,
    required String date,
    required String locationCode,
    required String partCode,
  }) async {
    try {
      final headers = await _authHeaders();
      final response = await http
          .post(
            Uri.parse('${AppConfig.baseUrl}/picking-fg/scan-part'),
            headers: headers,
            body: json.encode({
              'delivery_order_id': deliveryOrderId,
              'date': date,
              'location_code': locationCode,
              'part_code': partCode,
            }),
          )
          .timeout(AppConfig.requestTimeout);
      return _handleResponse(response);
    } on SocketException {
      return {'success': false, 'message': 'No internet connection'};
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  /// Submit pick with DO + location (required).
  Future<Map<String, dynamic>> updatePick({
    required String date,
    required String partNo,
    required int qty,
    required String location,
    required int deliveryOrderId,
    String? batchNo,
  }) async {
    try {
      final headers = await _authHeaders();
      final body = <String, dynamic>{
        'date': date,
        'part_no': partNo,
        'qty': qty,
        'location': location,
        'delivery_order_id': deliveryOrderId,
      };
      if (batchNo != null && batchNo.isNotEmpty) {
        body['batch_no'] = batchNo;
      }
      final response = await http
          .post(
            Uri.parse('${AppConfig.baseUrl}/picking-fg/pick'),
            headers: headers,
            body: json.encode(body),
          )
          .timeout(AppConfig.requestTimeout);
      return _handleResponse(response);
    } on SocketException {
      return {'success': false, 'message': 'No internet connection'};
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }
}
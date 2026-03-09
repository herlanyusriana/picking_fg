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
            body: {'username': username, 'password': password},
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
      // Token expired
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('token');
      return {'success': false, 'message': 'Session expired. Please login again.', 'auth_expired': true};
    }
    return json.decode(response.body);
  }

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

  Future<Map<String, dynamic>> updatePick({
    required String date,
    required String partNo,
    required int qty,
    String? location,
    int? deliveryOrderId,
  }) async {
    try {
      final headers = await _authHeaders();
      final body = {
        'date': date,
        'part_no': partNo,
        'qty': qty,
        ...?location != null ? {'location': location} : null,
        ...?deliveryOrderId != null ? {'delivery_order_id': deliveryOrderId} : null,
      };
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

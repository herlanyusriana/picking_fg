import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // Use the IP of the machine running the Laravel server (usually 10.0.2.2 for Android emulator)
  static const String baseUrl = 'https://incoming.nooneasku.online/api'; 

  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      body: {'username': username, 'password': password},
    );
    return json.decode(response.body);
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  Future<Map<String, dynamic>> getPickingList(String date) async {
    final token = await getToken();
    final response = await http.get(
      Uri.parse('$baseUrl/picking-fg?date=$date'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );
    return json.decode(response.body);
  }

  Future<Map<String, dynamic>> updatePick({
    required String date,
    required String partNo,
    required int qty,
    String? location,
  }) async {
    final token = await getToken();
    final response = await http.post(
      Uri.parse('$baseUrl/picking-fg/pick'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'date': date,
        'part_no': partNo,
        'qty': qty,
        'location': location,
      }),
    );
    return json.decode(response.body);
  }
}

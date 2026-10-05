import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;

class OtpService {
  // Apna custom Supabase Edge function ya backend API ka URL yahan dale
  static const String _url = 'https://swinging-quick-auth-go.base44.app/functions/supabasePhoneOtp';

  Future<String> sendOtp(String phone) async {
    return _makeRequest({'action': 'send', 'phone': phone});
  }

  Future<String> verifyOtp(String phone, String token) async {
    return _makeRequest({'action': 'verify', 'phone': phone, 'token': token});
  }

  Future<String> _makeRequest(Map<String, dynamic> body) async {
    try {
      final response = await http
          .post(
            Uri.parse(_url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));

      Map<String, dynamic> data = {};
      try {
        if (response.body.isNotEmpty) {
          data = jsonDecode(response.body);
        } else {
          throw const FormatException('Empty response body');
        }
      } catch (_) {
        throw Exception('Invalid response format from server.');
      }

      if (response.statusCode == 200) {
        if (data['success'] == true) {
          return data['phone'] ?? body['phone'];
        } else {
          throw Exception(data['error'] ?? 'Unknown error occurred.');
        }
      } else {
        throw Exception(data['error'] ?? 'Server error: ');
      }
    } on SocketException {
      throw Exception('Network error. Please check your internet connection.');
    } on TimeoutException {
      throw Exception('Request timed out. Please try again later.');
    } catch (e) {
      if (e is Exception) {
        final msg = e.toString();
        if (msg.startsWith('Exception: ')) {
          throw Exception(msg.replaceFirst('Exception: ', ''));
        }
      }
      throw Exception(e.toString());
    }
  }
}

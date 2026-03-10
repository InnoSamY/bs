import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VideoApi {
  final Dio _dio = Dio();
  final String _baseUrl = 'http://123.56.168.149:3000/api';

  static final VideoApi _instance = VideoApi._internal();
  VideoApi._internal();
  factory VideoApi() => _instance;

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('user');
    if (userJson == null) return null;
    
    final userMap = jsonDecode(userJson);
    return userMap['token'];
  }

  Future<Map<String, dynamic>> _postWithAuth(String path, Map<String, dynamic> data) async {
    try {
      final token = await _getToken();
      if (token == null) {
        return {'success': false, 'code': -1, 'message': '未登录'};
      }

      final response = await _dio.post(
        '$_baseUrl$path',
        data: data,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      print('$path response: ${response.data}');
      return response.data;
    } catch (e) {
      print('$path error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> invite(String userId, bool isOnlyAudio) async {
    return _postWithAuth('/video/invite', {'userId': userId, 'isOnlyAudio': isOnlyAudio});
  }

  Future<Map<String, dynamic>> accept(String userId) async {
    return _postWithAuth('/video/accept', {'userId': userId});
  }

  Future<Map<String, dynamic>> offer(String userId, Map<String, dynamic> desc) async {
    return _postWithAuth('/video/offer', {'userId': userId, 'desc': desc});
  }

  Future<Map<String, dynamic>> answer(String userId, Map<String, dynamic> desc) async {
    return _postWithAuth('/video/answer', {'userId': userId, 'desc': desc});
  }

  Future<Map<String, dynamic>> candidate(String userId, Map<String, dynamic> candidate) async {
    return _postWithAuth('/video/candidate', {'userId': userId, 'candidate': candidate});
  }

  Future<Map<String, dynamic>> hangup(String userId) async {
    return _postWithAuth('/video/hangup', {'userId': userId});
  }
}

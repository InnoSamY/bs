import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_base/models/user.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  final Dio _dio = Dio();
  // 云服务器API地址
  final String _baseUrl = 'http://123.56.168.149:3000/api';
  
  // 注册用户
  Future<User> register({
    required String username,
    required String password,
    required String avatar,
    required String bio,
    required String publicKey,
  }) async {
    try {
      final response = await _dio.post(
        '$_baseUrl/auth/register',
        data: {
          'username': username,
          'password': password,
          'avatar': avatar,
          'bio': bio,
          'publicKey': publicKey,
        },
      );
      
      if (response.data['success'] == true) {
        User user = User.fromJson(response.data['data']);
        await _saveUser(user);
        return user;
      } else {
        throw Exception(response.data['message'] ?? '注册失败');
      }
    } catch (error) {
      throw Exception('注册失败: $error');
    }
  }
  
  // 登录用户
  Future<User> login({
    required String userId,
    required String password,
  }) async {
    try {
      final response = await _dio.post(
        '$_baseUrl/auth/login',
        data: {
          'userId': userId,
          'password': password,
        },
      );
      
      if (response.data['success'] == true) {
        User user = User.fromJson(response.data['data']);
        await _saveUser(user);
        return user;
      } else {
        throw Exception(response.data['message'] ?? '登录失败');
      }
    } catch (error) {
      throw Exception('登录失败: $error');
    }
  }
  
  // 退出登录
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user');
  }
  
  // 获取当前用户
  Future<User?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('user');
    if (userJson == null) return null;
    
    final userMap = jsonDecode(userJson);
    return User.fromJson(userMap);
  }
  
  // 保存用户信息到本地
  Future<void> _saveUser(User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user', jsonEncode(user.toJson()));
  }
}

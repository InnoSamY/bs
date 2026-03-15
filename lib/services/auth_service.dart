import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_base/models/user.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 认证服务类
/// 
/// 提供用户注册、登录、登出等功能。
/// 
/// 主要功能：
/// 1. 用户注册（register）
/// 2. 用户登录（login）
/// 3. 用户登出（logout）
/// 4. 获取当前用户信息（getCurrentUser）
/// 5. 本地存储用户信息（_saveUser）
class AuthService {
  final Dio _dio = Dio();
  // 云服务器API地址
  final String _baseUrl = 'http://123.56.168.149:3000/api';
  
  /// 注册新用户
  /// 
  /// 向服务器发送注册请求，创建新用户账户。
  /// 
  /// 参数：
  /// - username: 用户名
  /// - password: 密码
  /// - avatar: 头像路径
  /// - bio: 个性签名
  /// - publicKey: 公钥（用于后量子加密）
  /// 
  /// 返回：
  /// - User: 创建的用户对象
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
  
  /// 用户登录
  /// 
  /// 向服务器发送登录请求，验证用户身份。
  /// 
  /// 参数：
  /// - userId: 用户ID
  /// - password: 密码
  /// 
  /// 返回：
  /// - User: 登录成功的用户对象
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
  
  /// 用户登出
  /// 
  /// 清除本地存储的用户信息。
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user');
  }
  
  /// 获取当前登录用户
  /// 
  /// 从本地存储中读取用户信息。
  /// 
  /// 返回：
  /// - User?: 当前用户对象，如果未登录则返回 null
  Future<User?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('user');
    if (userJson == null) return null;
    
    final userMap = jsonDecode(userJson);
    return User.fromJson(userMap);
  }
  
  /// 更新用户资料
  /// 
  /// 向服务器发送更新请求，修改用户的头像和个性签名。
  /// 
  /// 参数：
  /// - avatar: 头像（Base64编码）
  /// - bio: 个性签名
  /// 
  /// 返回：
  /// - User: 更新后的用户对象
  Future<User> updateProfile({
    required String avatar,
    required String bio,
  }) async {
    try {
      final currentUser = await getCurrentUser();
      if (currentUser == null) {
        throw Exception('用户未登录');
      }

      final response = await _dio.put(
        '$_baseUrl/auth/profile',
        data: {
          'avatar': avatar,
          'bio': bio,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer ${currentUser.token}',
          },
        ),
      );

      if (response.data['success'] == true) {
        final updatedUser = User.fromJson(response.data['data']);
        final mergedUser = User(
          id: updatedUser.id,
          username: updatedUser.username,
          password: currentUser.password,
          avatar: updatedUser.avatar,
          bio: updatedUser.bio,
          publicKey: updatedUser.publicKey,
          token: currentUser.token,
        );
        await _saveUser(mergedUser);
        return mergedUser;
      } else {
        throw Exception(response.data['message'] ?? '更新失败');
      }
    } catch (error) {
      throw Exception('更新失败: $error');
    }
  }

  /// 保存用户信息到本地
  /// 
  /// 使用 SharedPreferences 将用户信息持久化存储。
  /// 
  /// 参数：
  /// - user: 用户对象
  Future<void> _saveUser(User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user', jsonEncode(user.toJson()));
  }
}

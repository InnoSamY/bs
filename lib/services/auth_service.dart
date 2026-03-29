import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_base/models/user.dart';
import 'package:flutter_base/services/pqc_kem_service.dart';
import 'package:flutter_base/services/pqc_signature_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 认证服务类
/// 
/// 提供用户注册、登录、密钥管理等功能。
/// 
/// 主要功能：
/// 1. 用户注册（register）- 自动生成后量子密钥对
/// 2. 用户登录（login）
/// 3. 密钥管理（生成、存储、获取）
/// 4. 本地存储用户信息
/// 
/// 安全特性：
/// - 注册时自动生成两套密钥对（ML-KEM + 签名）
/// - 私钥只在本地存储，不上传服务器
/// - 公钥上传到服务器用于加密通信
class AuthService {
  final Dio _dio = Dio();
  final String _baseUrl = 'http://123.56.168.149:3000/api';
  
  final _kemService = PqcKemService();
  final _sigService = PqcSignatureService();
  
  /// 注册新用户
  /// 
  /// 流程：
  /// 1. 生成 ML-KEM 密钥对
  /// 2. 生成签名密钥对
  /// 3. 上传公钥到服务器
  /// 4. 本地保存私钥
  /// 
  /// 参数：
  /// - username: 用户名
  /// - password: 密码
  /// - avatar: 头像路径
  /// - bio: 个性签名
  Future<User> register({
    required String username,
    required String password,
    required String avatar,
    required String bio,
  }) async {
    try {
      // 生成后量子密钥对
      print('正在生成后量子密钥对...');
      
      // 1. 生成 ML-KEM 密钥对
      final kemKeyPair = _kemService.generateKeyPair();
      
      // 2. 生成签名密钥对
      final sigKeyPair = _sigService.generateKeyPair();
      
      print('密钥对生成成功');
      
      // 3. 注册到服务器（只上传公钥）
      final response = await _dio.post(
        '$_baseUrl/auth/register',
        data: {
          'username': username,
          'password': password,
          'avatar': avatar,
          'bio': bio,
          'kemPublicKey': kemKeyPair['publicKey'],
          'sigPublicKey': sigKeyPair['publicKey'],
        },
      );
      
      if (response.data['success'] == true) {
        User user = User.fromJson(response.data['data']);
        
        // 4. 本地保存私钥
        await _saveUserKeys(UserKeys(
          userId: user.id,
          kemPublicKey: kemKeyPair['publicKey']!,
          kemSecretKey: kemKeyPair['privateKey']!,
          sigPublicKey: sigKeyPair['publicKey']!,
          sigSecretKey: sigKeyPair['privateKey']!,
        ));
        
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
        
        // 检查本地是否已有密钥
        final existingKeys = await getCurrentUserKeys();
        if (existingKeys == null) {
          throw Exception('本机缺少该账号私钥，请使用原设备登录或重新注册');
        } else {
          print('✓ 使用本地已有密钥');
        }
        
        return user;
      } else {
        throw Exception(response.data['message'] ?? '登录失败');
      }
    } catch (error) {
      throw Exception('登录失败: $error');
    }
  }
  
  /// 用户登出
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user');
    // 保留私钥，不删除 user_keys
  }
  
  /// 获取当前登录用户
  Future<User?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('user');
    if (userJson == null) return null;
    
    try {
      final userMap = jsonDecode(userJson);
      return User.fromJson(userMap);
    } catch (e) {
      print('用户数据解析失败，清除损坏的缓存: $e');
      await prefs.remove('user');
      return null;
    }
  }
  
  /// 获取当前用户的密钥
  Future<UserKeys?> getCurrentUserKeys() async {
    final currentUser = await getCurrentUser();
    if (currentUser == null) return null;
    
    final prefs = await SharedPreferences.getInstance();
    final key = 'user_keys_${currentUser.id}';
    final keysJson = prefs.getString(key);
    if (keysJson == null) return null;
    
    try {
      final keysMap = jsonDecode(keysJson);
      return UserKeys.fromJson(keysMap);
    } catch (e) {
      print('密钥数据解析失败，清除损坏的缓存: $e');
      await prefs.remove(key);
      return null;
    }
  }
  
  /// 更新用户资料
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
        final mergedUser = currentUser.copyWith(
          avatar: updatedUser.avatar,
          bio: updatedUser.bio,
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
  Future<void> _saveUser(User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user', jsonEncode(user.toJson()));
  }
  
  /// 保存用户密钥到本地
  Future<void> _saveUserKeys(UserKeys keys) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'user_keys_${keys.userId}';
    await prefs.setString(key, jsonEncode(keys.toJson()));
  }
}

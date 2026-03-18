import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_base/screens/contacts_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 联系人服务类
/// 
/// 提供联系人管理功能。
/// 
/// 主要功能：
/// 1. 获取联系人列表（getContacts）
/// 2. 获取联系人请求列表（getContactRequests）
/// 3. 添加联系人（addContact）
/// 4. 删除联系人（deleteContact）
/// 5. 接受联系人请求（acceptContactRequest）
/// 6. 拒绝联系人请求（rejectContactRequest）
class ContactService {
  final Dio _dio = Dio();
  // 云服务器API地址
  final String _baseUrl = 'http://123.56.168.149:3000/api';
  
  /// 获取当前用户的 JWT token
  /// 
  /// 用于 API 认证。
  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('user');
    if (userJson == null) return null;
    
    final userMap = jsonDecode(userJson);
    return userMap['token'];
  }
  
  /// 获取联系人列表
  /// 
  /// 从服务器获取当前用户的所有联系人。
  /// 
  /// 返回：
  /// - List<Contact>: 联系人列表
  Future<List<Contact>> getContacts() async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('未登录');
      }
      
      final response = await _dio.get(
        '$_baseUrl/contacts',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      
      if (response.data['success'] == true) {
        List<Contact> contacts = [];
        for (var item in response.data['data']) {
          contacts.add(Contact.fromJson(item));
        }
        return contacts;
      } else {
        throw Exception(response.data['message'] ?? '获取联系人列表失败');
      }
    } catch (error) {
      if (error is DioException) {
        if (error.response?.data != null) {
          throw Exception(error.response!.data['message'] ?? '获取联系人列表失败');
        }
      }
      throw Exception('获取联系人列表失败: $error');
    }
  }
  
  /// 获取联系人请求列表
  /// 
  /// 获取收到的和发送的联系人请求。
  /// 
  /// 返回：
  /// - Map<String, List<dynamic>>: 包含 received（收到的）和 sent（发送的）两个列表
  Future<Map<String, List<dynamic>>> getContactRequests() async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('未登录');
      }
      
      final response = await _dio.get(
        '$_baseUrl/contacts/requests',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      
      if (response.data['success'] == true) {
        return {
          'received': List<dynamic>.from(response.data['data']['received'] ?? []),
          'sent': List<dynamic>.from(response.data['data']['sent'] ?? []),
        };
      } else {
        throw Exception(response.data['message'] ?? '获取联系人请求失败');
      }
    } catch (error) {
      if (error is DioException) {
        if (error.response?.data != null) {
          throw Exception(error.response!.data['message'] ?? '获取联系人请求失败');
        }
      }
      throw Exception('获取联系人请求失败: $error');
    }
  }
  
  /// 添加联系人
  /// 
  /// 发送添加联系人请求。
  /// 
  /// 参数：
  /// - contactId: 对方用户ID
  /// - verificationMessage: 验证消息
  Future<void> addContact({
    required String contactId,
    required String verificationMessage,
  }) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('未登录');
      }
      
      final response = await _dio.post(
        '$_baseUrl/contacts/add',
        data: {
          'contactId': contactId,
          'verificationMessage': verificationMessage,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      
      if (response.data['success'] != true) {
        throw Exception(response.data['message'] ?? '添加联系人失败');
      }
    } catch (error) {
      if (error is DioException) {
        if (error.response?.data != null) {
          throw Exception(error.response!.data['message'] ?? '添加联系人失败');
        }
      }
      throw Exception('添加联系人失败: $error');
    }
  }
  
  /// 删除联系人
  /// 
  /// 从联系人列表中删除指定用户。
  /// 
  /// 参数：
  /// - contactId: 对方用户ID
  Future<void> deleteContact({
    required String contactId,
  }) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('未登录');
      }
      
      final response = await _dio.delete(
        '$_baseUrl/contacts/$contactId',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      
      if (response.data['success'] != true) {
        throw Exception(response.data['message'] ?? '删除联系人失败');
      }
    } catch (error) {
      if (error is DioException) {
        if (error.response?.data != null) {
          throw Exception(error.response!.data['message'] ?? '删除联系人失败');
        }
      }
      throw Exception('删除联系人失败: $error');
    }
  }
  
  /// 接受联系人请求
  /// 
  /// 同意对方的联系人请求。
  /// 
  /// 参数：
  /// - requestId: 请求ID
  Future<void> acceptContactRequest({
    required String requestId,
  }) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('未登录');
      }
      
      final response = await _dio.post(
        '$_baseUrl/contacts/accept',
        data: {
          'requestId': requestId,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      
      if (response.data['success'] != true) {
        throw Exception(response.data['message'] ?? '接受联系人请求失败');
      }
    } catch (error) {
      if (error is DioException) {
        if (error.response?.data != null) {
          throw Exception(error.response!.data['message'] ?? '接受联系人请求失败');
        }
      }
      throw Exception('接受联系人请求失败: $error');
    }
  }
  
  /// 拒绝联系人请求
  /// 
  /// 拒绝对方的联系人请求。
  /// 
  /// 参数：
  /// - requestId: 请求ID
  Future<void> rejectContactRequest({
    required String requestId,
  }) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('未登录');
      }
      
      final response = await _dio.post(
        '$_baseUrl/contacts/reject',
        data: {
          'requestId': requestId,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      
      if (response.data['success'] != true) {
        throw Exception(response.data['message'] ?? '拒绝联系人请求失败');
      }
    } catch (error) {
      if (error is DioException) {
        if (error.response?.data != null) {
          throw Exception(error.response!.data['message'] ?? '拒绝联系人请求失败');
        }
      }
      throw Exception('拒绝联系人请求失败: $error');
    }
  }
  
  /// 获取联系人详情
  /// 
  /// 获取指定联系人的详细信息，包括公钥。
  /// 
  /// 参数：
  /// - contactId: 联系人ID
  /// 
  /// 返回：
  /// - Contact 对象，包含公钥信息
  Future<Contact?> getContactDetail(String contactId) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('未登录');
      }
      
      final response = await _dio.get(
        '$_baseUrl/contacts/$contactId',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      
      if (response.data['success'] == true) {
        return Contact.fromJson(response.data['data']);
      } else {
        return null;
      }
    } catch (error) {
      print('获取联系人详情失败: $error');
      return null;
    }
  }
}

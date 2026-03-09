import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_base/models/user.dart';
import 'package:flutter_base/screens/contacts_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ContactService {
  final Dio _dio = Dio();
  // 云服务器API地址
  final String _baseUrl = 'http://123.56.168.149:3000/api';
  
  // 获取JWT token
  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('user');
    if (userJson == null) return null;
    
    final userMap = jsonDecode(userJson);
    return userMap['token'];
  }
  
  // 获取联系人列表
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
          contacts.add(Contact(
            id: item['id'] ?? '',
            username: item['username'] ?? '未知用户',
            avatar: item['avatar'] ?? '',
            bio: item['bio'] ?? '',
            isOnline: item['isOnline'] ?? false,
          ));
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
  
  // 获取联系人请求列表
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
  
  // 添加联系人
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
  
  // 删除联系人
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
  
  // 接受联系人请求
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
  
  // 拒绝联系人请求
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
}

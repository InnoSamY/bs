import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 视频通话 API 服务类
/// 
/// 提供与服务器通信的接口，用于信令交换和密钥传输。
/// 
/// 主要功能：
/// 1. 通话邀请（invite）
/// 2. 通话接受（accept）
/// 3. SDP 描述交换（offer/answer）
/// 4. ICE 候选者交换（candidate）
/// 5. 通话结束（hangup）
/// 6. 密钥交换（keyExchange）
/// 7. 安全邀请（secureInvite）
class VideoApi {
  final Dio _dio = Dio();
  final String _baseUrl = 'http://123.56.168.149:3000/api';

  static final VideoApi _instance = VideoApi._internal();
  VideoApi._internal();
  factory VideoApi() => _instance;

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

  /// 发送带认证的 POST 请求
  /// 
  /// 自动添加 JWT token 到请求头。
  /// 
  /// 参数：
  /// - path: API 路径
  /// - data: 请求数据
  /// 
  /// 返回：
  /// - API 响应数据
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

  /// 发起通话邀请
  /// 
  /// 向服务器发送通话邀请，服务器会通过 WebSocket 转发给对方。
  /// 
  /// 参数：
  /// - userId: 对方用户ID
  /// - isOnlyAudio: 是否仅音频通话
  Future<Map<String, dynamic>> invite(String userId, bool isOnlyAudio) async {
    return _postWithAuth('/video/invite', {'userId': userId, 'isOnlyAudio': isOnlyAudio});
  }

  /// 接听通话
  /// 
  /// 向服务器发送接听信号，开始通话流程。
  /// 
  /// 参数：
  /// - userId: 对方用户ID
  Future<Map<String, dynamic>> accept(String userId) async {
    return _postWithAuth('/video/accept', {'userId': userId});
  }

  /// 发送 SDP Offer
  /// 
  /// SDP（Session Description Protocol）用于协商通话参数。
  /// 主叫方发送 Offer 给被叫方。
  /// 
  /// 参数：
  /// - userId: 对方用户ID
  /// - desc: SDP 描述（包含媒体信息、编解码器等）
  Future<Map<String, dynamic>> offer(String userId, Map<String, dynamic> desc) async {
    return _postWithAuth('/video/offer', {'userId': userId, 'desc': desc});
  }

  /// 发送 SDP Answer
  /// 
  /// 被叫方回复 Answer 给主叫方，确认通话参数。
  /// 
  /// 参数：
  /// - userId: 对方用户ID
  /// - desc: SDP 描述
  Future<Map<String, dynamic>> answer(String userId, Map<String, dynamic> desc) async {
    return _postWithAuth('/video/answer', {'userId': userId, 'desc': desc});
  }

  /// 发送 ICE 候选者
  /// 
  /// ICE（Interactive Connectivity Establishment）用于 NAT 穿透。
  /// 双方交换候选者以建立直接连接。
  /// 
  /// 参数：
  /// - userId: 对方用户ID
  /// - candidate: ICE 候选者信息
  Future<Map<String, dynamic>> candidate(String userId, Map<String, dynamic> candidate) async {
    return _postWithAuth('/video/candidate', {'userId': userId, 'candidate': candidate});
  }

  /// 结束通话
  /// 
  /// 通知服务器通话已结束。
  /// 
  /// 参数：
  /// - userId: 对方用户ID
  Future<Map<String, dynamic>> hangup(String userId) async {
    return _postWithAuth('/video/hangup', {'userId': userId});
  }

  /// 发送密钥交换消息
  /// 
  /// 通过服务器转发密钥交换消息，用于建立加密会话。
  /// 
  /// 参数：
  /// - userId: 对方用户ID
  /// - data: 密钥交换数据（包含密文等）
  Future<Map<String, dynamic>> keyExchange(String userId, Map<String, dynamic> data) async {
    return _postWithAuth('/video/keyExchange', {'userId': userId, ...data});
  }

  /// 发送安全邀请
  /// 
  /// 带数字签名的邀请，防止伪造和篡改。
  /// 
  /// 参数：
  /// - userId: 对方用户ID
  /// - isOnlyAudio: 是否仅音频通话
  /// - signature: 数字签名
  /// - publicKey: 签名公钥
  Future<Map<String, dynamic>> secureInvite(
    String userId,
    bool isOnlyAudio,
    String signature,
    String publicKey,
  ) async {
    return _postWithAuth('/video/secure-invite', {
      'userId': userId,
      'isOnlyAudio': isOnlyAudio,
      'signature': signature,
      'publicKey': publicKey,
    });
  }
}

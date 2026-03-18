import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 音频通话 API 服务类
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
class AudioApi {
  final Dio _dio = Dio();
  final String _baseUrl = 'http://123.56.168.149:3000/api';

  static final AudioApi _instance = AudioApi._internal();
  AudioApi._internal();
  factory AudioApi() => _instance;

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
    return _postWithAuth('/audio/invite', {'userId': userId, 'isOnlyAudio': isOnlyAudio});
  }

  /// 接听通话
  /// 
  /// 向服务器发送接听信号，开始通话流程。
  /// 
  /// 参数：
  /// - userId: 对方用户ID
  Future<Map<String, dynamic>> accept(String userId) async {
    return _postWithAuth('/audio/accept', {'userId': userId});
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
    return _postWithAuth('/audio/offer', {'userId': userId, 'desc': desc});
  }

  /// 发送 SDP Answer
  /// 
  /// 被叫方回复 Answer 给主叫方，确认通话参数。
  /// 
  /// 参数：
  /// - userId: 对方用户ID
  /// - desc: SDP 描述
  Future<Map<String, dynamic>> answer(String userId, Map<String, dynamic> desc) async {
    return _postWithAuth('/audio/answer', {'userId': userId, 'desc': desc});
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
    return _postWithAuth('/audio/candidate', {'userId': userId, 'candidate': candidate});
  }

  /// 结束通话
  /// 
  /// 通知服务器通话已结束。
  /// 
  /// 参数：
  /// - userId: 对方用户ID
  Future<Map<String, dynamic>> hangup(String userId) async {
    return _postWithAuth('/audio/hangup', {'userId': userId});
  }

  /// 拒绝通话
  /// 
  /// 通知服务器通话被拒绝。
  /// 
  /// 参数：
  /// - userId: 对方用户ID
  Future<Map<String, dynamic>> reject(String userId) async {
    print('[AudioApi] 发送 reject 请求到服务器，目标: $userId');
    final result = await _postWithAuth('/audio/reject', {'userId': userId});
    print('[AudioApi] reject 请求结果: $result');
    return result;
  }

  /// 发送密钥交换消息
  /// 
  /// 通过服务器转发密钥交换消息，用于建立加密会话。
  /// 
  /// 参数：
  /// - userId: 对方用户ID
  /// - data: 密钥交换数据（包含密文等）
  Future<Map<String, dynamic>> keyExchange(String userId, Map<String, dynamic> data) async {
    return _postWithAuth('/audio/keyExchange', {'userId': userId, ...data});
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
    return _postWithAuth('/audio/secure-invite', {
      'userId': userId,
      'isOnlyAudio': isOnlyAudio,
      'signature': signature,
      'publicKey': publicKey,
    });
  }

  /// 发送安全邀请 V2（新版）
  /// 
  /// 包含完整的后量子安全信息：
  /// - ML-KEM 密文
  /// - 数字签名
  /// - WebRTC Offer
  /// 
  /// 参数：
  /// - userId: 对方用户ID
  /// - isOnlyAudio: 是否仅音频通话
  /// - kemCiphertext: ML-KEM 密文
  /// - signature: 数字签名
  /// - sigPublicKey: 签名公钥
  /// - offer: WebRTC Offer
  /// - timestamp: 时间戳
  Future<Map<String, dynamic>> secureInviteV2(
    String userId,
    bool isOnlyAudio,
    String kemCiphertext,
    String signature,
    String sigPublicKey,
    Map<String, dynamic> offer,
    String timestamp,
  ) async {
    return _postWithAuth('/audio/secure-invite-v2', {
      'userId': userId,
      'isOnlyAudio': isOnlyAudio,
      'kemCiphertext': kemCiphertext,
      'signature': signature,
      'sigPublicKey': sigPublicKey,
      'offer': offer,
      'timestamp': timestamp,
    });
  }

  /// 发送应答 V2（新版）
  /// 
  /// 包含完整的后量子安全信息：
  /// - WebRTC Answer
  /// - 数字签名
  /// 
  /// 参数：
  /// - userId: 对方用户ID
  /// - answer: WebRTC Answer
  /// - signature: 数字签名
  /// - sigPublicKey: 签名公钥
  /// - timestamp: 时间戳
  Future<Map<String, dynamic>> answerV2(
    String userId,
    Map<String, dynamic> answer,
    String signature,
    String sigPublicKey,
    String timestamp,
  ) async {
    return _postWithAuth('/audio/answer-v2', {
      'userId': userId,
      'answer': answer,
      'signature': signature,
      'sigPublicKey': sigPublicKey,
      'timestamp': timestamp,
    });
  }
}

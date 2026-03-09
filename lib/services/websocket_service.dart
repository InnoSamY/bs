import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

// 通话状态枚举
enum CallState {
  idle,           // 空闲
  calling,        // 正在呼叫
  ringing,        // 正在响铃（被叫方）
  connecting,     // 连接中
  connected,      // 已连接
  ended,          // 已结束
  rejected,       // 被拒绝
  error,          // 错误
}

// 通话事件回调
class CallEventCallbacks {
  final Function(Map<String, dynamic>)? onIncomingCall;
  final Function(dynamic)? onCallAccepted;
  final Function(String)? onCallRejected;
  final Function(RTCIceCandidate)? onIceCandidate;
  final Function()? onCallEnded;
  final Function(String)? onError;

  CallEventCallbacks({
    this.onIncomingCall,
    this.onCallAccepted,
    this.onCallRejected,
    this.onIceCandidate,
    this.onCallEnded,
    this.onError,
  });
}

class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  io.Socket? _socket;
  String? _currentUserId;
  CallEventCallbacks? _callbacks;

  // 服务器地址
  final String _serverUrl = 'http://123.56.168.149:3000';

  // 连接状态
  bool get isConnected => _socket?.connected ?? false;

  // 初始化连接
  Future<void> connect(String userId, {CallEventCallbacks? callbacks}) async {
    _currentUserId = userId;
    _callbacks = callbacks;

    if (_socket != null && _socket!.connected) {
      print('WebSocket 已连接');
      return;
    }

    try {
      _socket = io.io(_serverUrl, <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': true,
      });

      _socket!.onConnect((_) {
        print('WebSocket 连接成功');
        // 注册用户
        _socket!.emit('register', userId);
      });

      _socket!.onDisconnect((_) {
        print('WebSocket 断开连接');
      });

      _socket!.onConnectError((error) {
        print('WebSocket 连接错误: $error');
        _callbacks?.onError?.call('连接服务器失败');
      });

      // 监听来电
      _socket!.on('incoming-call', (data) {
        print('收到来电: $data');
        _callbacks?.onIncomingCall?.call(data);
      });

      // 监听对方接受通话
      _socket!.on('call-accepted', (data) {
        print('对方接受通话: $data');
        _callbacks?.onCallAccepted?.call(data);
      });

      // 监听对方拒绝通话
      _socket!.on('call-rejected', (data) {
        print('对方拒绝通话: $data');
        final reason = data['reason'] ?? '用户拒绝接听';
        _callbacks?.onCallRejected?.call(reason);
      });

      // 监听ICE候选者
      _socket!.on('ice-candidate', (data) {
        print('收到ICE候选者');
        final candidateData = data['candidate'];
        if (candidateData != null) {
          final candidate = RTCIceCandidate(
            candidateData['candidate'],
            candidateData['sdpMid'],
            candidateData['sdpMLineIndex'],
          );
          _callbacks?.onIceCandidate?.call(candidate);
        }
      });

      // 监听通话结束
      _socket!.on('call-ended', (_) {
        print('通话结束');
        _callbacks?.onCallEnded?.call();
      });

      // 监听错误
      _socket!.on('call-error', (data) {
        print('通话错误: $data');
        _callbacks?.onError?.call(data['message'] ?? '通话错误');
      });

    } catch (e) {
      print('WebSocket 初始化错误: $e');
      throw Exception('WebSocket 连接失败: $e');
    }
  }

  // 发起通话请求
  void sendCallRequest(String calleeId, RTCSessionDescription offer) {
    if (_socket == null || !_socket!.connected) {
      throw Exception('WebSocket 未连接');
    }

    _socket!.emit('call-request', {
      'callerId': _currentUserId,
      'calleeId': calleeId,
      'offer': {
        'sdp': offer.sdp,
        'type': offer.type,
      },
      'callType': 'audio',
    });
  }

  // 接受通话
  void sendCallAccept(String callerId, RTCSessionDescription answer) {
    if (_socket == null || !_socket!.connected) {
      throw Exception('WebSocket 未连接');
    }

    _socket!.emit('call-accept', {
      'callerId': callerId,
      'answer': {
        'sdp': answer.sdp,
        'type': answer.type,
      },
    });
  }

  // 拒绝通话
  void sendCallReject(String callerId) {
    if (_socket == null || !_socket!.connected) {
      throw Exception('WebSocket 未连接');
    }

    _socket!.emit('call-reject', {
      'callerId': callerId,
    });
  }

  // 结束通话
  void sendCallEnd(String targetId) {
    if (_socket == null || !_socket!.connected) {
      throw Exception('WebSocket 未连接');
    }

    _socket!.emit('call-end', {
      'targetId': targetId,
    });
  }

  // 发送ICE候选者
  void sendIceCandidate(String targetId, RTCIceCandidate candidate) {
    if (_socket == null || !_socket!.connected) {
      throw Exception('WebSocket 未连接');
    }

    _socket!.emit('ice-candidate', {
      'targetId': targetId,
      'candidate': {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      },
    });
  }

  // 断开连接
  void disconnect() {
    _socket?.disconnect();
    _socket = null;
    _currentUserId = null;
    _callbacks = null;
  }

  // 更新回调
  void updateCallbacks(CallEventCallbacks callbacks) {
    _callbacks = callbacks;
  }
}

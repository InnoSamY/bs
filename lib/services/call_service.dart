import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_base/services/websocket_service.dart';

class CallService {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  final _webSocketService = WebSocketService();

  // 通话状态
  final _callStateController = StreamController<CallState>.broadcast();
  Stream<CallState> get callStateStream => _callStateController.stream;

  // 当前通话状态
  CallState _currentState = CallState.idle;
  CallState get currentState => _currentState;

  // 当前通话的对方ID
  String? _currentPeerId;
  String? get currentPeerId => _currentPeerId;

  // 是否是呼叫方
  bool _isCaller = false;
  bool get isCaller => _isCaller;

  // 初始化本地媒体流
  Future<MediaStream> initializeLocalStream() async {
    // 请求麦克风权限
    final permissionStatus = await Permission.microphone.request();
    if (permissionStatus != PermissionStatus.granted) {
      throw Exception('麦克风权限被拒绝');
    }

    final constraints = {
      'audio': true,
      'video': false,
    };

    _localStream = await navigator.mediaDevices.getUserMedia(constraints);
    return _localStream!;
  }

  // 创建PeerConnection
  Future<RTCPeerConnection> _createPeerConnectionInternal() async {
    final config = {
      'iceServers': [
        {
          'urls': 'stun:stun.l.google.com:19302',
        },
        {
          'urls': 'stun:stun1.l.google.com:19302',
        },
      ],
    };

    _peerConnection = await createPeerConnection(config);

    // 添加本地流
    if (_localStream != null) {
      for (var track in _localStream!.getTracks()) {
        await _peerConnection!.addTrack(track, _localStream!);
      }
    }

    // 监听远程流
    _peerConnection!.onTrack = (RTCTrackEvent event) {
      print('收到远程流: ${event.track.kind}');
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
      }
    };

    // 监听ICE候选者
    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      print('生成ICE候选者');
      if (_currentPeerId != null) {
        _webSocketService.sendIceCandidate(_currentPeerId!, candidate);
      }
    };

    // 监听连接状态变化
    _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
      print('连接状态变化: $state');
      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _updateState(CallState.connected);
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
          _updateState(CallState.ended);
          break;
        default:
          break;
      }
    };

    return _peerConnection!;
  }

  // 发起呼叫
  Future<void> initiateCall(String calleeId) async {
    try {
      _isCaller = true;
      _currentPeerId = calleeId;
      _updateState(CallState.calling);

      // 初始化本地媒体流
      await initializeLocalStream();

      // 创建PeerConnection
      await _createPeerConnectionInternal();

      // 创建offer
      final offer = await _peerConnection!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
      });
      await _peerConnection!.setLocalDescription(offer);

      // 发送呼叫请求
      _webSocketService.sendCallRequest(calleeId, offer);

    } catch (e) {
      print('发起呼叫失败: $e');
      _updateState(CallState.error);
      throw Exception('发起呼叫失败: $e');
    }
  }

  // 处理来电（创建answer）
  Future<void> handleIncomingCall(String callerId, Map<String, dynamic> offerData) async {
    try {
      _isCaller = false;
      _currentPeerId = callerId;
      _updateState(CallState.ringing);

      // 初始化本地媒体流
      await initializeLocalStream();

      // 创建PeerConnection
      await _createPeerConnectionInternal();

      // 设置远程描述（offer）
      final offer = RTCSessionDescription(
        offerData['sdp'],
        offerData['type'],
      );
      await _peerConnection!.setRemoteDescription(offer);

    } catch (e) {
      print('处理来电失败: $e');
      _updateState(CallState.error);
      throw Exception('处理来电失败: $e');
    }
  }

  // 接受通话
  Future<void> acceptCall() async {
    try {
      if (_peerConnection == null || _currentPeerId == null) {
        throw Exception('没有待接听的通话');
      }

      _updateState(CallState.connecting);

      // 创建answer
      final answer = await _peerConnection!.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
      });
      await _peerConnection!.setLocalDescription(answer);

      // 发送接受响应
      _webSocketService.sendCallAccept(_currentPeerId!, answer);

    } catch (e) {
      print('接受通话失败: $e');
      _updateState(CallState.error);
      throw Exception('接受通话失败: $e');
    }
  }

  // 拒绝通话
  void rejectCall() {
    if (_currentPeerId != null) {
      _webSocketService.sendCallReject(_currentPeerId!);
    }
    _cleanup();
    _updateState(CallState.rejected);
  }

  // 处理对方接受通话
  Future<void> handleCallAccepted(Map<String, dynamic> answerData) async {
    try {
      if (_peerConnection == null) {
        throw Exception('PeerConnection 未初始化');
      }

      _updateState(CallState.connecting);

      // 设置远程描述（answer）
      final answer = RTCSessionDescription(
        answerData['sdp'],
        answerData['type'],
      );
      await _peerConnection!.setRemoteDescription(answer);

    } catch (e) {
      print('处理接受响应失败: $e');
      _updateState(CallState.error);
    }
  }

  // 处理对方拒绝通话
  void handleCallRejected(String reason) {
    _cleanup();
    _updateState(CallState.rejected);
  }

  // 处理ICE候选者
  Future<void> handleIceCandidate(RTCIceCandidate candidate) async {
    try {
      if (_peerConnection != null) {
        await _peerConnection!.addCandidate(candidate);
      }
    } catch (e) {
      print('添加ICE候选者失败: $e');
    }
  }

  // 结束通话
  Future<void> endCall() async {
    if (_currentPeerId != null) {
      _webSocketService.sendCallEnd(_currentPeerId!);
    }
    await _cleanup();
    _updateState(CallState.ended);
  }

  // 清理资源
  Future<void> _cleanup() async {
    try {
      if (_localStream != null) {
        for (var track in _localStream!.getTracks()) {
          await track.stop();
        }
        await _localStream!.dispose();
        _localStream = null;
      }

      if (_remoteStream != null) {
        await _remoteStream!.dispose();
        _remoteStream = null;
      }

      if (_peerConnection != null) {
        await _peerConnection!.close();
        _peerConnection = null;
      }

      _currentPeerId = null;
      _isCaller = false;
    } catch (e) {
      print('清理资源失败: $e');
    }
  }

  // 更新状态
  void _updateState(CallState state) {
    _currentState = state;
    _callStateController.add(state);
  }

  // 获取本地流
  MediaStream? getLocalStream() {
    return _localStream;
  }

  // 获取远程流
  MediaStream? getRemoteStream() {
    return _remoteStream;
  }

  // 静音/取消静音
  void setMute(bool muted) {
    if (_localStream != null) {
      for (var track in _localStream!.getAudioTracks()) {
        track.enabled = !muted;
      }
    }
  }

  // 释放资源
  void dispose() {
    _cleanup();
    _callStateController.close();
  }
}

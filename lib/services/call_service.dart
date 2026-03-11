import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_base/services/websocket_service.dart';
import 'package:flutter_base/services/video_api.dart';

typedef IncomingCallCallback = void Function(String callerId, String? callerName, bool isOnlyAudio);

class CallService {
  static final CallService _instance = CallService._internal();
  factory CallService() => _instance;
  CallService._internal();

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  final _webSocketService = WebSocketService();
  final _videoApi = VideoApi();

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();
  bool _renderersInitialized = false;

  final _callStateController = StreamController<CallState>.broadcast();
  Stream<CallState> get callStateStream => _callStateController.stream;

  CallState _currentState = CallState.idle;
  CallState get currentState => _currentState;

  String? _currentPeerId;
  String? get currentPeerId => _currentPeerId;

  bool _isCaller = false;
  bool get isCaller => _isCaller;

  bool _isOnlyAudio = true;
  bool get isOnlyAudio => _isOnlyAudio;

  bool _toUserIsReady = false;
  bool get toUserIsReady => _toUserIsReady;

  Timer? _timer;
  int _time = 0;
  int get time => _time;

  final _timeController = StreamController<int>.broadcast();
  Stream<int> get timeStream => _timeController.stream;

  bool _isAudioEnabled = true;
  bool get isAudioEnabled => _isAudioEnabled;

  bool _isVideoEnabled = true;
  bool get isVideoEnabled => _isVideoEnabled;

  StreamSubscription? _subscription;
  bool _isVideoEventInitialized = false;

  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 3;
  static const Duration _reconnectDelay = Duration(seconds: 2);

  IncomingCallCallback? _onIncomingCall;

  void setOnIncomingCall(IncomingCallCallback callback) {
    _onIncomingCall = callback;
  }

  Future<void> initializeRenderers() async {
    if (_renderersInitialized) {
      print('renderers 已初始化，跳过');
      return;
    }
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    _renderersInitialized = true;
  }

  Future<MediaStream> initializeLocalStream() async {
    final permissionStatus = await Permission.microphone.request();
    if (permissionStatus != PermissionStatus.granted) {
      throw Exception('麦克风权限被拒绝');
    }

    final constraints = {
      'audio': true,
      'video': !_isOnlyAudio,
    };

    _localStream = await navigator.mediaDevices.getUserMedia(constraints);
    localRenderer.srcObject = _localStream;

    if (_isOnlyAudio) {
      _localStream!.getVideoTracks().forEach((track) {
        track.enabled = false;
      });
    }

    return _localStream!;
  }

  Future<RTCPeerConnection> createPeerConnectionInternal() async {
    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
        {'urls': 'stun:stun2.l.google.com:19302'},
        {'urls': 'stun:stun3.l.google.com:19302'},
        {'urls': 'stun:stun4.l.google.com:19302'},
        {
          'urls': 'turn:123.56.168.149:3478',
          'username': 'webrtc',
          'credential': 'webrtc123',
        },
        {
          'urls': 'turn:123.56.168.149:3478?transport=tcp',
          'username': 'webrtc',
          'credential': 'webrtc123',
        },
      ],
      'sdpSemantics': 'unified-plan',
      'iceCandidatePoolSize': 10,
    };

    print('创建PeerConnection');
    _peerConnection = await createPeerConnection(config);

    if (_localStream != null) {
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });
    }

    _peerConnection!.onIceCandidate = handleICECandidateEvent;
    _peerConnection!.onIceConnectionState = handleICEConnectionStateChangeEvent;
    _peerConnection!.onTrack = handleTrackEvent;
    _peerConnection!.onConnectionState = (state) {
      print('连接状态: $state');
    };

    return _peerConnection!;
  }

  Future<void> handleICECandidateEvent(RTCIceCandidate candidate) async {
    if (_currentPeerId != null && candidate != null) {
      print('发送ICE候选者: ${candidate.candidate}');
      await _videoApi.candidate(_currentPeerId!, {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    }
  }

  void handleICEConnectionStateChangeEvent(RTCIceConnectionState? state) {
    print('ICE连接状态: $state');
    if (state == RTCIceConnectionState.RTCIceConnectionStateConnected) {
      _toUserIsReady = true;
      _reconnectAttempts = 0;
      _destroyReconnectTimer();
      _destroyTimer();
      _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
        _time++;
        _timeController.add(_time);
      });
      _updateState(CallState.connected);
    } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
      print('ICE连接断开，尝试重连...');
      _attemptReconnect();
    } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
        state == RTCIceConnectionState.RTCIceConnectionStateClosed) {
      handleHangup();
    }
  }

  void handleTrackEvent(RTCTrackEvent event) {
    print('收到远程流: ${event.track.kind}');
    if (event.streams.isNotEmpty) {
      _remoteStream = event.streams[0];
      remoteRenderer.srcObject = _remoteStream;
    }
  }

  void videoEvent() {
    if (_isVideoEventInitialized) {
      print('videoEvent 已初始化，跳过');
      return;
    }
    _isVideoEventInitialized = true;

    _subscription = _webSocketService.eventStream.listen((event) {
      if (event['type'] == 'on-receive-video') {
        var data = event['content'];
        print('收到视频事件: ${data['type']}');
        switch (data['type']) {
          case 'offer':
            handleVideoOfferMsg(data);
            break;
          case 'answer':
            handleVideoAnswerMsg(data);
            break;
          case 'candidate':
            handleNewICECandidateMsg(data);
            break;
          case 'hangup':
            handleHangup();
            break;
          case 'accept':
            onOffer();
            break;
          case 'invite':
            handleIncomingCall(data);
            break;
        }
      }
    });
  }

  Future<void> handleVideoOfferMsg(Map<String, dynamic> data) async {
    try {
      print('处理offer消息');
      if (_peerConnection == null) {
        print('PeerConnection未初始化');
        return;
      }
      final RTCSessionDescription desc =
          RTCSessionDescription(data['desc']['sdp'], data['desc']['type']);
      await _peerConnection!.setRemoteDescription(desc);
      RTCSessionDescription localDesc = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(localDesc);
      await _videoApi.answer(_currentPeerId!, {
        'sdp': localDesc.sdp,
        'type': localDesc.type,
      });
      print('已发送answer');
    } catch (e) {
      print('处理offer失败: $e');
    }
  }

  Future<void> handleVideoAnswerMsg(Map<String, dynamic> data) async {
    try {
      print('处理answer消息');
      if (_peerConnection == null) {
        print('PeerConnection未初始化');
        return;
      }
      final RTCSessionDescription remoteDesc = RTCSessionDescription(
        data['desc']['sdp'],
        data['desc']['type'],
      );
      await _peerConnection!.setRemoteDescription(remoteDesc);
      print('已设置远程描述');
    } catch (e) {
      print('处理answer失败: $e');
    }
  }

  Future<void> handleNewICECandidateMsg(Map<String, dynamic> data) async {
    try {
      print('处理ICE候选者消息');
      if (_peerConnection == null) {
        print('PeerConnection未初始化');
        return;
      }
      final RTCIceCandidate candidate = RTCIceCandidate(
        data['candidate']['candidate'],
        data['candidate']['sdpMid'],
        data['candidate']['sdpMLineIndex'],
      );
      await _peerConnection!.addCandidate(candidate);
      print('已添加ICE候选者');
    } catch (e) {
      print('添加ICE候选者失败: $e');
    }
  }

  Future<void> onOffer() async {
    try {
      print('创建offer');
      if (_peerConnection == null) {
        print('PeerConnection未初始化');
        return;
      }
      RTCSessionDescription offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);
      await _videoApi.offer(_currentPeerId!, {
        'sdp': offer.sdp,
        'type': offer.type,
      });
      print('已发送offer');
    } catch (e) {
      print('创建offer失败: $e');
    }
  }

  void handleIncomingCall(Map<String, dynamic> data) {
    print('收到来电: $data');
    final fromUserId = data['fromUserId'] as String?;
    final isOnlyAudio = data['isOnlyAudio'] as bool? ?? true;

    if (fromUserId != null) {
      _currentPeerId = fromUserId;
      _isOnlyAudio = isOnlyAudio;
      _isCaller = false;
      _updateState(CallState.ringing);

      if (_onIncomingCall != null) {
        _onIncomingCall!(fromUserId, data['fromUserName'], isOnlyAudio);
      }
    }
  }

  Future<void> initiateCall(String calleeId, {bool isOnlyAudio = true}) async {
    try {
      _isCaller = true;
      _currentPeerId = calleeId;
      _isOnlyAudio = isOnlyAudio;
      _toUserIsReady = false;
      _updateState(CallState.calling);

      await initializeRenderers();
      await initializeLocalStream();
      await createPeerConnectionInternal();

      final result = await _videoApi.invite(calleeId, isOnlyAudio);
      print('invite结果: $result');
      
      if (result['code'] == -1) {
        throw Exception(result['message'] ?? '用户不在线');
      }
      
      print('已发送invite到 $calleeId');

    } catch (e) {
      print('发起呼叫失败: $e');
      _updateState(CallState.error);
      throw Exception('发起呼叫失败: $e');
    }
  }

  Future<void> acceptCall() async {
    try {
      if (_currentPeerId == null) {
        throw Exception('没有待接听的通话');
      }

      _updateState(CallState.connecting);

      await initializeRenderers();
      await initializeLocalStream();
      await createPeerConnectionInternal();

      final result = await _videoApi.accept(_currentPeerId!);
      print('accept结果: $result');
      
      if (result['code'] == -1) {
        throw Exception(result['message'] ?? '用户不在线');
      }
      
      _toUserIsReady = true;
      print('已发送accept');

    } catch (e) {
      print('接受通话失败: $e');
      _updateState(CallState.error);
      throw Exception('接受通话失败: $e');
    }
  }

  void rejectCall() {
    if (_currentPeerId != null) {
      _videoApi.hangup(_currentPeerId!);
    }
    _cleanup();
    _updateState(CallState.rejected);
  }

  void _destroyReconnectTimer() {
    if (_reconnectTimer != null && _reconnectTimer!.isActive) {
      _reconnectTimer!.cancel();
      _reconnectTimer = null;
    }
  }

  void _attemptReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      print('重连次数已达上限，结束通话');
      handleHangup();
      return;
    }

    _reconnectAttempts++;
    print('尝试重连第 $_reconnectAttempts 次');

    _reconnectTimer = Timer(_reconnectDelay, () {
      _reconnect();
    });
  }

  Future<void> _reconnect() async {
    try {
      print('开始重连...');
      
      if (_peerConnection != null) {
        await _peerConnection!.close();
        _peerConnection = null;
      }

      await createPeerConnectionInternal();

      if (_isCaller) {
        await onOffer();
      } else {
        await onOffer();
      }

      print('重连尝试完成');
    } catch (e) {
      print('重连失败: $e');
      if (_reconnectAttempts < _maxReconnectAttempts) {
        _attemptReconnect();
      } else {
        handleHangup();
      }
    }
  }

  void handleHangup() {
    _destroyReconnectTimer();
    _destroyTimer();
    _cleanup();
    _updateState(CallState.ended);
  }

  Future<void> endCall() async {
    if (_currentPeerId != null) {
      await _videoApi.hangup(_currentPeerId!);
    }
    await _cleanup();
    _updateState(CallState.ended);
  }

  void _destroyTimer() {
    if (_timer != null && _timer!.isActive) {
      _timer!.cancel();
      _timer = null;
    }
  }

  Future<void> _cleanup() async {
    try {
      _destroyReconnectTimer();
      _destroyTimer();
      _time = 0;
      _toUserIsReady = false;
      _reconnectAttempts = 0;

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

      localRenderer.srcObject = null;
      remoteRenderer.srcObject = null;

      if (_peerConnection != null) {
        await _peerConnection!.close();
        _peerConnection = null;
      }

      _currentPeerId = null;
      _isCaller = false;
      _renderersInitialized = false;
      _isVideoEventInitialized = false;
    } catch (e) {
      print('清理资源失败: $e');
    }
  }

  void toggleAudio() {
    _isAudioEnabled = !_isAudioEnabled;
    if (_localStream != null) {
      _localStream!.getAudioTracks().forEach((track) {
        track.enabled = _isAudioEnabled;
      });
    }
  }

  void toggleVideo() {
    _isVideoEnabled = !_isVideoEnabled;
    if (_localStream != null) {
      _localStream!.getVideoTracks().forEach((track) {
        track.enabled = _isVideoEnabled;
      });
    }
  }

  void _updateState(CallState state) {
    if (!_callStateController.isClosed) {
      _currentState = state;
      _callStateController.add(state);
    }
  }

  MediaStream? getLocalStream() => _localStream;
  MediaStream? getRemoteStream() => _remoteStream;

  void setMute(bool muted) {
    if (_localStream != null) {
      for (var track in _localStream!.getAudioTracks()) {
        track.enabled = !muted;
      }
    }
  }

  void dispose() {
    print('CallService dispose 被调用，但不关闭单例');
  }

  void reset() {
    print('CallService 重置');
    _subscription?.cancel();
    _subscription = null;
    _isVideoEventInitialized = false;
    _cleanup();
    if (!_callStateController.isClosed) {
      _callStateController.close();
    }
  }
}

enum CallState {
  idle,
  calling,
  ringing,
  connecting,
  connected,
  ended,
  rejected,
  error,
}

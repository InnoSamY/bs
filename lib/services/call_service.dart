/// 语音通话服务类
/// 
/// 这是应用的核心通话服务，提供完整的语音通话功能。
/// 
/// 主要功能：
/// 1. WebRTC 语音通话
/// 2. 后量子加密（ML-KEM）
/// 3. 基于哈希的后量子签名原型
/// 4. 端到端加密消息
/// 5. ICE 候选交换
/// 6. 会话管理
/// 
/// 安全特性：
/// - ML-KEM 后量子密钥交换
/// - 基于哈希的后量子签名原型（Lamport OTS 原型实现）
/// - AES-256-GCM 对称加密
/// - 通话请求签名验证
/// 
/// ⚠️ 重要说明：
/// 本服务中的数字签名采用基于哈希的后量子签名原型，用于概念验证。
/// 这不是标准的 FIPS 204 ML-DSA (Dilithium) 实现。
/// 生产环境建议使用经过审计的标准密码学库。
/// 
/// 使用流程：
/// 1. 初始化密钥：initializeKeys()
/// 2. 发起通话：initiateCall()
/// 3. 接听通话：acceptCall()
/// 4. 发送消息：sendSecureMessage()
/// 5. 结束通话：handleHangup()

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_base/services/websocket_service.dart';
import 'package:flutter_base/services/audio_api.dart';
import 'package:flutter_base/services/pqc_kem_service.dart';
import 'package:flutter_base/services/pqc_signature_service.dart';
import 'package:flutter_base/services/auth_service.dart';
import 'package:flutter_base/services/crypto_service.dart';
import 'package:flutter_base/models/user.dart';
import 'package:crypto/crypto.dart';

/// 来电回调函数类型
/// 
/// 当收到来电时调用的回调函数。
/// 参数：
/// - callerId: 呼叫方用户ID
/// - callerName: 呼叫方用户名（可能为空）
/// - isOnlyAudio: 是否仅音频通话
/// - kemCiphertext: KEM 密文（用于密钥交换）
/// - signature: 签名（用于验证呼叫者身份）
/// - sigPublicKey: 签名公钥
/// - timestamp: 时间戳
/// - offer: WebRTC offer
typedef IncomingCallCallback = void Function(
  String callerId, 
  String? callerName, 
  bool isOnlyAudio, {
  String? kemCiphertext,
  String? signature,
  String? sigPublicKey,
  String? timestamp,
  Map<String, dynamic>? offer,
});

/// 通话状态枚举
/// 
/// 表示通话的不同状态阶段。
enum CallState {
  idle,           // 空闲状态，无通话
  calling,        // 呼叫中
  ringing,        // 响铃中（收到来电）
  connecting,     // 连接中
  connected,      // 已连接（通话中）
  ended,          // 通话结束
  rejected,       // 被拒绝
  error,          // 错误状态
}

/// 通话服务类（单例模式）
/// 
/// 提供所有音视频通话相关的功能。
/// 使用单例模式确保全局只有一个实例。
class CallService {
  /// 单例实例
  static final CallService _instance = CallService._internal();
  
  /// 获取单例实例
  factory CallService() => _instance;
  
  /// 内部构造函数
  CallService._internal();

  // ==================== 服务依赖 ====================
  
  final _webSocketService = WebSocketService();
  final _audioApi = AudioApi();
  final _kemService = PqcKemService();
  final _sigService = PqcSignatureService();
  final _cryptoService = CryptoService();
  final _authService = AuthService();

  // ==================== 媒体流 ====================
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  // ==================== 状态管理 ====================
  final _callStateController = StreamController<CallState>.broadcast();
  Stream<CallState> get callStateStream => _callStateController.stream;

  CallState _currentState = CallState.idle;
  CallState get currentState => _currentState;

  bool _isCleanupInProgress = false;
  bool _isRejecting = false;

  // ==================== 通话信息 ====================
  String? _currentPeerId;
  String? get currentPeerId => _currentPeerId;

  bool _isCaller = false;
  bool get isCaller => _isCaller;

  bool _isOnlyAudio = true;
  bool get isOnlyAudio => _isOnlyAudio;

  bool _toUserIsReady = false;
  bool get toUserIsReady => _toUserIsReady;

  // ==================== 计时器 ====================
  Timer? _timer;
  int _time = 0;
  int get time => _time;

  final _timeController = StreamController<int>.broadcast();
  Stream<int> get timeStream => _timeController.stream;

  // ==================== 媒体控制 ====================
  bool _isAudioEnabled = true;
  bool get isAudioEnabled => _isAudioEnabled;

  // ==================== 事件订阅 ====================
  StreamSubscription? _subscription;
  bool _isAudioEventInitialized = false;

  // ==================== 重连机制 ====================
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 3;
  static const Duration _reconnectDelay = Duration(seconds: 2);

  // ==================== 回调函数 ====================
  IncomingCallCallback? _onIncomingCall;

  // ==================== 密钥与会话 ====================
  UserKeys? _currentUserKeys;
  
  /// 会话密钥存储
  /// key: 对端用户ID
  /// value: 会话密钥（Base64 编码的共享密钥）
  final Map<String, String> _sessionKeys = {};
  
  /// 联系人公钥缓存
  /// key: 联系人ID
  /// value: {kemPublicKey, sigPublicKey}
  final Map<String, Map<String, String>> _contactKeys = {};

  /// 设置来电回调
  void setOnIncomingCall(IncomingCallCallback callback) {
    _onIncomingCall = callback;
  }

  /// 初始化当前用户的密钥
  /// 
  /// 从本地存储加载用户的密钥对
  Future<void> initializeKeys() async {
    if (_currentUserKeys != null) {
      print('密钥已加载，跳过');
      return;
    }

    try {
      print('加载用户密钥...');
      _currentUserKeys = await _authService.getCurrentUserKeys();
      
      if (_currentUserKeys == null) {
        throw Exception('用户密钥未找到，请重新登录');
      }
      
      print('✓ 用户密钥加载成功');
      print('  KEM 公钥长度: ${base64Decode(_currentUserKeys!.kemPublicKey).length} 字节');
      print('  签名公钥长度: ${base64Decode(_currentUserKeys!.sigPublicKey).length} 字节');
    } catch (e) {
      print('密钥加载失败: $e');
      throw Exception('密钥加载失败: $e');
    }
  }

  /// 缓存联系人公钥
  /// 
  /// 参数：
  /// - contactId: 联系人ID
  /// - kemPublicKey: ML-KEM 公钥
  /// - sigPublicKey: 签名公钥
  void cacheContactKeys(String contactId, String kemPublicKey, String sigPublicKey) {
    _contactKeys[contactId] = {
      'kemPublicKey': kemPublicKey,
      'sigPublicKey': sigPublicKey,
    };
    print('已缓存联系人 $contactId 的公钥');
  }

  /// 获取联系人公钥
  Map<String, String>? getContactKeys(String contactId) {
    return _contactKeys[contactId];
  }

  /// 获取会话密钥
  String? getSessionKey(String peerId) {
    return _sessionKeys[peerId];
  }

  /// 清除会话密钥
  void clearSessionKey(String peerId) {
    _sessionKeys.remove(peerId);
  }

  /// 派生 AES-256 密钥
  /// 
  /// 从共享密钥派生 AES-256 密钥
  String _deriveAesKey(String sharedSecret) {
    // 使用 SHA-256 派生 32 字节密钥
    return _cryptoService.deriveAesKey(sharedSecret);
  }

  /// 构建邀请消息的签名原文
  /// 
  /// 确保发起方和接收方使用相同的字段顺序和结构
  /// 
  /// 参数：
  /// - from: 发送方用户ID
  /// - to: 接收方用户ID
  /// - timestamp: 时间戳
  /// - offer: WebRTC offer
  /// - isOnlyAudio: 是否仅音频通话
  /// - kemCiphertext: ML-KEM 密文
  String _buildInviteMessageToSign(
    String from,
    String to,
    String timestamp,
    Map<String, dynamic> offer,
    bool isOnlyAudio,
    String kemCiphertext,
  ) {
    // 按照固定的字段顺序构建消息，确保签名和验签使用相同的原文
    final message = {
      'from': from,
      'to': to,
      'timestamp': timestamp,
      'offer': offer,
      'isOnlyAudio': isOnlyAudio,
      'kemCiphertext': kemCiphertext,
    };
    return jsonEncode(message);
  }

  /// 构建应答消息的签名原文
  /// 
  /// 确保发起方和接收方使用相同的字段顺序和结构
  /// 
  /// 参数：
  /// - from: 发送方用户ID
  /// - to: 接收方用户ID
  /// - timestamp: 时间戳
  /// - answer: WebRTC answer
  String _buildAnswerMessageToSign(
    String from,
    String to,
    String timestamp,
    Map<String, dynamic> answer,
  ) {
    // 按照固定的字段顺序构建消息，确保签名和验签使用相同的原文
    final message = {
      'from': from,
      'to': to,
      'timestamp': timestamp,
      'answer': answer,
    };
    return jsonEncode(message);
  }

  /// 发起通话
  /// 
  /// 流程：
  /// 1. 加载用户密钥
  /// 2. 使用对方 kemPublicKey 做 encapsulate
  /// 3. 生成共享密钥并派生 AES-256 key
  /// 4. 对呼叫消息签名
  /// 5. 发送带签名的呼叫请求
  /// 
  /// 参数：
  /// - calleeId: 被叫方用户ID
  /// - calleeKemPublicKey: 被叫方 ML-KEM 公钥
  /// - calleeSigPublicKey: 被叫方签名公钥
  /// - isOnlyAudio: 是否仅音频通话
  Future<void> initiateCall(
    String calleeId, 
    String calleeKemPublicKey, 
    String calleeSigPublicKey, {
    bool isOnlyAudio = true,
  }) async {
    try {
      print('发起通话到 $calleeId...');
      
      // 设置通话信息
      _isCaller = true;
      _currentPeerId = calleeId;
      _isOnlyAudio = isOnlyAudio;
      _toUserIsReady = false;
      _updateState(CallState.calling);

      // 缓存对方公钥
      cacheContactKeys(calleeId, calleeKemPublicKey, calleeSigPublicKey);

      // 加载用户密钥
      await initializeKeys();

      // 执行 ML-KEM 密钥封装
      print('执行 ML-KEM 密钥封装...');
      final encapsulation = _kemService.encapsulate(calleeKemPublicKey);
      final sharedSecret = encapsulation['sharedSecret']!;
      final ciphertext = encapsulation['ciphertext']!;
      
      // 派生 AES-256 密钥并存储
      final aesKey = _deriveAesKey(sharedSecret);
      _sessionKeys[calleeId] = aesKey;
      print('✓ 会话密钥已建立并派生为 AES-256 密钥');
      print('  AES 密钥长度: ${base64Decode(aesKey).length} 字节');

      // 初始化媒体设备
      await _initializeLocalStream();
      await _createPeerConnectionInternal();

      // 创建 offer
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      // 构建呼叫消息
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final offerMap = {
        'sdp': offer.sdp,
        'type': offer.type,
      };
      
      // 使用统一方法构建签名原文
      final callMessage = _buildInviteMessageToSign(
        _currentUserKeys!.userId,
        calleeId,
        timestamp,
        offerMap,
        isOnlyAudio,
        ciphertext,
      );

      // 对呼叫消息签名
      final signature = _sigService.signMessage(
        _currentUserKeys!.sigSecretKey, 
        callMessage
      );
      print('✓ 呼叫消息已签名');

      // 发送带签名的呼叫请求
      final result = await _audioApi.secureInviteV2(
        calleeId,
        isOnlyAudio,
        ciphertext,
        signature,
        _currentUserKeys!.sigPublicKey,
        offer.toMap(),
        timestamp,
      );
      
      print('secureInviteV2 结果: $result');
      
      if (result['code'] == -1) {
        throw Exception(result['message'] ?? '用户不在线');
      }
      
      print('✓ 呼叫请求已发送');

    } catch (e) {
      print('发起呼叫失败: $e');
      _updateState(CallState.error);
      _cleanup();
      throw Exception('发起呼叫失败: $e');
    }
  }

  /// 接听通话
  /// 
  /// 流程：
  /// 1. 验证呼叫消息签名
  /// 2. 使用本地 kemSecretKey 做 decapsulate 得到共享密钥
  /// 3. 派生 AES-256 key
  /// 4. 初始化媒体设备
  /// 5. 创建 answer
  /// 6. 对 answer 签名并发送
  Future<void> acceptCall(
    String callerId,
    String callerSigPublicKey,
    String kemCiphertext,
    Map<String, dynamic> offer,
    String timestamp,
    String signature,
  ) async {
    try {
      print('接听来自 $callerId 的通话...');
      
      if (_currentPeerId == null) {
        throw Exception('没有待接听的通话');
      }

      _updateState(CallState.connecting);

      // 加载用户密钥
      await initializeKeys();

      // 验证签名
      // 使用统一方法构建签名原文，确保与发起方格式一致
      final callMessage = _buildInviteMessageToSign(
        callerId,
        _currentUserKeys!.userId,
        timestamp,
        offer,
        _isOnlyAudio,
        kemCiphertext,
      );

      final isValid = _sigService.verifyMessage(
        callerSigPublicKey,
        callMessage,
        signature
      );

      if (!isValid) {
        print('✗ 签名验证失败，拒绝通话');
        _updateState(CallState.error);
        _cleanup();
        throw Exception('签名验证失败，通话被拒绝');
      }
      print('✓ 签名验证成功');

      // 执行 ML-KEM 密钥解封装
      print('执行 ML-KEM 密钥解封装...');
      final sharedSecret = _kemService.decapsulate(
        _currentUserKeys!.kemSecretKey,
        kemCiphertext
      );
      
      // 派生 AES-256 密钥并存储
      final aesKey = _deriveAesKey(sharedSecret);
      _sessionKeys[callerId] = aesKey;
      print('✓ 会话密钥已恢复并派生为 AES-256 密钥');
      print('  AES 密钥长度: ${base64Decode(aesKey).length} 字节');

      // 初始化媒体设备
      await _initializeLocalStream();
      await _createPeerConnectionInternal();

      // 设置远程描述（offer）
      final remoteDesc = RTCSessionDescription(offer['sdp'], offer['type']);
      await _peerConnection!.setRemoteDescription(remoteDesc);

      // 创建 answer
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);

      // 对 answer 签名
      final answerTimestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final answerMap = {
        'sdp': answer.sdp,
        'type': answer.type,
      };
      
      // 使用统一方法构建签名原文
      final answerMessage = _buildAnswerMessageToSign(
        _currentUserKeys!.userId,
        callerId,
        answerTimestamp,
        answerMap,
      );

      final answerSignature = _sigService.signMessage(
        _currentUserKeys!.sigSecretKey,
        answerMessage
      );

      // 发送带签名的 answer
      final result = await _audioApi.answerV2(
        callerId,
        answer.toMap(),
        answerSignature,
        _currentUserKeys!.sigPublicKey,
        answerTimestamp,
      );
      
      print('answerV2 结果: $result');
      
      if (result['code'] == -1) {
        throw Exception(result['message'] ?? '发送应答失败');
      }
      
      _toUserIsReady = true;
      print('✓ 通话已接听');

    } catch (e) {
      print('接听通话失败: $e');
      _updateState(CallState.error);
      _cleanup();
      throw Exception('接听通话失败: $e');
    }
  }

  /// 拒绝通话
  /// 
  /// 注意：此方法由接收方（被叫方）调用，只发送拒绝请求，
  /// 不更新本地状态。状态更新由拨号方收到 reject 事件后处理。
  Future<void> rejectCall() async {
    if (_isRejecting) {
      print('[CallService] rejectCall 已在进行中，跳过');
      return;
    }
    
    _isRejecting = true;
    print('[CallService] rejectCall 被调用（接收方拒绝），_currentPeerId: $_currentPeerId');
    
    if (_currentPeerId != null) {
      try {
        await _audioApi.reject(_currentPeerId!);
        print('[CallService] reject 请求已发送');
      } catch (e) {
        print('[CallService] reject 请求失败: $e');
      }
    } else {
      print('[CallService] 警告: _currentPeerId 为空，无法发送 reject');
    }
    
    _cleanup();
    print('[CallService] 接收方拒绝通话，清理资源完成');
    _isRejecting = false;
  }

  /// 初始化本地媒体流
  Future<MediaStream> _initializeLocalStream() async {
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

  /// 创建 PeerConnection
  Future<RTCPeerConnection> _createPeerConnectionInternal() async {
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

    print('创建 PeerConnection');
    _peerConnection = await createPeerConnection(config);

    if (_localStream != null) {
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });
    }

    _peerConnection!.onIceCandidate = _handleICECandidateEvent;
    _peerConnection!.onIceConnectionState = _handleICEConnectionStateChangeEvent;
    _peerConnection!.onTrack = _handleTrackEvent;
    _peerConnection!.onConnectionState = (state) {
      print('连接状态: $state');
    };

    _peerConnection!.onDataChannel = (channel) {
      print('收到数据通道: ${channel.label}');
      _dataChannel = channel;
      _dataChannel!.onMessage = (RTCDataChannelMessage message) {
        _handleSecureMessage(message.text);
      };
    };

    await _initializeDataChannel();

    return _peerConnection!;
  }

  /// 初始化数据通道
  Future<void> _initializeDataChannel() async {
    if (_peerConnection == null) return;

    try {
      final dataChannelDict = RTCDataChannelInit();
      dataChannelDict.ordered = true;
      dataChannelDict.maxRetransmits = 3;

      _dataChannel = await _peerConnection!.createDataChannel(
        'secure_message',
        dataChannelDict,
      );

      _dataChannel!.onMessage = (RTCDataChannelMessage message) {
        _handleSecureMessage(message.text);
      };

      _dataChannel!.onDataChannelState = (state) {
        print('数据通道状态: $state');
      };

      print('数据通道初始化成功');
    } catch (e) {
      print('初始化数据通道失败: $e');
    }
  }

  /// 处理 ICE 候选者
  Future<void> _handleICECandidateEvent(RTCIceCandidate candidate) async {
    if (_currentPeerId != null && candidate.candidate != null) {
      print('发送 ICE 候选者');
      await _audioApi.candidate(_currentPeerId!, {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    }
  }

  /// 处理 ICE 连接状态变化
  void _handleICEConnectionStateChangeEvent(RTCIceConnectionState? state) {
    print('ICE 连接状态: $state');
    if (state == RTCIceConnectionState.RTCIceConnectionStateConnected) {
      _toUserIsReady = true;
      _reconnectAttempts = 0;
      _destroyReconnectTimer();
      _destroyTimer();
      _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
        _time++;
        if (!_timeController.isClosed) {
          _timeController.add(_time);
        }
      });
      _updateState(CallState.connected);
    } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
      print('ICE 连接断开，尝试重连...');
      _attemptReconnect();
    } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
      print('ICE 连接失败，尝试重连...');
      _attemptReconnect();
    } else if (state == RTCIceConnectionState.RTCIceConnectionStateClosed) {
      handleHangup();
    }
  }

  /// 处理远程轨道事件
  void _handleTrackEvent(RTCTrackEvent event) {
    print('收到远程流: ${event.track.kind}');
    if (event.streams.isNotEmpty) {
      _remoteStream = event.streams[0];
    }
  }

  /// 初始化视频事件监听
  void audioEvent() {
    if (_isAudioEventInitialized) {
      print('audioEvent 已初始化，跳过');
      return;
    }
    _isAudioEventInitialized = true;

    _subscription = _webSocketService.eventStream.listen((event) {
      print('[CallService] 收到 WebSocket 事件: ${event['type']}');
      if (event['type'] == 'on-receive-audio') {
        var data = event['content'];
        print('[CallService] 收到音频事件: ${data['type']}');
        switch (data['type']) {
          case 'answer':
            _handleVideoAnswerMsg(data);
            break;
          case 'candidate':
            _handleNewICECandidateMsg(data);
            break;
          case 'hangup':
            handleHangup();
            break;
          case 'reject':
            print('[CallService] 匹配到 reject 事件，调用 _handleRejected');
            _handleRejected();
            break;
          case 'invite':
            _handleIncomingCall(data);
            break;
          default:
            print('[CallService] 未知事件类型: ${data['type']}');
        }
      }
    });
  }



  /// 处理 answer 消息
  Future<void> _handleVideoAnswerMsg(Map<String, dynamic> data) async {
    try {
      print('处理 answer 消息');
      if (_peerConnection == null) return;

      final answerData = data['answer'] as Map<String, dynamic>?;
      if (answerData == null) {
        print('Answer 数据为空');
        return;
      }

      final remoteDesc = RTCSessionDescription(
        answerData['sdp'],
        answerData['type'],
      );
      await _peerConnection!.setRemoteDescription(remoteDesc);
      print('已设置远程描述');
      
      // 验证签名（如果有）
      if (data['signature'] != null && data['sigPublicKey'] != null) {
        print('验证 answer 签名...');
        
        // 确保用户密钥已加载
        if (_currentUserKeys == null) {
          print('✗ 用户密钥未加载');
          _updateState(CallState.error);
          _cleanup();
          return;
        }
        
        // 构建与发送方相同格式的消息
        final answerMessage = _buildAnswerMessageToSign(
          _currentPeerId!,
          _currentUserKeys!.userId,
          data['timestamp'] as String,
          answerData
        );
        
        // 验证签名
        final isValid = _sigService.verifyMessage(
          data['sigPublicKey'] as String,
          answerMessage,
          data['signature'] as String
        );
        
        if (!isValid) {
          print('✗ Answer 签名验证失败');
          _updateState(CallState.error);
          _cleanup();
          return;
        }
        
        print('✓ Answer 签名验证通过');
      }
    } catch (e) {
      print('处理 answer 失败: $e');
    }
  }

  /// 处理 ICE 候选者消息
  Future<void> _handleNewICECandidateMsg(Map<String, dynamic> data) async {
    try {
      print('处理 ICE 候选者消息');
      if (_peerConnection == null) return;

      final candidate = RTCIceCandidate(
        data['candidate']['candidate'],
        data['candidate']['sdpMid'],
        data['candidate']['sdpMLineIndex'],
      );
      await _peerConnection!.addCandidate(candidate);
      print('已添加 ICE 候选者');
    } catch (e) {
      print('添加 ICE 候选者失败: $e');
    }
  }



  /// 处理来电
  void _handleIncomingCall(Map<String, dynamic> data) {
    print('收到来电: $data');
    final fromUserId = data['fromUserId'] as String?;
    final isOnlyAudio = data['isOnlyAudio'] as bool? ?? true;
    final kemCiphertext = data['kemCiphertext'] as String?;
    final signature = data['signature'] as String?;
    final sigPublicKey = data['sigPublicKey'] as String?;
    final timestamp = data['timestamp'] as String?;
    final offer = data['offer'] as Map<String, dynamic>?;

    if (fromUserId != null) {
      _currentPeerId = fromUserId;
      _isOnlyAudio = isOnlyAudio;
      _isCaller = false;
      _updateState(CallState.ringing);

      // 缓存对方公钥
      if (sigPublicKey != null) {
        // KEM 公钥需要从服务器获取或在其他方式传递
        // 这里暂时只缓存签名公钥
        _contactKeys[fromUserId] = {
          'sigPublicKey': sigPublicKey,
          'kemCiphertext': kemCiphertext ?? '',
          'timestamp': timestamp ?? '',
          'offer': jsonEncode(offer),
          'signature': signature ?? '',
        };
      }

      if (_onIncomingCall != null) {
        _onIncomingCall!(
          fromUserId, 
          data['fromUserName'], 
          isOnlyAudio,
          kemCiphertext: kemCiphertext,
          signature: signature,
          sigPublicKey: sigPublicKey,
          timestamp: timestamp,
          offer: offer,
        );
      }
    }
  }

  /// 获取来电数据（用于接听时验证）
  Map<String, String>? getIncomingCallData(String callerId) {
    return _contactKeys[callerId];
  }

  /// 发送安全消息
  Future<void> sendSecureMessage(String message) async {
    if (_currentPeerId == null) {
      throw Exception('没有活动的通话');
    }

    final sessionKey = _sessionKeys[_currentPeerId!];
    if (sessionKey == null) {
      throw Exception('会话密钥未建立');
    }

    if (_dataChannel == null || _dataChannel!.state != RTCDataChannelState.RTCDataChannelOpen) {
      throw Exception('数据通道未就绪');
    }

    try {
      // 使用 AES-256-GCM 加密消息
      final encryptionResult = _cryptoService.encryptAesGcm(sessionKey, message);
      final ciphertext = encryptionResult['ciphertext']!;
      final iv = encryptionResult['iv']!;
      final tag = encryptionResult['tag']!;

      // 签名
      final signature = _sigService.signMessage(
        _currentUserKeys!.sigSecretKey,
        ciphertext + iv + tag
      );

      final payload = jsonEncode({
        'ciphertext': ciphertext,
        'iv': iv,
        'tag': tag,
        'signature': signature,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      _dataChannel!.send(RTCDataChannelMessage(payload));
      print('安全消息已发送');
    } catch (e) {
      print('发送安全消息失败: $e');
      throw Exception('发送安全消息失败: $e');
    }
  }

  /// 处理安全消息
  void _handleSecureMessage(String payload) {
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final ciphertext = data['ciphertext'] as String?;
      final iv = data['iv'] as String?;
      final tag = data['tag'] as String?;
      final signature = data['signature'] as String;
      final timestamp = data['timestamp'] as int;

      if (ciphertext == null || iv == null || tag == null) {
        print('消息格式错误，缺少必要字段');
        return;
      }

      if (_currentPeerId == null) return;

      final sessionKey = _sessionKeys[_currentPeerId!];
      if (sessionKey == null) return;

      // 获取对方签名公钥
      final contactKeys = _contactKeys[_currentPeerId!];
      if (contactKeys == null) return;

      // 验证签名
      final isValid = _sigService.verifyMessage(
        contactKeys['sigPublicKey']!,
        ciphertext + iv + tag,
        signature
      );

      if (!isValid) {
        print('消息签名验证失败');
        return;
      }

      // 解密消息
      final decrypted = _cryptoService.decryptAesGcm(sessionKey, ciphertext, iv, tag);

      // 检查消息是否过期（30秒内有效）
      final age = DateTime.now().millisecondsSinceEpoch - timestamp;
      if (age > 30000) {
        print('消息已过期，忽略');
        return;
      }

      print('收到安全消息: $decrypted');
    } catch (e) {
      print('处理安全消息失败: $e');
    }
  }



  /// 尝试重连
  void _attemptReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      print('已达到最大重连次数');
      handleHangup();
      return;
    }

    _reconnectAttempts++;
    print('尝试重连 ($_reconnectAttempts/$_maxReconnectAttempts)');

    _reconnectTimer = Timer(_reconnectDelay, () async {
      if (_peerConnection != null) {
        await _peerConnection!.close();
        _peerConnection = null;
      }
      
      await _createPeerConnectionInternal();
      
      // 重连时，由于使用的是新版信令，不需要重新发送offer
      // 连接会通过ICE候选者交换自动恢复
    });
  }



  /// 挂断通话
  void handleHangup() {
    print('handleHangup 被调用');
    endCall();
  }

  /// 处理被拒绝
  void _handleRejected() {
    print('[CallService] ========================================');
    print('[CallService] >>> _handleRejected 被调用 <<<');
    print('[CallService] 当前状态: $_currentState');
    print('[CallService] ========================================');
    _cleanup();
    _updateState(CallState.rejected);
    print('[CallService] _handleRejected 处理完成');
  }

  /// 结束通话
  Future<void> endCall() async {
    try {
      print('endCall 被调用');
      if (_currentPeerId != null) {
        await _audioApi.hangup(_currentPeerId!);
      }
      _cleanup();
      _updateState(CallState.ended);
      print('通话已结束');
    } catch (e) {
      print('结束通话失败: $e');
      _updateState(CallState.error);
    }
  }

  /// 设置静音状态
  void setMute(bool muted) {
    if (_localStream != null) {
      _isAudioEnabled = !muted;
      _localStream!.getAudioTracks().forEach((track) {
        track.enabled = _isAudioEnabled;
      });
    }
  }

  /// 清理资源
  void _cleanup() {
    if (_isCleanupInProgress) {
      print('清理已在进行，跳过重复清理');
      return;
    }
    
    _isCleanupInProgress = true;
    print('开始清理资源...');

    _destroyTimer();
    _destroyReconnectTimer();
    _reconnectAttempts = 0;

    if (_currentPeerId != null) {
      clearSessionKey(_currentPeerId!);
    }

    if (_dataChannel != null) {
      _dataChannel!.close();
      _dataChannel = null;
    }

    if (_peerConnection != null) {
      _peerConnection!.close();
      _peerConnection = null;
    }

    if (_localStream != null) {
      _localStream!.getTracks().forEach((track) {
        track.stop();
      });
      _localStream = null;
    }

    _remoteStream = null;

    _currentPeerId = null;
    _isCaller = false;
    _time = 0;
    _toUserIsReady = false;
    _isOnlyAudio = true;
    
    _isAudioEventInitialized = false;
    _currentUserKeys = null;
    
    _isCleanupInProgress = false;

    print('资源清理完成');
  }

  /// 销毁重连计时器
  void _destroyReconnectTimer() {
    if (_reconnectTimer != null && _reconnectTimer!.isActive) {
      _reconnectTimer!.cancel();
      _reconnectTimer = null;
    }
  }

  /// 销毁通话计时器
  void _destroyTimer() {
    if (_timer != null && _timer!.isActive) {
      _timer!.cancel();
      _timer = null;
    }
  }

  /// 切换音频
  void toggleAudio() {
    if (_localStream != null) {
      _isAudioEnabled = !_isAudioEnabled;
      _localStream!.getAudioTracks().forEach((track) {
        track.enabled = _isAudioEnabled;
      });
    }
  }

  /// 切换扬声器
  Future<void> toggleSpeaker() async {
    print('切换扬声器功能');
  }

  /// 切换听筒
  Future<void> toggleEarpiece() async {
    print('切换听筒功能');
  }

  /// 更新通话状态
  void _updateState(CallState state) {
    print('[CallService] 更新状态: $_currentState -> $state');
    _currentState = state;
    if (!_callStateController.isClosed) {
      _callStateController.add(state);
      print('[CallService] 状态已发送到流: $state');
    } else {
      print('[CallService] 警告: _callStateController 已关闭');
    }
  }

  /// 释放资源
  Future<void> dispose() async {
    _cleanup();
    _subscription?.cancel();
  }
}

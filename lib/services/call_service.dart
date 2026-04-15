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
import 'package:audioplayers/audioplayers.dart';
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
  final _audioPlayer = AudioPlayer();

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
      return;
    }

    try {
      _currentUserKeys = await _authService.getCurrentUserKeys();
      
      if (_currentUserKeys == null) {
        throw Exception('用户密钥未找到，请重新登录');
      }
      
      print('✓ 用户密钥加载成功');
      print('  KEM 公钥长度: ${base64Decode(_currentUserKeys!.kemPublicKey).length} 字节');
      print('  签名公钥长度: ${base64Decode(_currentUserKeys!.sigPublicKey).length} 字节');
    } catch (e) {
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
  // 通话开始时间
  DateTime? _callStartTime;

  Future<void> initiateCall(
    String calleeId, 
    String calleeKemPublicKey, 
    String calleeSigPublicKey, {
    bool isOnlyAudio = true,
  }) async {
    try {
      // 记录通话开始时间（测试一）
      _callStartTime = DateTime.now();
      print('测试一：通话建立开始时间: ${_callStartTime!.toString()}');
      
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

      // 执行 ML-KEM 密钥封装（测试二）
      print('执行 ML-KEM 密钥封装...');
      final kemStartTime = DateTime.now();
      final encapsulation = _kemService.encapsulate(calleeKemPublicKey);
      final kemEndTime = DateTime.now();
      final kemDuration = kemEndTime.difference(kemStartTime).inMilliseconds;
      print('测试二：ML-KEM 封装耗时: ${kemDuration}ms');
      
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

      // 等待 ICE 候选者收集完成
      await _waitForIceGatheringComplete();

      // 获取包含 ICE 候选者的完整 offer
      final completeOffer = await _peerConnection!.getLocalDescription();
      if (completeOffer == null) {
        throw Exception('获取本地描述失败');
      }

      // 构建呼叫消息
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final offerMap = {
        'sdp': completeOffer.sdp,
        'type': completeOffer.type,
      };
      
      // 加密 WebRTC offer
      final offerJson = jsonEncode(offerMap);
      final encryptedOffer = _cryptoService.encryptAesGcm(aesKey, offerJson);
      
      // 使用统一方法构建签名原文
      final callMessage = _buildInviteMessageToSign(
        _currentUserKeys!.userId,
        calleeId,
        timestamp,
        encryptedOffer, // 传递加密后的offer
        isOnlyAudio,
        ciphertext,
      );

      // 对呼叫消息签名
      final signature = _sigService.signMessage(
        _currentUserKeys!.sigSecretKey, 
        callMessage
      );

      // 发送带签名的呼叫请求
      final result = await _audioApi.secureInviteV2(
        calleeId,
        isOnlyAudio,
        ciphertext,
        signature,
        _currentUserKeys!.sigPublicKey,
        encryptedOffer, // 发送加密后的offer
        timestamp,
      );
      
      if (result['code'] == -1) {
        throw Exception(result['message'] ?? '用户不在线');
      }

    } catch (e) {
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
        offer, // offer 是加密的
        _isOnlyAudio,
        kemCiphertext,
      );

      final isValid = _sigService.verifyMessage(
        callerSigPublicKey,
        callMessage,
        signature
      );

      if (!isValid) {
        _updateState(CallState.error);
        _cleanup();
        throw Exception('签名验证失败，通话被拒绝');
      }
      print('✓ 签名验证成功');

      // 执行 ML-KEM 密钥解封装（测试二）
      print('执行 ML-KEM 密钥解封装...');
      final decapsulateStartTime = DateTime.now();
      final sharedSecret = _kemService.decapsulate(
        _currentUserKeys!.kemSecretKey,
        kemCiphertext
      );
      final decapsulateEndTime = DateTime.now();
      final decapsulateDuration = decapsulateEndTime.difference(decapsulateStartTime).inMilliseconds;
      print('测试二：ML-KEM 解封装耗时: ${decapsulateDuration}ms');
      
      // 派生 AES-256 密钥并存储
      final aesKey = _deriveAesKey(sharedSecret);
      _sessionKeys[callerId] = aesKey;
      print('✓ 会话密钥已恢复并派生为 AES-256 密钥');
      print('  AES 密钥长度: ${base64Decode(aesKey).length} 字节');

      // 解密 WebRTC offer
      final offerJson = _cryptoService.decryptAesGcm(
        aesKey,
        offer['ciphertext']!,
        offer['iv']!,
        offer['tag']!
      );
      final decryptedOffer = jsonDecode(offerJson);

      // 初始化媒体设备
      await _initializeLocalStream();
      await _createPeerConnectionInternal();

      // 设置远程描述（offer）
      final remoteDesc = RTCSessionDescription(decryptedOffer['sdp'], decryptedOffer['type']);
      await _peerConnection!.setRemoteDescription(remoteDesc);

      // 创建 answer
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);

      // 等待 ICE 候选者收集完成
      await _waitForIceGatheringComplete();

      // 获取包含 ICE 候选者的完整 answer
      final completeAnswer = await _peerConnection!.getLocalDescription();
      if (completeAnswer == null) {
        throw Exception('获取本地描述失败');
      }

      // 对 answer 签名
      final answerTimestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final answerMap = {
        'sdp': completeAnswer.sdp,
        'type': completeAnswer.type,
      };
      
      // 加密 WebRTC answer
      final answerJson = jsonEncode(answerMap);
      final encryptedAnswer = _cryptoService.encryptAesGcm(aesKey, answerJson);
      
      // 使用统一方法构建签名原文
      final answerMessage = _buildAnswerMessageToSign(
        _currentUserKeys!.userId,
        callerId,
        answerTimestamp,
        encryptedAnswer, // 传递加密后的answer
      );

      final answerSignature = _sigService.signMessage(
        _currentUserKeys!.sigSecretKey,
        answerMessage
      );

      // 发送带签名的 answer
      final result = await _audioApi.answerV2(
        callerId,
        encryptedAnswer, // 发送加密后的answer
        answerSignature,
        _currentUserKeys!.sigPublicKey,
        answerTimestamp,
      );
      
      if (result['code'] == -1) {
        throw Exception(result['message'] ?? '发送应答失败');
      }
      
      _toUserIsReady = true;

    } catch (e) {
      _updateState(CallState.error);
      _cleanup();
      throw Exception('接听通话失败: $e');
    }
  }

  /// 等待 ICE 候选者收集完成
  Future<void> _waitForIceGatheringComplete() async {
    const timeout = Duration(seconds: 5);
    const checkInterval = Duration(milliseconds: 100);
    
    final startTime = DateTime.now();
    
    while (DateTime.now().difference(startTime) < timeout) {
      final gatheringState = await _peerConnection!.getIceGatheringState();
      
      if (gatheringState == RTCIceGatheringState.RTCIceGatheringStateComplete) {
        return;
      }
      
      await Future.delayed(checkInterval);
    }
  }

  /// 拒绝通话
  /// 
  /// 注意：此方法由接收方（被叫方）调用，只发送拒绝请求，
  /// 不更新本地状态。状态更新由拨号方收到 reject 事件后处理。
  Future<void> rejectCall() async {
    if (_isRejecting) {
      return;
    }
    
    _isRejecting = true;
    
    if (_currentPeerId != null) {
      try {
        await _audioApi.reject(_currentPeerId!);
      } catch (e) {
        // 忽略错误
      }
    }
    
    _cleanup();
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
      // 测试一：记录通话建立完成时间
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected && _callStartTime != null) {
        final callEndTime = DateTime.now();
        final callDuration = callEndTime.difference(_callStartTime!).inMilliseconds;
        print('测试一：通话建立完成时间: ${callEndTime.toString()}');
        print('测试一：通话建立时延: ${callDuration}ms');
      }
    };

    _peerConnection!.onDataChannel = (channel) {
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
      };
    } catch (e) {
    }
  }

  /// 处理 ICE 候选者
  Future<void> _handleICECandidateEvent(RTCIceCandidate candidate) async {
    if (_currentPeerId != null && candidate.candidate != null) {
      await _audioApi.candidate(_currentPeerId!, {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    }
  }

  /// 处理 ICE 连接状态变化
  void _handleICEConnectionStateChangeEvent(RTCIceConnectionState? state) {
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
      _attemptReconnect();
    } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
      _attemptReconnect();
    } else if (state == RTCIceConnectionState.RTCIceConnectionStateClosed) {
      handleHangup();
    }
  }

  /// 处理远程轨道事件
  void _handleTrackEvent(RTCTrackEvent event) {
    if (event.streams.isNotEmpty) {
      _remoteStream = event.streams[0];
    }
  }

  /// 初始化视频事件监听
  void audioEvent() {
    if (_isAudioEventInitialized) {
      return;
    }
    _isAudioEventInitialized = true;

    _subscription = _webSocketService.eventStream.listen((event) {
      if (event['type'] == 'on-receive-audio') {
        var data = event['content'];
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
            _handleRejected();
            break;
          case 'invite':
            _handleIncomingCall(data);
            break;
        }
      }
    });
  }



  /// 处理 answer 消息
  Future<void> _handleVideoAnswerMsg(Map<String, dynamic> data) async {
    try {
      if (_peerConnection == null) return;

      // 检查 PeerConnection 状态，避免重复设置远程描述
      final currentState = await _peerConnection!.getConnectionState();
      
      // 如果已经处于稳定状态或连接状态，忽略重复的 answer
      if (currentState == RTCPeerConnectionState.RTCPeerConnectionStateConnected ||
          currentState == RTCPeerConnectionState.RTCPeerConnectionStateConnecting) {
        return;
      }

      final answerData = data['answer'] as Map<String, dynamic>?;
      if (answerData == null) {
        return;
      }

      // 检查是否已经设置过远程描述
      final currentRemoteDesc = await _peerConnection!.getRemoteDescription();
      if (currentRemoteDesc != null) {
        return;
      }

      // 验证签名（如果有）
      if (data['signature'] != null && data['sigPublicKey'] != null) {
        // 确保用户密钥已加载
        if (_currentUserKeys == null) {
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
          _updateState(CallState.error);
          _cleanup();
          return;
        }
      }

      // 签名验证通过后，解密 answer
      final sessionKey = _sessionKeys[_currentPeerId!];
      if (sessionKey == null) {
        _updateState(CallState.error);
        _cleanup();
        return;
      }
      
      // 解密 WebRTC answer
      final answerJson = _cryptoService.decryptAesGcm(
        sessionKey,
        answerData['ciphertext']!,
        answerData['iv']!,
        answerData['tag']!
      );
      final decryptedAnswer = jsonDecode(answerJson);

      // 设置远程描述
      final remoteDesc = RTCSessionDescription(
        decryptedAnswer['sdp'],
        decryptedAnswer['type'],
      );
      await _peerConnection!.setRemoteDescription(remoteDesc);
    } catch (e) {
    }
  }

  /// 处理 ICE 候选者消息
  Future<void> _handleNewICECandidateMsg(Map<String, dynamic> data) async {
    try {
      if (_peerConnection == null) return;

      // 检查 PeerConnection 状态，确保可以添加 ICE 候选者
      final currentState = await _peerConnection!.getConnectionState();
      if (currentState == RTCPeerConnectionState.RTCPeerConnectionStateClosed ||
          currentState == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        return;
      }

      // 检查远程描述是否已设置
      final remoteDesc = await _peerConnection!.getRemoteDescription();
      if (remoteDesc == null) {
        // 可以在这里实现 ICE 候选者缓冲队列
        return;
      }

      final candidate = RTCIceCandidate(
        data['candidate']['candidate'],
        data['candidate']['sdpMid'],
        data['candidate']['sdpMLineIndex'],
      );
      await _peerConnection!.addCandidate(candidate);
    } catch (e) {
    }
  }



  /// 处理来电
  void _handleIncomingCall(Map<String, dynamic> data) {
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
    } catch (e) {
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
        return;
      }

      // 解密消息
      final decrypted = _cryptoService.decryptAesGcm(sessionKey, ciphertext, iv, tag);

      // 检查消息是否过期（30秒内有效）
      final age = DateTime.now().millisecondsSinceEpoch - timestamp;
      if (age > 30000) {
        return;
      }

    } catch (e) {
    }
  }



  /// 尝试重连
  void _attemptReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      handleHangup();
      return;
    }

    _reconnectAttempts++;

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
    // 如果当前状态已经是被拒绝，不应该再结束通话
    if (_currentState != CallState.rejected) {
      endCall();
    }
  }

  /// 处理被拒绝
  void _handleRejected() {
    _cleanup();
    _updateState(CallState.rejected);
  }

  /// 结束通话
  Future<void> endCall() async {
    try {
      // 如果当前状态已经是被拒绝，不应该再更新状态
      if (_currentState == CallState.rejected) {
        return;
      }
      if (_currentPeerId != null) {
        await _audioApi.hangup(_currentPeerId!);
      }
      _cleanup();
      _updateState(CallState.ended);
    } catch (e) {
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
      return;
    }
    
    _isCleanupInProgress = true;

    _destroyTimer();
    _destroyReconnectTimer();
    _reconnectAttempts = 0;
    
    // 停止铃声
    stopRingtone();

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
  }

  /// 切换听筒
  Future<void> toggleEarpiece() async {
  }

  /// 播放铃声
  Future<void> playRingtone() async {
    try {
      // 停止之前可能正在播放的音频
      await _audioPlayer.stop();
      // 重置播放器状态
      await _audioPlayer.seek(Duration.zero);
      
      // 设置音频源
      await _audioPlayer.setSource(AssetSource('Atria.ogg'));
      
      // 设置音量
      await _audioPlayer.setVolume(1.0);
      
      // 设置循环播放
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      
      // 开始播放
      await _audioPlayer.resume();
    } catch (e) {
      // 尝试使用不同的方式播放
      try {
        await _audioPlayer.play(AssetSource('Atria.ogg'));
      } catch (e2) {
        // 尝试使用延迟播放
        try {
          await Future.delayed(Duration(milliseconds: 100));
          await _audioPlayer.play(AssetSource('Atria.ogg'));
        } catch (e3) {
        }
      }
    }
  }

  /// 停止铃声
  Future<void> stopRingtone() async {
    try {
      await _audioPlayer.stop();
    } catch (e) {
    }
  }

  /// 更新通话状态
  void _updateState(CallState state) {
    _currentState = state;
    
    // 控制铃声
    if (state == CallState.ringing) {
      playRingtone();
    } else if (state == CallState.connecting || 
               state == CallState.connected || 
               state == CallState.ended || 
               state == CallState.rejected || 
               state == CallState.error) {
      stopRingtone();
    }
    
    if (!_callStateController.isClosed) {
      _callStateController.add(state);
    }
  }

  /// 释放资源
  Future<void> dispose() async {
    _cleanup();
    _subscription?.cancel();
  }
}

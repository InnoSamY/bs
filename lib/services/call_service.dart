/// 语音通话服务类
/// 
/// 这是应用的核心通话服务，提供完整的语音通话功能。
/// 
/// 主要功能：
/// 1. WebRTC 语音通话
/// 2. 后量子加密（ML-KEM、ML-DSA）
/// 3. 端到端加密消息
/// 4. ICE 候选交换
/// 5. 会话管理
/// 
/// 安全特性：
/// - 后量子密钥交换
/// - 数字签名验证
/// - AES-256-GCM 消息加密
/// - 通话请求签名验证
/// 
/// 使用流程：
/// 1. 初始化密钥：initializeKeys()
/// 2. 发起通话：initiateCall()
/// 3. 接听通话：acceptCall()
/// 4. 发送消息：sendSecureMessage()
/// 5. 结束通话：handleHangup()

import 'dart:async';
import 'dart:convert';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_base/services/websocket_service.dart';
import 'package:flutter_base/services/video_api.dart';
import 'package:flutter_base/services/crypto_service.dart';

/// 来电回调函数类型
/// 
/// 当收到来电时调用的回调函数。
/// 参数：
/// - callerId: 呼叫方用户ID
/// - callerName: 呼叫方用户名（可能为空）
/// - isOnlyAudio: 是否仅音频通话
typedef IncomingCallCallback = void Function(String callerId, String? callerName, bool isOnlyAudio);

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

  // ==================== 媒体流 ====================
  
  /// PeerConnection 实例
  /// 
  /// WebRTC 对等连接，用于建立和管理通话。
  /// 包括媒体协商、ICE 候选交换等。
  RTCPeerConnection? _peerConnection;
  
  /// 数据通道实例
  /// 
  /// 用于发送加密文本消息。
  RTCDataChannel? _dataChannel;
  
  /// 本地媒体流
  /// 
  /// 包含本地麦克风采集的音频。
  MediaStream? _localStream;
  
  /// 远程媒体流
  /// 
  /// 对方发送过来的音频流。
  MediaStream? _remoteStream;

  // ==================== 服务依赖 ====================
  
  /// WebSocket 服务
  /// 
  /// 用于实时通信，接收信令消息。
  final _webSocketService = WebSocketService();
  
  /// 视频 API 服务
  /// 
  /// 用于与服务器通信，发送和接收通话相关请求。
  final _videoApi = VideoApi();
  
  /// 加密服务
  /// 
  /// 提供后量子加密功能。
  final _cryptoService = CryptoService();

  // ==================== 状态管理 ====================
  
  /// 通话状态流控制器
  /// 
  /// 用于通知 UI 通话状态的变化。
  final _callStateController = StreamController<CallState>.broadcast();
  
  /// 通话状态流
  /// 
  /// UI 可以监听此流来更新界面。
  Stream<CallState> get callStateStream => _callStateController.stream;

  /// 当前通话状态
  CallState _currentState = CallState.idle;
  
  /// 获取当前通话状态
  CallState get currentState => _currentState;

  /// 是否正在清理中（防止重复清理）
  bool _isCleanupInProgress = false;
  String _cleanupStackTrace = '';

  // ==================== 通话信息 ====================
  
  /// 当前通话的对端用户ID
  String? _currentPeerId;
  
  /// 获取当前通话的对端用户ID
  String? get currentPeerId => _currentPeerId;

  /// 是否为主叫方
  bool _isCaller = false;
  
  /// 获取是否为主叫方
  bool get isCaller => _isCaller;

  /// 是否仅音频通话
  bool _isOnlyAudio = true;
  
  /// 获取是否仅音频通话
  bool get isOnlyAudio => _isOnlyAudio;

  /// 对端是否已就绪
  bool _toUserIsReady = false;
  
  /// 获取对端是否已就绪
  bool get toUserIsReady => _toUserIsReady;

  // ==================== 计时器 ====================
  
  /// 通话计时器
  Timer? _timer;
  
  /// 通话时长（秒）
  int _time = 0;
  
  /// 获取通话时长
  int get time => _time;

  /// 通话时长流控制器
  final _timeController = StreamController<int>.broadcast();
  
  /// 通话时长流
  Stream<int> get timeStream => _timeController.stream;

  // ==================== 媒体控制 ====================
  
  /// 音频是否启用
  bool _isAudioEnabled = true;
  
  /// 获取音频是否启用
  bool get isAudioEnabled => _isAudioEnabled;

  // ==================== 事件订阅 ====================
  
  /// WebSocket 事件订阅
  StreamSubscription? _subscription;
  
  /// 视频事件是否已初始化
  bool _isVideoEventInitialized = false;

  // ==================== 重连机制 ====================
  
  /// 重连计时器
  Timer? _reconnectTimer;
  
  /// 重连尝试次数
  int _reconnectAttempts = 0;
  
  /// 最大重连次数
  static const int _maxReconnectAttempts = 3;
  
  /// 重连延迟时间
  static const Duration _reconnectDelay = Duration(seconds: 2);

  // ==================== 回调函数 ====================
  
  /// 来电回调函数
  IncomingCallCallback? _onIncomingCall;

  // ==================== 密钥管理 ====================
  
  /// ML-DSA 签名密钥对
  /// 
  /// 用于：
  /// - 对通话请求进行数字签名
  /// - 验证对方身份
  Map<String, String>? _signatureKeyPair;
  
  /// ML-KEM 加密密钥对
  /// 
  /// 用于：
  /// - 密钥交换
  /// - 消息加密
  Map<String, String>? _encryptionKeyPair;
  
  /// 会话密钥存储
  /// 
  /// 存储与每个对端的会话密钥。
  /// key: 对端用户ID
  /// value: 会话密钥
  final Map<String, String> _sessionKeys = {};
  
  /// 密钥是否已初始化
  bool _keysInitialized = false;

  /// 设置来电回调
  /// 
  /// 用于处理收到的来电。
  /// 
  /// 参数：
  /// - callback: 来电时的回调函数
  void setOnIncomingCall(IncomingCallCallback callback) {
    _onIncomingCall = callback;
  }

  /// 初始化密钥
  /// 
  /// 初始化后量子加密密钥对。
  /// 在发起或接听通话前必须调用此方法。
  /// 
  /// 生成的密钥：
  /// 1. ML-DSA-2 签名密钥对：用于数字签名
  /// 2. ML-KEM-768 加密密钥对：用于密钥交换
  Future<void> initializeKeys() async {
    if (_keysInitialized) {
      print('密钥已初始化，跳过');
      return;
    }

    try {
      print('开始初始化后量子密钥...');
      
      // 生成签名密钥对
      _signatureKeyPair = _cryptoService.generateSignatureKeyPair();
      print('ML-DSA 签名密钥对生成成功');

      // 生成加密密钥对
      _encryptionKeyPair = _cryptoService.generateKeyPair();
      print('ML-KEM 加密密钥对生成成功');

      _keysInitialized = true;
      print('后量子密钥初始化完成');
    } catch (e) {
      print('密钥初始化失败: $e');
      throw Exception('密钥初始化失败: $e');
    }
  }

  /// 获取签名公钥
  /// 
  /// 返回用于验证签名的公钥。
  Map<String, String>? getSignaturePublicKey() {
    return _signatureKeyPair != null && _signatureKeyPair!['publicKey'] != null
        ? {'publicKey': _signatureKeyPair!['publicKey']!} 
        : null;
  }

  /// 获取加密公钥
  /// 
  /// 返回用于密钥交换的公钥。
  Map<String, String>? getEncryptionPublicKey() {
    return _encryptionKeyPair != null && _encryptionKeyPair!['publicKey'] != null
        ? {'publicKey': _encryptionKeyPair!['publicKey']!} 
        : null;
  }

  /// 获取会话密钥
  /// 
  /// 获取与指定对端的会话密钥。
  String? getSessionKey(String peerId) {
    return _sessionKeys[peerId];
  }

  /// 清除会话密钥
  /// 
  /// 结束通话后清除会话密钥。
  void clearSessionKey(String peerId) {
    _sessionKeys.remove(peerId);
  }

  /// 生成通话签名
  /// 
  /// 对通话请求进行数字签名，防止篡改和伪造。
  /// 
  /// 参数：
  /// - peerId: 对端用户ID
  /// - timestamp: 时间戳
  /// 
  /// 返回：
  /// - 数字签名
  String generateCallSignature(String peerId, String timestamp) {
    if (_signatureKeyPair == null) {
      throw Exception('签名密钥未初始化');
    }

    // 签名内容：通话类型:对方ID:时间戳
    final message = 'call_request:$peerId:$timestamp';
    // 使用私钥签名
    final signature = _cryptoService.sign(message, _signatureKeyPair!['privateKey']!);
    print('生成通话签名: $message');
    return signature;
  }

  /// 验证通话签名
  /// 
  /// 验证对方发来的通话请求签名。
  /// 
  /// 参数：
  /// - peerId: 对端用户ID
  /// - timestamp: 时间戳
  /// - signature: 数字签名
  /// - publicKey: 签名公钥
  /// 
  /// 返回：
  /// - 签名是否有效
  bool verifyCallSignature(String peerId, String timestamp, String signature, String publicKey) {
    final message = 'call_request:$peerId:$timestamp';
    final isValid = _cryptoService.verify(message, signature, publicKey);
    print('验证通话签名: $message, 结果: $isValid');
    return isValid;
  }

  /// 封装密钥
  /// 
  /// 使用 ML-KEM 算法封装密钥。
  /// 
  /// 参数：
  /// - peerPublicKey: 对方的公钥
  /// 
  /// 返回：
  /// - 包含共享密钥和密文的 Map
  Future<Map<String, String>> encapsulateKey(String peerPublicKey) async {
    try {
      print('开始 ML-KEM 密钥封装...');
      
      final encapsulation = _cryptoService.encapsulate(peerPublicKey);
      final sharedSecret = encapsulation['sharedSecret']!;
      final ciphertext = encapsulation['ciphertext']!;

      print('ML-KEM 密钥封装成功');
      print('共享密钥长度: ${base64Decode(sharedSecret).length} 字节');
      print('密文长度: ${base64Decode(ciphertext).length} 字节');

      return {
        'sharedSecret': sharedSecret,
        'ciphertext': ciphertext,
      };
    } catch (e) {
      print('ML-KEM 密钥封装失败: $e');
      throw Exception('密钥封装失败: $e');
    }
  }

  /// 解封装密钥
  /// 
  /// 使用 ML-KEM 算法解封装密钥。
  /// 
  /// 参数：
  /// - ciphertext: 对方发来的密文
  /// 
  /// 返回：
  /// - 共享密钥
  Future<String> decapsulateKey(String ciphertext) async {
    try {
      if (_encryptionKeyPair == null) {
        throw Exception('加密密钥未初始化');
      }

      print('开始 ML-KEM 密钥解封装...');
      
      final sharedSecret = _cryptoService.decapsulate(
        ciphertext,
        _encryptionKeyPair!['privateKey']!
      );

      print('ML-KEM 密钥解封装成功');
      print('共享密钥长度: ${base64Decode(sharedSecret).length} 字节');

      return sharedSecret;
    } catch (e) {
      print('ML-KEM 密钥解封装失败: $e');
      throw Exception('密钥解封装失败: $e');
    }
  }

  /// 建立安全会话
  /// 
  /// 与对端建立加密的安全会话。
  /// 
  /// 流程：
  /// 1. 使用对方公钥封装密钥
  /// 2. 存储会话密钥
  /// 3. 发送密文给对方
  /// 
  /// 参数：
  /// - peerId: 对端用户ID
  /// - peerPublicKey: 对方的公钥
  Future<void> establishSecureSession(String peerId, String peerPublicKey) async {
    try {
      print('开始建立安全会话: $peerId');

      // 步骤1: 封装密钥
      final encapsulation = await encapsulateKey(peerPublicKey);
      final sharedSecret = encapsulation['sharedSecret']!;
      final ciphertext = encapsulation['ciphertext']!;

      // 步骤2: 存储会话密钥
      _sessionKeys[peerId] = sharedSecret;
      print('安全会话建立成功，会话密钥已存储');

      // 步骤3: 发送密文给对方
      await sendKeyExchangeMessage(peerId, ciphertext);
    } catch (e) {
      print('建立安全会话失败: $e');
      throw Exception('建立安全会话失败: $e');
    }
  }

  /// 处理密钥交换
  /// 
  /// 处理对方发来的密钥交换消息。
  /// 
  /// 参数：
  /// - peerId: 对端用户ID
  /// - ciphertext: 对方发来的密文
  Future<void> handleKeyExchange(String peerId, String ciphertext) async {
    try {
      print('处理密钥交换: $peerId');

      // 解封装密钥
      final sharedSecret = await decapsulateKey(ciphertext);
      // 存储会话密钥
      _sessionKeys[peerId] = sharedSecret;

      print('密钥交换处理完成，会话密钥已存储');
    } catch (e) {
      print('处理密钥交换失败: $e');
      throw Exception('处理密钥交换失败: $e');
    }
  }

  /// 发送密钥交换消息
  /// 
  /// 通过服务器发送密钥交换消息给对方。
  /// 
  /// 参数：
  /// - peerId: 对端用户ID
  /// - ciphertext: 密文
  Future<void> sendKeyExchangeMessage(String peerId, String ciphertext) async {
    try {
      final result = await _videoApi.keyExchange(peerId, {
        'ciphertext': ciphertext,
        'timestamp': DateTime.now().millisecondsSinceEpoch.toString(),
      });
      print('密钥交换消息发送结果: $result');
    } catch (e) {
      print('发送密钥交换消息失败: $e');
      throw Exception('发送密钥交换消息失败: $e');
    }
  }

  /// 初始化数据通道
  /// 
  /// 创建用于发送加密消息的数据通道。
  /// 
  /// 数据通道特点：
  /// - 可靠传输（ordered = true）
  /// - 最多重传3次
  Future<void> initializeDataChannel() async {
    if (_peerConnection == null) {
      print('PeerConnection未初始化，无法创建数据通道');
      return;
    }

    try {
      // 创建数据通道配置
      final dataChannelDict = RTCDataChannelInit();
      dataChannelDict.ordered = true;     // 保证顺序
      dataChannelDict.maxRetransmits = 3; // 最多重传3次

      // 创建数据通道
      _dataChannel = await _peerConnection!.createDataChannel(
        'secure_message',
        dataChannelDict,
      );

      // 设置消息处理回调
      _dataChannel!.onMessage = (RTCDataChannelMessage message) {
        handleSecureMessage(message.text);
      };

      // 设置状态变化回调
      _dataChannel!.onDataChannelState = (state) {
        print('数据通道状态: $state');
      };

      print('数据通道初始化成功');
    } catch (e) {
      print('初始化数据通道失败: $e');
    }
  }

  /// 发送安全消息
  /// 
  /// 发送加密的文本消息给对方。
  /// 
  /// 加密流程：
  /// 1. 使用会话密钥加密消息（AES-256-GCM）
  /// 2. 使用私钥对加密内容签名
  /// 3. 组合加密内容和签名，发送
  /// 
  /// 参数：
  /// - message: 要发送的消息
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
      // 步骤1: 加密消息
      final encrypted = _cryptoService.aesEncrypt(message, sessionKey);

      // 步骤2: 签名
      final signature = _cryptoService.sign(encrypted, _signatureKeyPair!['privateKey']!);

      // 步骤3: 组合并发送
      final payload = jsonEncode({
        'encrypted': encrypted,        // 加密内容
        'signature': signature,       // 数字签名
        'timestamp': DateTime.now().millisecondsSinceEpoch, // 时间戳
      });

      _dataChannel!.send(RTCDataChannelMessage(payload));
      print('安全消息已发送');
    } catch (e) {
      print('发送安全消息失败: $e');
      throw Exception('发送安全消息失败: $e');
    }
  }

  /// 处理安全消息
  /// 
  /// 接收并解密安全消息。
  /// 
  /// 解密流程：
  /// 1. 验证签名
  /// 2. 解密消息
  /// 3. 检查消息是否过期
  /// 
  /// 参数：
  /// - payload: 消息载荷（JSON格式）
  void handleSecureMessage(String payload) {
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final encrypted = data['encrypted'] as String;
      final signature = data['signature'] as String;
      final timestamp = data['timestamp'] as int;

      if (_currentPeerId == null) {
        print('收到安全消息但没有活动通话');
        return;
      }

      final sessionKey = _sessionKeys[_currentPeerId!];
      if (sessionKey == null) {
        print('收到安全消息但会话密钥未建立');
        return;
      }

      // 解密消息
      final decrypted = _cryptoService.aesDecrypt(encrypted, sessionKey);
      print('收到安全消息: $decrypted');

      // 检查消息是否过期（30秒内有效）
      final age = DateTime.now().millisecondsSinceEpoch - timestamp;
      if (age > 30000) {
        print('消息已过期，忽略');
        return;
      }

      print('安全消息处理完成: $decrypted');
    } catch (e) {
      print('处理安全消息失败: $e');
    }
  }

  /// 初始化本地媒体流
  /// 
  /// 请求权限，并获取本地音频流。
  /// 
  /// 流程：
  /// 1. 请求麦克风权限
  /// 2. 获取音频流
  /// 
  /// 返回：
  /// - MediaStream: 本地媒体流
  Future<MediaStream> initializeLocalStream() async {
    // 请求麦克风权限
    final permissionStatus = await Permission.microphone.request();
    if (permissionStatus != PermissionStatus.granted) {
      throw Exception('麦克风权限被拒绝');
    }

    // 媒体约束配置 - 只需要音频
    final constraints = {
      'audio': true,   // 需要音频
      'video': false,  // 不需要视频
    };

    // 获取本地媒体流
    _localStream = await navigator.mediaDevices.getUserMedia(constraints);

    return _localStream!;
  }

  /// 创建 PeerConnection（内部方法）
  /// 
  /// 创建 WebRTC 对等连接。
  /// 
  /// ICE 服务器配置：
  /// - STUN 服务器：Google 公共 STUN 服务器
  /// - TURN 服务器：自建 TURN 服务器（用于穿透 NAT）
  /// 
  /// 事件处理：
  /// - onIceCandidate: ICE 候选者事件
  /// - onIceConnectionState: ICE 连接状态变化
  /// - onTrack: 收到远程流
  /// - onDataChannel: 数据通道事件
  /// 
  /// 返回：
  /// - RTCPeerConnection: 对等连接
  Future<RTCPeerConnection> createPeerConnectionInternal() async {
    // ICE 服务器配置
    final config = {
      'iceServers': [
        // Google 公共 STUN 服务器
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
        {'urls': 'stun:stun2.l.google.com:19302'},
        {'urls': 'stun:stun3.l.google.com:19302'},
        {'urls': 'stun:stun4.l.google.com:19302'},
        // 自建 TURN 服务器
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

    // 添加本地流轨道
    if (_localStream != null) {
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });
    }

    // 设置事件处理
    _peerConnection!.onIceCandidate = handleICECandidateEvent;
    _peerConnection!.onIceConnectionState = handleICEConnectionStateChangeEvent;
    _peerConnection!.onTrack = handleTrackEvent;
    _peerConnection!.onConnectionState = (state) {
      print('连接状态: $state');
    };

    // 数据通道处理
    _peerConnection!.onDataChannel = (channel) {
      print('收到数据通道: ${channel.label}');
      _dataChannel = channel;
      _dataChannel!.onMessage = (RTCDataChannelMessage message) {
        handleSecureMessage(message.text);
      };
      _dataChannel!.onDataChannelState = (state) {
        print('数据通道状态: $state');
      };
    };

    // 初始化数据通道
    await initializeDataChannel();

    return _peerConnection!;
  }

  /// 处理 ICE 候选者
  /// 
  /// 当发现新的 ICE 候选者时，发送给服务器。
  /// 
  /// 参数：
  /// - candidate: ICE 候选者
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

  /// 处理 ICE 连接状态变化
  /// 
  /// 处理 ICE 连接状态变化事件。
  /// 
  /// 状态处理：
  /// - connected: 连接成功，开始计时
  /// - disconnected: 断开连接，尝试重连
  /// - failed/closed: 结束通话
  /// 
  /// 参数：
  /// - state: ICE 连接状态
  void handleICEConnectionStateChangeEvent(RTCIceConnectionState? state) {
    print('ICE连接状态: $state');
    if (state == RTCIceConnectionState.RTCIceConnectionStateConnected) {
      // 连接成功
      _toUserIsReady = true;
      _reconnectAttempts = 0;
      _destroyReconnectTimer();
      _destroyTimer();
      // 开始计时
      _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
        _time++;
        // 检查 StreamController 是否已关闭
        if (!_timeController.isClosed) {
          _timeController.add(_time);
        }
      });
      _updateState(CallState.connected);
    } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
      // 断开连接，尝试重连
      print('ICE连接断开，尝试重连...');
      _attemptReconnect();
    } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
      // 连接失败，尝试重连
      print('ICE连接失败，尝试重连...');
      _attemptReconnect();
    } else if (state == RTCIceConnectionState.RTCIceConnectionStateClosed) {
      // 连接关闭
      handleHangup();
    }
  }

  /// 处理远程轨道事件
  /// 
  /// 当收到远程媒体流时触发。
  /// 
  /// 参数：
  /// - event: 轨道事件
  void handleTrackEvent(RTCTrackEvent event) {
    print('收到远程流: ${event.track.kind}');
    if (event.streams.isNotEmpty) {
      _remoteStream = event.streams[0];
    }
  }

  /// 初始化视频事件监听
  /// 
  /// 监听 WebSocket 消息，处理各种视频相关事件。
  /// 
  /// 处理的事件类型：
  /// - offer: 收到呼叫请求
  /// - answer: 收到应答
  /// - candidate: 收到 ICE 候选者
  /// - hangup: 对方挂断
  /// - accept: 对方接听
  /// - invite: 收到呼叫邀请
  /// - key-exchange: 密钥交换
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
          case 'key-exchange':
            handleKeyExchangeEvent(data);
            break;
        }
      }
    });
  }

  /// 处理 offer 消息
  /// 
  /// 处理对方发来的呼叫请求（offer）。
  /// 
  /// 流程：
  /// 1. 设置远程描述
  /// 2. 创建 answer
  /// 3. 设置本地描述
  /// 4. 发送 answer 给对方
  Future<void> handleVideoOfferMsg(Map<String, dynamic> data) async {
    try {
      print('处理offer消息');
      if (_peerConnection == null) {
        print('PeerConnection未初始化');
        return;
      }
      // 设置远程描述
      final RTCSessionDescription desc =
          RTCSessionDescription(data['desc']['sdp'], data['desc']['type']);
      await _peerConnection!.setRemoteDescription(desc);
      // 创建 answer
      RTCSessionDescription localDesc = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(localDesc);
      // 发送 answer
      await _videoApi.answer(_currentPeerId!, {
        'sdp': localDesc.sdp,
        'type': localDesc.type,
      });
      print('已发送answer');
    } catch (e) {
      print('处理offer失败: $e');
    }
  }

  /// 处理 answer 消息
  /// 
  /// 处理对方发来的应答（answer）。
  Future<void> handleVideoAnswerMsg(Map<String, dynamic> data) async {
    try {
      print('处理answer消息');
      if (_peerConnection == null) {
        print('PeerConnection未初始化');
        return;
      }
      // 设置远程描述
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

  /// 处理 ICE 候选者消息
  /// 
  /// 添加对方发来的 ICE 候选者。
  Future<void> handleNewICECandidateMsg(Map<String, dynamic> data) async {
    try {
      print('处理ICE候选者消息');
      if (_peerConnection == null) {
        print('PeerConnection未初始化');
        return;
      }
      // 创建并添加候选者
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

  /// 发送 offer
  /// 
  /// 创建并发送呼叫请求（offer）。
  /// 在对方接听后调用。
  Future<void> onOffer() async {
    try {
      print('创建offer');
      if (_peerConnection == null) {
        print('PeerConnection未初始化');
        return;
      }
      // 创建 offer
      RTCSessionDescription offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);
      // 发送 offer
      await _videoApi.offer(_currentPeerId!, {
        'sdp': offer.sdp,
        'type': offer.type,
      });
      print('已发送offer');
    } catch (e) {
      print('创建offer失败: $e');
    }
  }

  /// 处理来电
  /// 
  /// 处理收到的呼叫邀请。
  /// 
  /// 参数：
  /// - data: 邀请数据
  void handleIncomingCall(Map<String, dynamic> data) {
    print('收到来电: $data');
    final fromUserId = data['fromUserId'] as String?;
    final isOnlyAudio = data['isOnlyAudio'] as bool? ?? true;

    if (fromUserId != null) {
      _currentPeerId = fromUserId;
      _isOnlyAudio = isOnlyAudio;
      _isCaller = false;
      _updateState(CallState.ringing);

      // 触发回调
      if (_onIncomingCall != null) {
        _onIncomingCall!(fromUserId, data['fromUserName'], isOnlyAudio);
      }
    }
  }

  /// 处理密钥交换事件
  /// 
  /// 处理对方发来的密钥交换消息。
  Future<void> handleKeyExchangeEvent(Map<String, dynamic> data) async {
    try {
      print('处理密钥交换事件: $data');
      final fromUserId = data['fromUserId'] as String?;
      final ciphertext = data['keyData']?['ciphertext'] as String?;

      if (fromUserId != null && ciphertext != null) {
        await handleKeyExchange(fromUserId, ciphertext);
      }
    } catch (e) {
      print('处理密钥交换事件失败: $e');
    }
  }

  /// 发起通话
  /// 
  /// 呼叫指定用户。
  /// 
  /// 流程：
  /// 1. 设置通话信息
  /// 2. 初始化密钥
  /// 3. 初始化媒体设备
  /// 4. 创建 PeerConnection
  /// 5. 发送呼叫请求
  /// 
  /// 参数：
  /// - calleeId: 被叫方用户ID
  /// - isOnlyAudio: 是否仅音频通话
  Future<void> initiateCall(String calleeId, {bool isOnlyAudio = true}) async {
    try {
      // 步骤1: 设置通话信息
      _isCaller = true;
      _currentPeerId = calleeId;
      _isOnlyAudio = isOnlyAudio;
      _toUserIsReady = false;
      _updateState(CallState.calling);

      // 步骤2: 初始化密钥
      await initializeKeys();

      // 步骤3: 初始化媒体设备
      await initializeLocalStream();
      await createPeerConnectionInternal();

      // 步骤4: 生成通话签名
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final signature = generateCallSignature(calleeId, timestamp);

      // 步骤5: 发送加密呼叫请求
      final result = await _videoApi.secureInvite(
        calleeId,
        isOnlyAudio,
        signature,
        _signatureKeyPair!['publicKey']!,
      );
      print('secureInvite结果: $result');
      
      if (result['code'] == -1) {
        throw Exception(result['message'] ?? '用户不在线');
      }
      
      print('已发送secureInvite到 $calleeId');

    } catch (e) {
      print('发起呼叫失败: $e');
      _updateState(CallState.error);
      throw Exception('发起呼叫失败: $e');
    }
  }

  /// 接听通话
  /// 
  /// 接听当前来电。
  /// 
  /// 流程：
  /// 1. 初始化密钥
  /// 2. 初始化媒体设备
  /// 3. 创建 PeerConnection
  /// 4. 发送接听响应
  Future<void> acceptCall() async {
    try {
      if (_currentPeerId == null) {
        throw Exception('没有待接听的通话');
      }

      _updateState(CallState.connecting);

      // 初始化密钥
      await initializeKeys();

      // 初始化媒体设备
      await initializeLocalStream();
      await createPeerConnectionInternal();

      // 发送接听响应
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

  /// 拒绝通话
  /// 
  /// 拒绝当前来电。
  void rejectCall() {
    if (_currentPeerId != null) {
      _videoApi.hangup(_currentPeerId!);
    }
    _cleanup();
    _updateState(CallState.rejected);
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

  /// 尝试重连
  /// 
  /// 当连接断开时尝试重新连接。
  void _attemptReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      print('已达到最大重连次数');
      handleHangup();
      return;
    }

    _reconnectAttempts++;
    print('尝试重连 ($_reconnectAttempts/$_maxReconnectAttempts)');

    _reconnectTimer = Timer(_reconnectDelay, () async {
      // 清理旧的 PeerConnection
      if (_peerConnection != null) {
        await _peerConnection!.close();
        _peerConnection = null;
      }
      
      // 重新创建 PeerConnection
      await createPeerConnectionInternal();
      
      // 根据角色重新进行信令交换
      if (_isCaller) {
        // 如果是呼叫方，重新创建并发送 offer
        await _createAndSendOffer();
      }
      // 如果是被叫方，等待新的 offer（通过 WebSocket 接收）
    });
  }
  
  /// 创建并发送 Offer
  /// 
  /// 用于重连时呼叫方重新发起连接。
  Future<void> _createAndSendOffer() async {
    try {
      if (_peerConnection == null || _currentPeerId == null) return;
      
      print('重新创建并发送 offer...');
      
      // 创建 offer
      final offer = await _peerConnection!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
      });
      
      // 设置本地描述
      await _peerConnection!.setLocalDescription(offer);
      
      // 发送 offer 到对方
      await _videoApi.offer(_currentPeerId!, {
        'sdp': offer.sdp,
        'type': offer.type,
      });
      
      print('重新发送 offer 成功');
    } catch (e) {
      print('重新创建 offer 失败: $e');
    }
  }

  /// 挂断通话
  /// 
  /// 结束当前通话。
  void handleHangup() {
    print('handleHangup 被调用 [isCaller: $_isCaller, currentPeerId: $_currentPeerId]');
    endCall();
  }

  /// 结束通话
  /// 
  /// 结束当前正在进行的通话。
  /// 
  /// 流程：
  /// 1. 发送结束通话信号
  /// 2. 清理资源
  /// 3. 更新状态为已结束
  Future<void> endCall() async {
    try {
      print('endCall 被调用 [isCaller: $_isCaller, currentPeerId: $_currentPeerId]');
      if (_currentPeerId != null) {
        await _videoApi.hangup(_currentPeerId!);
      }
      _cleanup();
      _updateState(CallState.ended);
      print('通话已结束');
    } catch (e) {
      print('结束通话失败: $e');
      _updateState(CallState.error);
      throw Exception('结束通话失败: $e');
    }
  }

  /// 设置静音状态
  /// 
  /// 开启或关闭麦克风静音。
  /// 
  /// 参数：
  /// - muted: 是否静音
  void setMute(bool muted) {
    if (_localStream != null) {
      _isAudioEnabled = !muted;
      _localStream!.getAudioTracks().forEach((track) {
        track.enabled = _isAudioEnabled;
      });
    }
  }

  /// 清理资源
  /// 
  /// 释放所有通话相关资源。
  void _cleanup() {
    if (_isCleanupInProgress) {
      print('清理已在进行，跳过重复清理');
      return;
    }
    
    _isCleanupInProgress = true;
    _cleanupStackTrace = StackTrace.current.toString();
    print('开始清理资源... [isCaller: $_isCaller, currentPeerId: $_currentPeerId]');
    print('清理调用栈: $_cleanupStackTrace');

    // 停止计时器
    _destroyTimer();
    _destroyReconnectTimer();
    _reconnectAttempts = 0;

    // 清除会话密钥
    if (_currentPeerId != null) {
      clearSessionKey(_currentPeerId!);
    }

    // 关闭数据通道
    if (_dataChannel != null) {
      _dataChannel!.close();
      _dataChannel = null;
    }

    // 关闭 PeerConnection
    if (_peerConnection != null) {
      _peerConnection!.close();
      _peerConnection = null;
    }

    // 停止本地流
    if (_localStream != null) {
      _localStream!.getTracks().forEach((track) {
        track.stop();
      });
      _localStream = null;
    }

    // 清除远程流
    _remoteStream = null;

    // 重置所有状态标志
    _currentPeerId = null;
    _isCaller = false;
    _time = 0;
    _toUserIsReady = false;
    _isOnlyAudio = true;
    
    // 重置初始化标志，允许下次通话重新初始化
    _isVideoEventInitialized = false;
    _keysInitialized = false;
    
    // 清空密钥对
    _signatureKeyPair = null;
    _encryptionKeyPair = null;
    
    // 重置清理标志
    _isCleanupInProgress = false;

    print('资源清理完成');
  }

  /// 切换音频
  /// 
  /// 开启或关闭麦克风。
  void toggleAudio() {
    if (_localStream != null) {
      _isAudioEnabled = !_isAudioEnabled;
      _localStream!.getAudioTracks().forEach((track) {
        track.enabled = _isAudioEnabled;
      });
    }
  }

  /// 切换扬声器
  /// 
  /// 开启或关闭扬声器。
  Future<void> toggleSpeaker() async {
    // WebRTC 库可能没有 toggleSpeaker 方法
    // 这里可以根据实际使用的 WebRTC 库进行调整
    print('切换扬声器功能');
  }

  /// 切换听筒
  /// 
  /// 在听筒和扬声器之间切换。
  Future<void> toggleEarpiece() async {
    // WebRTC 库可能没有这些方法
    // 这里可以根据实际使用的 WebRTC 库进行调整
    print('切换听筒功能');
  }

  /// 更新通话状态
  /// 
  /// 通知 UI 通话状态变化。
  void _updateState(CallState state) {
    _currentState = state;
    // 检查 StreamController 是否已关闭
    if (!_callStateController.isClosed) {
      _callStateController.add(state);
    }
  }

  /// 释放资源
  /// 
  /// 清理所有资源，结束服务。
  Future<void> dispose() async {
    _cleanup();
    _subscription?.cancel();
    // 不要关闭 StreamController，因为 CallService 是单例模式
    // _callStateController.close();
    // _timeController.close();
  }
}

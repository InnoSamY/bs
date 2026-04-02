import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as io;

/// WebSocket 服务类（单例模式）
/// 
/// 提供实时通信功能，用于接收服务器推送的信令消息。
/// 
/// 主要功能：
/// 1. WebSocket 连接管理
/// 2. 心跳保活
/// 3. 自动重连
/// 4. 事件广播
/// 
/// 支持的事件：
/// - audio: 音频信令（来自 HTTP 路由的转发）
class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  io.Socket? _socket;
  String? _currentUserId;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  bool _isConnecting = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  static const Duration _initialReconnectDelay = Duration(seconds: 1);
  static const Duration _maxReconnectDelay = Duration(seconds: 10);

  final String _serverUrl = 'http://123.56.168.149:3000';

  bool get isConnected => _socket?.connected ?? false;

  /// 事件广播控制器
  /// 
  /// 用于向订阅者广播服务器推送的事件。
  static final eventController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get eventStream => eventController.stream;

  /// 连接到 WebSocket 服务器
  /// 
  /// 参数：
  /// - userId: 当前用户ID，用于注册
  Future<void> connect(String userId) async {
    _currentUserId = userId;

    if (_isConnecting) {
      print('WebSocket 正在连接中...');
      return;
    }

    if (_socket != null && _socket!.connected) {
      print('WebSocket 已连接');
      _socket!.emit('register', userId);
      return;
    }

    final completer = Completer<void>();

    try {
      _isConnecting = true;
      print('WebSocket connecting...');
      
      _socket = io.io(_serverUrl, <String, dynamic>{
        'transports': ['websocket', 'polling'],
        'autoConnect': true,
        'reconnect': true,
        'reconnectAttempts': 20,
        'reconnectDelay': 1000,
        'reconnectDelayMax': 10000,
        'timeout': 20000,
        'pingTimeout': 30000,
        'pingInterval': 25000,
        'upgrade': true,
        'rememberUpgrade': true,
      });

      _socket!.onConnect((_) {
        print('WebSocket 连接成功');
        _isConnecting = false;
        _reconnectAttempts = 0;
        _socket!.emit('register', userId);
        _startHeartbeat();
        eventController.add({'type': 'connection-status', 'connected': true});
        if (!completer.isCompleted) {
          completer.complete();
        }
      });

      _socket!.onDisconnect((_) {
        print('WebSocket 断开连接');
        _isConnecting = false;
        _stopHeartbeat();
        eventController.add({'type': 'connection-status', 'connected': false});
        _attemptReconnect();
      });

      _socket!.onConnectError((error) {
        print('WebSocket 连接错误: $error');
        _isConnecting = false;
        if (!completer.isCompleted) {
          completer.completeError('连接错误: $error');
        }
        _attemptReconnect();
      });

      _socket!.onError((error) {
        print('WebSocket错误: $error');
      });

      _socket!.on('audio', (data) {
        print('收到音频信令: $data');
        eventController.add({'type': 'on-receive-audio', 'content': data});
      });

      return completer.future.timeout(Duration(seconds: 10), onTimeout: () {
        if (!completer.isCompleted) {
          completer.complete();
        }
      });

    } catch (e) {
      print('WebSocket 初始化错误: $e');
      _isConnecting = false;
      throw Exception('WebSocket 连接失败: $e');
    }
  }

  /// 启动心跳定时器
  /// 
  /// 每 30 秒发送一次 ping 信号，保持连接活跃。
  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_socket != null && _socket!.connected) {
        _socket!.emit('ping', {'userId': _currentUserId});
      }
    });
  }

  /// 停止心跳定时器
  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// 尝试重连
  /// 
  /// 使用指数退避算法计算重连延迟时间。
  void _attemptReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      print('WebSocket 重连次数已达上限');
      return;
    }

    _reconnectAttempts++;
    final delay = _calculateReconnectDelay();
    print('WebSocket 尝试重连第 $_reconnectAttempts 次，延迟 ${delay.inSeconds} 秒');

    _reconnectTimer = Timer(delay, () {
      if (_currentUserId != null) {
        connect(_currentUserId!);
      }
    });
  }

  /// 计算重连延迟时间
  /// 
  /// 使用指数退避算法：1s, 2s, 4s, 8s, ...
  /// 最大延迟不超过 10 秒。
  Duration _calculateReconnectDelay() {
    final delay = Duration(
      milliseconds: (_initialReconnectDelay.inMilliseconds * 
                     (1 << _reconnectAttempts)).clamp(
                       _initialReconnectDelay.inMilliseconds, 
                       _maxReconnectDelay.inMilliseconds
                     )
    );
    return delay;
  }

  /// 断开连接
  void disconnect() {
    _stopHeartbeat();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _socket?.disconnect();
    _socket = null;
    _currentUserId = null;
    _isConnecting = false;
    _reconnectAttempts = 0;
  }

  /// 释放资源
  void dispose() {
    disconnect();
    if (!eventController.isClosed) {
      eventController.close();
    }
  }
}

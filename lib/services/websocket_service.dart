import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as io;

class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  io.Socket? _socket;
  String? _currentUserId;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  bool _isConnecting = false;

  final String _serverUrl = 'http://123.56.168.149:3000';

  bool get isConnected => _socket?.connected ?? false;

  static final eventController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get eventStream => eventController.stream;

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

    try {
      _isConnecting = true;
      print('WebSocket connecting...');
      
      _socket = io.io(_serverUrl, <String, dynamic>{
        'transports': ['websocket', 'polling'],
        'autoConnect': true,
        'reconnect': true,
        'reconnectAttempts': 10,
        'reconnectDelay': 1000,
        'reconnectDelayMax': 5000,
      });

      _socket!.onConnect((_) {
        print('WebSocket 连接成功');
        _isConnecting = false;
        _socket!.emit('register', userId);
        _startHeartbeat();
      });

      _socket!.onDisconnect((_) {
        print('WebSocket 断开连接');
        _isConnecting = false;
        _stopHeartbeat();
      });

      _socket!.onConnectError((error) {
        print('WebSocket 连接错误: $error');
        _isConnecting = false;
      });

      _socket!.onError((error) {
        print('WebSocket错误: $error');
      });

      _socket!.on('video', (data) {
        print('收到视频信令: $data');
        eventController.add({'type': 'on-receive-video', 'content': data});
      });

      _socket!.on('incoming-call', (data) {
        print('收到来电: $data');
        eventController.add({'type': 'on-receive-video', 'content': {
          'type': 'invite',
          'fromUserId': data['callerId'],
          'callType': data['callType'],
        }});
      });

      _socket!.on('call-accepted', (data) {
        print('通话被接受: $data');
        eventController.add({'type': 'on-receive-video', 'content': {
          'type': 'accept',
          'answer': data['answer'],
        }});
      });

      _socket!.on('call-rejected', (data) {
        print('通话被拒绝: $data');
        eventController.add({'type': 'on-receive-video', 'content': {
          'type': 'hangup',
          'reason': data['reason'],
        }});
      });

      _socket!.on('call-ended', (data) {
        print('通话结束: $data');
        eventController.add({'type': 'on-receive-video', 'content': {
          'type': 'hangup',
        }});
      });

      _socket!.on('ice-candidate', (data) {
        print('收到ICE候选者: $data');
        eventController.add({'type': 'on-receive-video', 'content': {
          'type': 'candidate',
          'candidate': data['candidate'],
        }});
      });

    } catch (e) {
      print('WebSocket 初始化错误: $e');
      _isConnecting = false;
      throw Exception('WebSocket 连接失败: $e');
    }
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_socket != null && _socket!.connected) {
        _socket!.emit('ping', {'userId': _currentUserId});
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void disconnect() {
    _stopHeartbeat();
    _socket?.disconnect();
    _socket = null;
    _currentUserId = null;
    _isConnecting = false;
  }

  void dispose() {
    disconnect();
    if (!eventController.isClosed) {
      eventController.close();
    }
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_base/screens/contacts_screen.dart';
import 'package:flutter_base/services/call_service.dart';
import 'package:flutter_base/services/websocket_service.dart';

// 通话类型
enum CallType {
  outgoing, // 呼出
  incoming, // 呼入
}

class CallScreen extends StatefulWidget {
  final Contact contact;
  final CallType callType;
  final Map<String, dynamic>? offerData; // 来电时的offer数据

  CallScreen({
    required this.contact,
    this.callType = CallType.outgoing,
    this.offerData,
  });

  @override
  _CallScreenState createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _callService = CallService();
  int _callDuration = 0;
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  Timer? _callTimer;
  String _statusText = '';
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _initializeCall();
  }

  Future<void> _initializeCall() async {
    // 更新 WebSocket 回调到当前 CallService 实例
    final webSocketService = WebSocketService();
    webSocketService.updateCallbacks(CallEventCallbacks(
      onCallAccepted: (data) {
        if (data != null) {
          _callService.handleCallAccepted(data);
        }
      },
      onCallRejected: (reason) {
        _callService.handleCallRejected(reason);
      },
      onIceCandidate: (candidate) {
        _callService.handleIceCandidate(candidate);
      },
      onCallEnded: () {
        _callService.endCall();
      },
      onError: (error) {
        print('通话错误: $error');
      },
    ));

    // 监听通话状态变化
    _callService.callStateStream.listen((state) {
      if (!mounted) return;

      setState(() {
        switch (state) {
          case CallState.calling:
            _statusText = '正在呼叫...';
            _isConnecting = true;
            break;
          case CallState.ringing:
            _statusText = '来电响铃';
            _isConnecting = false;
            break;
          case CallState.connecting:
            _statusText = '正在连接...';
            _isConnecting = true;
            break;
          case CallState.connected:
            _statusText = '通话中';
            _isConnecting = false;
            _startCallTimer();
            break;
          case CallState.ended:
            _statusText = '通话结束';
            _stopCallTimer();
            _closeScreen();
            break;
          case CallState.rejected:
            _statusText = '对方拒绝接听';
            _isConnecting = false;
            _stopCallTimer();
            Future.delayed(Duration(seconds: 2), _closeScreen);
            break;
          case CallState.error:
            _statusText = '通话错误';
            _isConnecting = false;
            _stopCallTimer();
            Future.delayed(Duration(seconds: 2), _closeScreen);
            break;
          default:
            break;
        }
      });
    });

    try {
      if (widget.callType == CallType.outgoing) {
        // 发起呼叫
        await _callService.initiateCall(widget.contact.id);
      } else {
        // 处理来电
        if (widget.offerData != null) {
          await _callService.handleIncomingCall(
            widget.contact.id,
            widget.offerData!,
          );
        }
      }
    } catch (e) {
      print('初始化通话失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('通话初始化失败: $e')),
        );
        Navigator.pop(context);
      }
    }
  }

  void _startCallTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _callDuration++;
        });
      }
    });
  }

  void _stopCallTimer() {
    _callTimer?.cancel();
    _callTimer = null;
  }

  Future<void> _acceptCall() async {
    try {
      await _callService.acceptCall();
    } catch (e) {
      print('接受通话失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('接受通话失败: $e')),
        );
      }
    }
  }

  void _rejectCall() {
    _callService.rejectCall();
    Navigator.pop(context);
  }

  Future<void> _endCall() async {
    _stopCallTimer();
    await _callService.endCall();
    Navigator.pop(context);
  }

  void _closeScreen() {
    if (mounted) {
      Future.delayed(Duration(seconds: 1), () {
        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      });
    }
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
    });
    _callService.setMute(_isMuted);
  }

  void _toggleSpeaker() {
    setState(() {
      _isSpeakerOn = !_isSpeakerOn;
    });
    // TODO: 实现扬声器切换
  }

  String _formatDuration(int seconds) {
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _stopCallTimer();
    _callService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isIncoming = widget.callType == CallType.incoming;
    final isRinging = _callService.currentState == CallState.ringing;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isIncoming && isRinging
                ? [Colors.orange[700]!, Colors.orange[900]!]
                : [Colors.blue[800]!, Colors.blue[900]!],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(height: 60),
              // 头像
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: 57,
                  backgroundColor: isIncoming && isRinging
                      ? Colors.orange[600]
                      : Colors.blue[700],
                  child: Text(
                    widget.contact.username[0],
                    style: TextStyle(fontSize: 50, color: Colors.white),
                  ),
                ),
              ),
              SizedBox(height: 30),
              // 用户名
              Text(
                widget.contact.username,
                style: TextStyle(
                  fontSize: 28,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 10),
              // 状态文字
              Text(
                _statusText,
                style: TextStyle(fontSize: 18, color: Colors.white70),
              ),
              // 通话时长
              if (_callService.currentState == CallState.connected)
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Text(
                    _formatDuration(_callDuration),
                    style: TextStyle(
                      fontSize: 48,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              // 连接动画
              if (_isConnecting)
                Padding(
                  padding: const EdgeInsets.all(30.0),
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 3,
                  ),
                ),
              Spacer(),
              // 按钮区域
              if (isIncoming && isRinging)
                // 来电接听/拒绝按钮
                _buildIncomingCallButtons()
              else
                // 通话中按钮
                _buildActiveCallButtons(),
              SizedBox(height: 60),
            ],
          ),
        ),
      ),
    );
  }

  // 来电时的接听/拒绝按钮
  Widget _buildIncomingCallButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 拒绝按钮
        Column(
          children: [
            GestureDetector(
              onTap: _rejectCall,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.5),
                      blurRadius: 15,
                      spreadRadius: 3,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.call_end,
                  size: 40,
                  color: Colors.white,
                ),
              ),
            ),
            SizedBox(height: 12),
            Text(
              '拒绝',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
          ],
        ),
        SizedBox(width: 80),
        // 接听按钮
        Column(
          children: [
            GestureDetector(
              onTap: _acceptCall,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.green,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.withOpacity(0.5),
                      blurRadius: 15,
                      spreadRadius: 3,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.call,
                  size: 40,
                  color: Colors.white,
                ),
              ),
            ),
            SizedBox(height: 12),
            Text(
              '接听',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // 通话中的按钮（静音、挂断、扬声器）
  Widget _buildActiveCallButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 静音按钮
        Column(
          children: [
            GestureDetector(
              onTap: _toggleMute,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isMuted
                      ? Colors.blue[600]
                      : Colors.white.withOpacity(0.2),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Icon(
                  _isMuted ? Icons.mic_off : Icons.mic,
                  size: 30,
                  color: Colors.white,
                ),
              ),
            ),
            SizedBox(height: 8),
            Text(
              _isMuted ? '静音中' : '静音',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
            ),
          ],
        ),
        SizedBox(width: 40),
        // 挂断按钮
        Column(
          children: [
            GestureDetector(
              onTap: _endCall,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.5),
                      blurRadius: 15,
                      spreadRadius: 3,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.call_end,
                  size: 40,
                  color: Colors.white,
                ),
              ),
            ),
            SizedBox(height: 8),
            Text(
              '挂断',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
            ),
          ],
        ),
        SizedBox(width: 40),
        // 扬声器按钮
        Column(
          children: [
            GestureDetector(
              onTap: _toggleSpeaker,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isSpeakerOn
                      ? Colors.blue[600]
                      : Colors.white.withOpacity(0.2),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Icon(
                  _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
                  size: 30,
                  color: Colors.white,
                ),
              ),
            ),
            SizedBox(height: 8),
            Text(
              _isSpeakerOn ? '扬声器' : '听筒',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

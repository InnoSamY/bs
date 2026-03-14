import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_base/screens/contacts_screen.dart';
import 'package:flutter_base/services/call_service.dart';
import 'package:flutter_base/services/websocket_service.dart';

/// 通话类型枚举
/// 
/// 表示通话的方向。
enum CallType {
  outgoing,  // 外呼通话
  incoming,  // 来电
}

/// 通话界面
/// 
/// 显示通话界面，包括：
/// - 对方头像和用户名
/// - 通话状态
/// - 通话时长
/// - 操作按钮（静音、扬声器、挂断、接听、拒绝）
class CallScreen extends StatefulWidget {
  final Contact contact;
  final CallType callType;

  CallScreen({
    required this.contact,
    this.callType = CallType.outgoing,
  });

  @override
  _CallScreenState createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _callService = CallService();
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  String _statusText = '';

  @override
  void initState() {
    super.initState();
    _initializeCall();
  }

  /// 初始化通话
  /// 
  /// 设置通话状态监听，发起或接听通话。
  Future<void> _initializeCall() async {
    _callService.videoEvent();

    _callService.callStateStream.listen((state) {
      if (!mounted) return;

      setState(() {
        switch (state) {
          case CallState.calling:
            _statusText = '正在呼叫...';
            break;
          case CallState.ringing:
            _statusText = '来电响铃';
            break;
          case CallState.connecting:
            _statusText = '正在连接...';
            break;
          case CallState.connected:
            _statusText = '通话中';
            break;
          case CallState.ended:
            _statusText = '通话结束';
            _closeScreen();
            break;
          case CallState.rejected:
            _statusText = '对方拒绝接听';
            Future.delayed(Duration(seconds: 2), _closeScreen);
            break;
          case CallState.error:
            _statusText = '通话错误';
            Future.delayed(Duration(seconds: 2), _closeScreen);
            break;
          default:
            break;
        }
      });
    });

    try {
      if (widget.callType == CallType.outgoing) {
        await _callService.initiateCall(widget.contact.id, isOnlyAudio: true);
      } else {
        setState(() {
          _statusText = '来电响铃';
        });
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

  /// 接听来电
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

  /// 拒绝来电
  void _rejectCall() {
    _callService.rejectCall();
    Navigator.pop(context);
  }

  /// 结束通话
  Future<void> _endCall() async {
    await _callService.endCall();
    if (mounted) {
      Navigator.pop(context);
    }
  }

  /// 关闭界面
  void _closeScreen() {
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  /// 切换静音状态
  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
    });
    _callService.setMute(_isMuted);
  }

  /// 切换扬声器状态
  void _toggleSpeaker() {
    setState(() {
      _isSpeakerOn = !_isSpeakerOn;
    });
  }

  /// 格式化通话时长
  /// 
  /// 将秒数转换为 mm:ss 格式。
  String _formatDuration(int seconds) {
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    // 不要调用 _callService.dispose()，因为 CallService 是单例模式
    // 应该在应用退出时才调用 dispose()
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
              Text(
                widget.contact.username,
                style: TextStyle(
                  fontSize: 28,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 10),
              Text(
                _statusText,
                style: TextStyle(fontSize: 18, color: Colors.white70),
              ),
              if (_callService.currentState == CallState.connected)
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: StreamBuilder<int>(
                    stream: _callService.timeStream,
                    builder: (context, snapshot) {
                      return Text(
                        _formatDuration(snapshot.data ?? 0),
                        style: TextStyle(
                          fontSize: 48,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    },
                  ),
                ),
              if (_callService.currentState == CallState.calling ||
                  _callService.currentState == CallState.connecting)
                Padding(
                  padding: const EdgeInsets.all(30.0),
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 3,
                  ),
                ),
              Spacer(),
              if (isIncoming && isRinging)
                _buildIncomingCallButtons()
              else
                _buildActiveCallButtons(),
              SizedBox(height: 60),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建来电按钮
  /// 
  /// 包含拒绝和接听两个按钮。
  Widget _buildIncomingCallButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
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
                child: Icon(Icons.call_end, size: 40, color: Colors.white),
              ),
            ),
            SizedBox(height: 12),
            Text('拒绝', style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        SizedBox(width: 80),
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
                child: Icon(Icons.call, size: 40, color: Colors.white),
              ),
            ),
            SizedBox(height: 12),
            Text('接听', style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
      ],
    );
  }

  /// 构建通话中按钮
  /// 
  /// 包含静音、挂断、扬声器三个按钮。
  Widget _buildActiveCallButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
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
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
        SizedBox(width: 40),
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
                child: Icon(Icons.call_end, size: 40, color: Colors.white),
              ),
            ),
            SizedBox(height: 8),
            Text('挂断', style: TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
        SizedBox(width: 40),
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
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }
}

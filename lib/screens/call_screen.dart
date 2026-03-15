import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_base/screens/contacts_screen.dart';
import 'package:flutter_base/services/call_service.dart';
import 'package:flutter_base/services/websocket_service.dart';

enum CallType {
  outgoing,
  incoming,
}

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
    await _callService.endCall();
    if (mounted) {
      Navigator.pop(context);
    }
  }

  void _closeScreen() {
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
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
  }

  String _formatDuration(int seconds) {
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isIncoming = widget.callType == CallType.incoming;
    final isRinging = _callService.currentState == CallState.ringing;

    return Scaffold(
      backgroundColor: Colors.grey[900],
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(height: 60),
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.grey[800],
                border: Border.all(color: Colors.grey[700]!, width: 2),
              ),
              child: Center(
                child: Text(
                  widget.contact.username[0].toUpperCase(),
                  style: TextStyle(fontSize: 42, color: Colors.white, fontWeight: FontWeight.w300),
                ),
              ),
            ),
            SizedBox(height: 24),
            Text(
              widget.contact.username,
              style: TextStyle(
                fontSize: 26,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 8),
            Text(
              _statusText,
              style: TextStyle(fontSize: 16, color: Colors.grey[400]),
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
                        fontSize: 42,
                        color: Colors.white,
                        fontWeight: FontWeight.w300,
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
                  color: Colors.grey[500],
                  strokeWidth: 2,
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
    );
  }

  Widget _buildIncomingCallButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Column(
          children: [
            GestureDetector(
              onTap: _rejectCall,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red[400],
                ),
                child: Icon(Icons.call_end, size: 32, color: Colors.white),
              ),
            ),
            SizedBox(height: 12),
            Text('拒绝', style: TextStyle(color: Colors.grey[400], fontSize: 14)),
          ],
        ),
        SizedBox(width: 72),
        Column(
          children: [
            GestureDetector(
              onTap: _acceptCall,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.green[400],
                ),
                child: Icon(Icons.call, size: 32, color: Colors.white),
              ),
            ),
            SizedBox(height: 12),
            Text('接听', style: TextStyle(color: Colors.grey[400], fontSize: 14)),
          ],
        ),
      ],
    );
  }

  Widget _buildActiveCallButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Column(
          children: [
            GestureDetector(
              onTap: _toggleMute,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isMuted ? Colors.grey[600] : Colors.grey[800],
                  border: Border.all(color: Colors.grey[700]!),
                ),
                child: Icon(
                  _isMuted ? Icons.mic_off : Icons.mic,
                  size: 24,
                  color: Colors.white,
                ),
              ),
            ),
            SizedBox(height: 8),
            Text(
              _isMuted ? '静音中' : '静音',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
          ],
        ),
        SizedBox(width: 32),
        Column(
          children: [
            GestureDetector(
              onTap: _endCall,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red[400],
                ),
                child: Icon(Icons.call_end, size: 32, color: Colors.white),
              ),
            ),
            SizedBox(height: 8),
            Text('挂断', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
          ],
        ),
        SizedBox(width: 32),
        Column(
          children: [
            GestureDetector(
              onTap: _toggleSpeaker,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isSpeakerOn ? Colors.grey[600] : Colors.grey[800],
                  border: Border.all(color: Colors.grey[700]!),
                ),
                child: Icon(
                  _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
                  size: 24,
                  color: Colors.white,
                ),
              ),
            ),
            SizedBox(height: 8),
            Text(
              _isSpeakerOn ? '扬声器' : '听筒',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }
}

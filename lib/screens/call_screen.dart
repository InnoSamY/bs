import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_base/screens/contacts_screen.dart';
import 'package:flutter_base/services/call_service.dart';
import 'package:flutter_base/services/websocket_service.dart';
import 'package:flutter_base/services/contact_service.dart';

/// 通话类型枚举
enum CallType {
  /// 呼出（主动发起通话）
  outgoing,

  /// 呼入（接听来电）
  incoming,
}

/// 通话界面
///
/// 提供完整的语音通话功能：
/// - 发起/接听通话
/// - 显示通话状态
/// - 静音/取消静音
/// - 挂断通话
///
/// 安全特性：
/// - 使用 ML-KEM 进行密钥交换
/// - 使用数字签名验证身份
/// - 端到端加密通话
class CallScreen extends StatefulWidget {
  final Contact contact;
  final CallType callType;
  
  // 来电时需要的额外数据
  final String? kemCiphertext;
  final String? signature;
  final String? callerSigPublicKey;
  final String? timestamp;
  final Map<String, dynamic>? offer;

  CallScreen({
    required this.contact,
    this.callType = CallType.outgoing,
    this.kemCiphertext,
    this.signature,
    this.callerSigPublicKey,
    this.timestamp,
    this.offer,
  });

  @override
  _CallScreenState createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _callService = CallService();
  final _contactService = ContactService();
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  String _statusText = '';
  bool _isRejecting = false;

  @override
  void initState() {
    super.initState();
    _initializeCall();
  }

  Future<void> _initializeCall() async {
    _callService.audioEvent();

    _callService.callStateStream.listen((state) {
      if (!mounted) {
        return;
      }

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
            Future.delayed(Duration(seconds: 2), _closeScreen);
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
        // 发起通话 - 需要对方的公钥
        if (widget.contact.kemPublicKey == null || widget.contact.sigPublicKey == null) {
          // 尝试从服务器获取联系人详情
          final contactDetail = await _contactService.getContactDetail(widget.contact.id);
          if (contactDetail == null || 
              contactDetail.kemPublicKey == null || 
              contactDetail.sigPublicKey == null) {
            throw Exception('联系人公钥信息不完整，无法建立安全通话');
          }
          
          await _callService.initiateCall(
            widget.contact.id,
            contactDetail.kemPublicKey!,
            contactDetail.sigPublicKey!,
            isOnlyAudio: true,
          );
        } else {
          await _callService.initiateCall(
            widget.contact.id,
            widget.contact.kemPublicKey!,
            widget.contact.sigPublicKey!,
            isOnlyAudio: true,
          );
        }
      } else {
        setState(() {
          _statusText = '来电响铃';
        });
      }
    } catch (e) {
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
      // 来电时需要验证签名
      if (widget.kemCiphertext == null || 
          widget.signature == null || 
          widget.callerSigPublicKey == null ||
          widget.timestamp == null ||
          widget.offer == null) {
        throw Exception('来电信息不完整，无法验证安全通话');
      }

      await _callService.acceptCall(
        widget.contact.id,
        widget.callerSigPublicKey!,
        widget.kemCiphertext!,
        widget.offer!,
        widget.timestamp!,
        widget.signature!,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('接受通话失败: $e')),
        );
      }
    }
  }

  Future<void> _rejectCall() async {
    // 防止重复调用 - 立即设置标志，不依赖 setState
    if (_isRejecting) {
      return;
    }
    
    // 立即设置标志（同步）
    _isRejecting = true;
    
    // 立即更新 UI
    setState(() {});
    
    try {
      await _callService.rejectCall();
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      // 失败时重置标志并更新 UI
      _isRejecting = false;
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _endCall() async {
    await _callService.endCall();
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
                image: widget.contact.avatar.isNotEmpty
                    ? DecorationImage(
                        image: MemoryImage(base64Decode(widget.contact.avatar)),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: widget.contact.avatar.isEmpty
                  ? Center(
                      child: Text(
                        widget.contact.username[0].toUpperCase(),
                        style: TextStyle(fontSize: 42, color: Colors.white, fontWeight: FontWeight.w300),
                      ),
                    )
                  : null,
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
              onTap: _isRejecting ? null : _rejectCall,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isRejecting ? Colors.grey[500] : Colors.red[400],
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
                  size: 28,
                  color: Colors.white,
                ),
              ),
            ),
            SizedBox(height: 8),
            Text(
              _isMuted ? '静音中' : '静音',
              style: TextStyle(color: Colors.grey[400], fontSize: 12),
            ),
          ],
        ),
        SizedBox(width: 40),
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
            Text('挂断', style: TextStyle(color: Colors.grey[400], fontSize: 14)),
          ],
        ),
        SizedBox(width: 40),
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
                  size: 28,
                  color: Colors.white,
                ),
              ),
            ),
            SizedBox(height: 8),
            Text(
              _isSpeakerOn ? '扬声器' : '听筒',
              style: TextStyle(color: Colors.grey[400], fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }
}

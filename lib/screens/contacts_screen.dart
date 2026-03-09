import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_base/services/auth_service.dart';
import 'package:flutter_base/services/contact_service.dart';
import 'package:flutter_base/services/websocket_service.dart';
import 'package:flutter_base/services/call_service.dart';
import 'package:flutter_base/screens/add_contact_screen.dart';
import 'package:flutter_base/screens/call_screen.dart';
import 'package:flutter_base/screens/contact_requests_screen.dart';

class Contact {
  final String id;
  final String username;
  final String avatar;
  final String bio;
  final bool isOnline;

  Contact({
    required this.id,
    required this.username,
    required this.avatar,
    required this.bio,
    this.isOnline = false,
  });
}

class ContactsScreen extends StatefulWidget {
  @override
  _ContactsScreenState createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final _authService = AuthService();
  final _contactService = ContactService();
  final _webSocketService = WebSocketService();
  final _callService = CallService();

  List<Contact> _contacts = [];
  bool _isLoading = false;
  String? _currentUserId;
  String? _currentUsername;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _loadCurrentUser();
    await _loadContacts();
    await _connectWebSocket();
  }

  Future<void> _loadCurrentUser() async {
    final user = await _authService.getCurrentUser();
    if (user != null) {
      setState(() {
        _currentUserId = user.id;
        _currentUsername = user.username;
      });
    }
  }

  Future<void> _connectWebSocket() async {
    if (_currentUserId == null) return;

    try {
      await _webSocketService.connect(
        _currentUserId!,
        callbacks: CallEventCallbacks(
          onIncomingCall: _handleIncomingCall,
          onCallAccepted: _handleCallAccepted,
          onCallRejected: _handleCallRejected,
          onIceCandidate: _handleIceCandidate,
          onCallEnded: _handleCallEnded,
          onError: _handleCallError,
        ),
      );
      print('WebSocket 连接成功');
    } catch (e) {
      print('WebSocket 连接失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('实时通信连接失败，请检查网络')),
        );
      }
    }
  }

  // 处理来电
  void _handleIncomingCall(Map<String, dynamic> data) async {
    final callerId = data['callerId'] as String?;
    final offer = data['offer'] as Map<String, dynamic>?;

    if (callerId == null || offer == null) return;

    // 查找联系人信息
    final contact = _contacts.firstWhere(
      (c) => c.id == callerId,
      orElse: () => Contact(
        id: callerId,
        username: '未知用户',
        avatar: '',
        bio: '',
      ),
    );

    if (mounted) {
      // 显示来电界面
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CallScreen(
            contact: contact,
            callType: CallType.incoming,
            offerData: offer,
          ),
        ),
      );
    }
  }

  // 处理对方接受通话
  void _handleCallAccepted(dynamic data) {
    // 由 CallScreen 处理
    print('对方接受通话: $data');
  }

  // 处理对方拒绝通话
  void _handleCallRejected(String reason) {
    _callService.handleCallRejected(reason);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('对方拒绝接听: $reason')),
      );
    }
  }

  // 处理ICE候选者
  void _handleIceCandidate(RTCIceCandidate candidate) {
    _callService.handleIceCandidate(candidate);
  }

  // 处理通话结束
  void _handleCallEnded() {
    print('通话结束');
  }

  // 处理通话错误
  void _handleCallError(String error) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('通话错误: $error')),
      );
    }
  }

  Future<void> _loadContacts() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 获取当前用户
      final user = await _authService.getCurrentUser();
      if (user != null) {
        // 调用API获取联系人列表
        _contacts = await _contactService.getContacts();
      }
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('获取联系人列表失败: $error')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _logout() async {
    _webSocketService.disconnect();
    await _authService.logout();
    Navigator.pushReplacementNamed(context, '/login');
  }

  void _startCall(Contact contact) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CallScreen(
          contact: contact,
          callType: CallType.outgoing,
        ),
      ),
    );
  }

  void _deleteContact(Contact contact) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除联系人'),
        content: Text('确定要删除 ${contact.username} 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                // 调用API删除联系人
                final user = await _authService.getCurrentUser();
                if (user != null) {
                  await _contactService.deleteContact(
                    contactId: contact.id,
                  );
                  _loadContacts();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('联系人删除成功')),
                  );
                }
              } catch (error) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('删除联系人失败')),
                );
              }
            },
            child: Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showMyId() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('我的ID'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('您的用户ID：'),
            SizedBox(height: 10),
            Container(
              padding: EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue),
              ),
              child: SelectableText(
                _currentUserId ?? '未知',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            SizedBox(height: 10),
            Text(
              '分享此ID给好友，让他们添加您为联系人',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _webSocketService.disconnect();
    _callService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('联系人'),
        backgroundColor: Colors.blue[600],
        actions: [
          // 连接状态指示器
          Container(
            margin: EdgeInsets.only(right: 8),
            child: Center(
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _webSocketService.isConnected ? Colors.green : Colors.red,
                ),
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.person_add_alt_1, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => ContactRequestsScreen()),
              );
            },
            tooltip: '联系人请求',
          ),
          IconButton(
            icon: Icon(Icons.person, color: Colors.white),
            onPressed: _showMyId,
            tooltip: '我的ID',
          ),
          IconButton(
            icon: Icon(Icons.logout, color: Colors.white),
            onPressed: _logout,
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: Colors.blue))
          : RefreshIndicator(
              onRefresh: _loadContacts,
              child: _contacts.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.contacts,
                            size: 80,
                            color: Colors.grey[300],
                          ),
                          SizedBox(height: 16),
                          Text(
                            '暂无联系人',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            '点击右下角按钮添加联系人',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[400],
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.all(10),
                      itemCount: _contacts.length,
                      itemBuilder: (context, index) {
                        final contact = _contacts[index];
                        return Card(
                          elevation: 3,
                          margin: EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            leading: Stack(
                              children: [
                                CircleAvatar(
                                  radius: 30,
                                  backgroundColor: Colors.blue[100],
                                  child: Text(
                                    contact.username[0],
                                    style: TextStyle(
                                      fontSize: 18,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: contact.isOnline
                                          ? Colors.green
                                          : Colors.grey,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            title: Text(
                              contact.username,
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(contact.bio),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  margin: EdgeInsets.only(right: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.green[100],
                                    shape: BoxShape.circle,
                                  ),
                                  child: IconButton(
                                    icon: Icon(Icons.call, color: Colors.green),
                                    onPressed: () => _startCall(contact),
                                  ),
                                ),
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.red[100],
                                    shape: BoxShape.circle,
                                  ),
                                  child: IconButton(
                                    icon: Icon(Icons.delete, color: Colors.red),
                                    onPressed: () => _deleteContact(contact),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => AddContactScreen()),
          );
        },
        child: Icon(Icons.add),
        backgroundColor: Colors.blue[600],
        elevation: 5,
      ),
    );
  }
}

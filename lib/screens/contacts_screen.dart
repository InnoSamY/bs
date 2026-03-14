import 'package:flutter/material.dart';
import 'package:flutter_base/services/auth_service.dart';
import 'package:flutter_base/services/contact_service.dart';
import 'package:flutter_base/services/websocket_service.dart';
import 'package:flutter_base/services/call_service.dart';
import 'package:flutter_base/screens/add_contact_screen.dart';
import 'package:flutter_base/screens/call_screen.dart';
import 'package:flutter_base/screens/contact_requests_screen.dart';

/// 联系人模型类
/// 
/// 表示一个联系人实体，包含联系人的基本信息。
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

/// 联系人列表界面
/// 
/// 显示用户的联系人列表，提供以下功能：
/// 1. 查看联系人列表
/// 2. 发起语音通话
/// 3. 删除联系人
/// 4. 查看我的用户ID
/// 5. 退出登录
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

  /// 初始化界面
  /// 
  /// 加载当前用户信息、联系人列表，并建立 WebSocket 连接。
  Future<void> _initialize() async {
    await _loadCurrentUser();
    await _loadContacts();
    await _connectWebSocket();
  }

  /// 加载当前用户信息
  /// 
  /// 从本地存储获取当前登录的用户信息。
  Future<void> _loadCurrentUser() async {
    final user = await _authService.getCurrentUser();
    if (user != null) {
      setState(() {
        _currentUserId = user.id;
        _currentUsername = user.username;
      });
    }
  }

  /// 连接 WebSocket
  /// 
  /// 建立与服务器的实时通信连接，用于接收来电等事件。
  Future<void> _connectWebSocket() async {
    if (_currentUserId == null) return;

    try {
      await _webSocketService.connect(_currentUserId!);
      _callService.videoEvent();
      _callService.setOnIncomingCall(_handleIncomingCall);
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

  /// 处理来电
  /// 
  /// 当收到来电时，自动查找联系人信息并跳转到通话界面。
  /// 
  /// 参数：
  /// - callerId: 呼叫方用户ID
  /// - callerName: 呼叫方用户名
  /// - isOnlyAudio: 是否仅音频通话
  void _handleIncomingCall(String callerId, String? callerName, bool isOnlyAudio) {
    print('处理来电: callerId=$callerId, callerName=$callerName');

    final contact = _contacts.firstWhere(
      (c) => c.id == callerId,
      orElse: () => Contact(
        id: callerId,
        username: callerName ?? '未知用户',
        avatar: '',
        bio: '',
      ),
    );

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CallScreen(
            contact: contact,
            callType: CallType.incoming,
          ),
        ),
      );
    }
  }

  /// 加载联系人列表
  /// 
  /// 从服务器获取当前用户的联系人列表。
  Future<void> _loadContacts() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = await _authService.getCurrentUser();
      if (user != null) {
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

  /// 退出登录
  /// 
  /// 断开 WebSocket 连接，清除本地用户信息，并跳转到登录界面。
  void _logout() async {
    _webSocketService.disconnect();
    await _authService.logout();
    Navigator.pushReplacementNamed(context, '/login');
  }

  /// 发起通话
  /// 
  /// 跳转到通话界面，发起对指定联系人的语音通话。
  /// 
  /// 参数：
  /// - contact: 要通话的联系人
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

  /// 删除联系人
  /// 
  /// 显示确认对话框，删除指定的联系人。
  /// 
  /// 参数：
  /// - contact: 要删除的联系人
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

  /// 显示我的用户ID
  /// 
  /// 弹出对话框显示当前用户的ID，方便分享给好友添加为联系人。
  void _showMyID() {
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
          /// WebSocket 连接状态指示器
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
          /// 联系人请求按钮
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
          /// 我的ID按钮
          IconButton(
            icon: Icon(Icons.person, color: Colors.white),
            onPressed: _showMyID,
            tooltip: '我的ID',
          ),
          /// 退出登录按钮
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
                            /// 联系人头像
                            leading: CircleAvatar(
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
                            /// 联系人信息
                            title: Text(
                              contact.username,
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(contact.bio),
                            /// 操作按钮
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                /// 通话按钮
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
                                /// 删除按钮
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
      /// 添加联系人浮动按钮
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

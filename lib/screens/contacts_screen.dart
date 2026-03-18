import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_base/services/auth_service.dart';
import 'package:flutter_base/services/contact_service.dart';
import 'package:flutter_base/services/websocket_service.dart';
import 'package:flutter_base/services/call_service.dart';
import 'package:flutter_base/screens/add_contact_screen.dart';
import 'package:flutter_base/screens/call_screen.dart';
import 'package:flutter_base/screens/contact_requests_screen.dart';
import 'package:flutter_base/screens/profile_screen.dart';

/// 联系人模型
/// 
/// 包含联系人的基本信息和后量子安全公钥
/// 用于建立端到端加密通话
class Contact {
  final String id;
  final String username;
  final String avatar;
  final String bio;
  final bool isOnline;
  
  // 后量子加密公钥（ML-KEM）- 用于密钥封装
  final String? kemPublicKey;
  
  // 后量子签名公钥 - 用于验证签名
  final String? sigPublicKey;

  Contact({
    required this.id,
    required this.username,
    required this.avatar,
    required this.bio,
    this.isOnline = false,
    this.kemPublicKey,
    this.sigPublicKey,
  });
  
  factory Contact.fromJson(Map<String, dynamic> json) {
    return Contact(
      id: json['id'] ?? '',
      username: json['username'] ?? '未知用户',
      avatar: json['avatar'] ?? '',
      bio: json['bio'] ?? '',
      isOnline: json['isOnline'] ?? false,
      kemPublicKey: json['kemPublicKey'],
      sigPublicKey: json['sigPublicKey'],
    );
  }
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
  StreamSubscription? _connectionSubscription;

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
      await _webSocketService.connect(_currentUserId!);
      _callService.audioEvent();
      _callService.setOnIncomingCall(_handleIncomingCall);
      print('WebSocket 连接成功');
      _connectionSubscription = _webSocketService.eventStream.listen((_) {
        if (mounted) {
          setState(() {});
        }
      });
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('WebSocket 连接失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('实时通信连接失败，请检查网络')),
        );
      }
    }
  }

  bool _isHandlingIncomingCall = false;

  void _handleIncomingCall(
    String callerId, 
    String? callerName, 
    bool isOnlyAudio, {
    String? kemCiphertext,
    String? signature,
    String? sigPublicKey,
    String? timestamp,
    Map<String, dynamic>? offer,
  }) {
    print('处理来电: callerId=$callerId, callerName=$callerName');

    // 防止重复处理来电
    if (_isHandlingIncomingCall) {
      print('来电已在处理中，跳过');
      return;
    }

    _isHandlingIncomingCall = true;

    final contact = _contacts.firstWhere(
      (c) => c.id == callerId,
      orElse: () => Contact(
        id: callerId,
        username: callerName ?? '未知用户',
        avatar: '',
        bio: '',
        kemPublicKey: null,
        sigPublicKey: sigPublicKey,
      ),
    );

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CallScreen(
            contact: contact,
            callType: CallType.incoming,
            kemCiphertext: kemCiphertext,
            signature: signature,
            callerSigPublicKey: sigPublicKey,
            timestamp: timestamp,
            offer: offer,
          ),
        ),
      ).then((_) {
        // 页面关闭后重置标志
        _isHandlingIncomingCall = false;
      });
    }
  }

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

  void _logout() async {
    _webSocketService.disconnect();
    await _authService.logout();
    Navigator.pushReplacementNamed(context, '/login');
  }

  void _startCall(Contact contact) {
    // 检查公钥信息是否完整
    if (contact.kemPublicKey == null || contact.sigPublicKey == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('联系人公钥信息不完整，无法发起安全通话')),
      );
      return;
    }
    
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  void _showMyID() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('我的ID'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('您的用户ID：'),
            SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                _currentUserId ?? '未知',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: Colors.grey[800],
                ),
              ),
            ),
            SizedBox(height: 12),
            Text(
              '分享此ID给好友，让他们添加您为联系人',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
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
    _connectionSubscription?.cancel();
    _webSocketService.disconnect();
    _callService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('联系人'),
        backgroundColor: Colors.grey[800],
        elevation: 0,
        actions: [
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
            icon: Icon(Icons.person_add_alt_1_outlined, color: Colors.white),
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => ContactRequestsScreen()),
              );
              // 如果从联系人请求页面返回时有更新，刷新联系人列表
              if (result == true) {
                _loadContacts();
              }
            },
            tooltip: '联系人请求',
          ),
          IconButton(
            icon: Icon(Icons.account_circle_outlined, color: Colors.white),
            onPressed: () {
              Navigator.pushNamed(context, '/profile');
            },
            tooltip: '个人信息',
          ),
          IconButton(
            icon: Icon(Icons.logout, color: Colors.white),
            onPressed: _logout,
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: Colors.grey[600]))
          : RefreshIndicator(
              onRefresh: _loadContacts,
              color: Colors.grey[600],
              child: _contacts.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.people_outline,
                            size: 80,
                            color: Colors.grey[300],
                          ),
                          SizedBox(height: 16),
                          Text(
                            '暂无联系人',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[500],
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
                      padding: EdgeInsets.all(12),
                      itemCount: _contacts.length,
                      itemBuilder: (context, index) {
                        final contact = _contacts[index];
                        return Container(
                          margin: EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            leading: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                shape: BoxShape.circle,
                                image: contact.avatar.isNotEmpty
                                    ? DecorationImage(
                                        image: MemoryImage(base64Decode(contact.avatar)),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                              ),
                              child: contact.avatar.isEmpty
                                  ? Center(
                                      child: Text(
                                        contact.username[0].toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.grey[700],
                                        ),
                                      ),
                                    )
                                  : null,
                            ),
                            title: Text(
                              contact.username,
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                color: Colors.grey[800],
                              ),
                            ),
                            subtitle: Text(
                              contact.bio,
                              style: TextStyle(color: Colors.grey[500]),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.call_outlined, color: Colors.grey[600]),
                                  onPressed: () => _startCall(contact),
                                  tooltip: '通话',
                                ),
                                IconButton(
                                  icon: Icon(Icons.delete_outline, color: Colors.grey[400]),
                                  onPressed: () => _deleteContact(contact),
                                  tooltip: '删除',
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
        child: Icon(Icons.add, color: Colors.white),
        backgroundColor: Colors.grey[800],
        elevation: 2,
      ),
    );
  }
}

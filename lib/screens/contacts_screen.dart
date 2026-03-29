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
///
/// 安全字段：
/// - kemPublicKey: ML-KEM 公钥，用于密钥封装
/// - sigPublicKey: 签名公钥，用于验证身份
class Contact {
  // ==================== 基本信息 ====================

  /// 用户唯一标识
  final String id;

  /// 用户名
  final String username;

  /// 头像路径
  final String avatar;

  /// 个性签名
  final String bio;

  /// 是否在线
  final bool isOnline;

  // ==================== 后量子安全公钥 ====================

  /// 后量子加密公钥（ML-KEM）- 用于密钥封装
  final String? kemPublicKey;

  /// 后量子签名公钥 - 用于验证签名
  final String? sigPublicKey;

  // ==================== 构造函数 ====================

  Contact({
    required this.id,
    required this.username,
    required this.avatar,
    required this.bio,
    this.isOnline = false,
    this.kemPublicKey,
    this.sigPublicKey,
  });

  /// 从 JSON 创建 Contact 对象
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

/// 联系人列表界面
///
/// 主要功能：
/// 1. 显示联系人列表
/// 2. 发起加密通话
/// 3. 管理联系人（添加、删除）
/// 4. 处理来电
/// 5. 显示好友请求
///
/// 安全特性：
/// - 只显示拥有完整公钥的联系人
/// - 来电时验证签名
/// - 使用 WebSocket 接收实时信令
class ContactsScreen extends StatefulWidget {
  @override
  _ContactsScreenState createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  // ==================== 服务实例 ====================

  /// 认证服务
  final _authService = AuthService();

  /// 联系人服务
  final _contactService = ContactService();

  /// WebSocket 服务（用于实时信令）
  final _webSocketService = WebSocketService();

  /// 通话服务
  final _callService = CallService();

  // ==================== 状态变量 ====================

  /// 联系人列表
  List<Contact> _contacts = [];

  /// 是否正在加载
  bool _isLoading = false;

  /// 当前用户ID
  String? _currentUserId;

  /// 当前用户名
  String? _currentUsername;

  /// WebSocket 连接状态订阅
  StreamSubscription? _connectionSubscription;

  /// 是否正在处理来电（防止重复处理）
  bool _isHandlingIncomingCall = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  /// 初始化界面
  ///
  /// 流程：
  /// 1. 加载当前用户信息
  /// 2. 加载联系人列表
  /// 3. 连接 WebSocket
  Future<void> _initialize() async {
    await _loadCurrentUser();
    await _loadContacts();
    await _connectWebSocket();
  }

  /// 加载当前登录用户信息
  Future<void> _loadCurrentUser() async {
    final user = await _authService.getCurrentUser();
    if (user != null) {
      setState(() {
        _currentUserId = user.id;
        _currentUsername = user.username;
      });
    }
  }

  /// 连接 WebSocket 服务器
  ///
  /// 用于接收实时信令消息（来电、通话状态等）
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

  /// 构建头像图片
  DecorationImage? _buildAvatarImage(String avatar) {
    if (avatar.isEmpty) return null;
    
    try {
      return DecorationImage(
        image: MemoryImage(base64Decode(avatar)),
        fit: BoxFit.cover,
      );
    } catch (e) {
      print('头像解码失败: $e');
      return null;
    }
  }

  /// 构建头像占位符
  Widget? _buildAvatarPlaceholder(Contact contact) {
    if (contact.avatar.isNotEmpty) {
      try {
        base64Decode(contact.avatar);
        return null;
      } catch (e) {
        // 头像解码失败，显示占位符
      }
    }
    
    return Center(
      child: Text(
        contact.username.isNotEmpty ? contact.username[0].toUpperCase() : '?',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w500,
          color: Colors.grey[700],
        ),
      ),
    );
  }

  /// 处理来电
  ///
  /// 当收到来电时跳转到通话界面
  ///
  /// 参数：
  /// - callerId: 呼叫方用户ID
  /// - callerName: 呼叫方用户名
  /// - isOnlyAudio: 是否仅音频通话
  /// - kemCiphertext: KEM 密文（用于密钥交换）
  /// - signature: 签名（用于验证身份）
  /// - sigPublicKey: 签名公钥
  /// - timestamp: 时间戳
  /// - offer: WebRTC offer
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

    // 查找联系人信息，如果不存在则创建临时联系人
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

  /// 加载联系人列表
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

  /// 用户登出
  Future<void> _logout() async {
    _webSocketService.disconnect();
    await _authService.logout();
    Navigator.pushReplacementNamed(context, '/login');
  }

  /// 发起通话
  ///
  /// 检查联系人公钥是否完整，然后跳转到通话界面
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
                                image: _buildAvatarImage(contact.avatar),
                              ),
                              child: _buildAvatarPlaceholder(contact),
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

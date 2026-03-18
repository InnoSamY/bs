import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_base/models/user.dart';
import 'package:flutter_base/services/auth_service.dart';
import 'package:image_picker/image_picker.dart';

class ProfileScreen extends StatefulWidget {
  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _authService = AuthService();
  final _formKey = GlobalKey<FormState>();
  final _bioController = TextEditingController();

  User? _currentUser;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _avatarBase64;
  Uint8List? _avatarBytes;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = await _authService.getCurrentUser();
      if (user != null) {
        _currentUser = user;
        _bioController.text = user.bio;
        if (user.avatar.isNotEmpty) {
          try {
            _avatarBytes = base64Decode(user.avatar);
          } catch (e) {
            _avatarBytes = null;
          }
        }
      }
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载用户信息失败: $error')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 200,
      maxHeight: 200,
      imageQuality: 80,
    );

    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      setState(() {
        _avatarBytes = bytes;
        _avatarBase64 = base64Encode(bytes);
      });
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final avatar = _avatarBase64 ?? _currentUser?.avatar ?? '';
      final bio = _bioController.text.trim();

      await _authService.updateProfile(
        avatar: avatar,
        bio: bio,
      );

      await _loadUserProfile();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('个人信息更新成功')),
      );
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('更新失败: $error')),
      );
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  @override
  void dispose() {
    _bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('个人信息'),
        backgroundColor: Colors.grey[800],
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveProfile,
            child: _isSaving
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    '保存',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: Colors.grey[600]))
          : SingleChildScrollView(
              padding: EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(height: 20),
                    GestureDetector(
                      onTap: _pickAvatar,
                      child: Stack(
                        children: [
                          Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.grey[200],
                              border: Border.all(
                                color: Colors.grey[300]!,
                                width: 2,
                              ),
                              image: _avatarBytes != null
                                  ? DecorationImage(
                                      image: MemoryImage(_avatarBytes!),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: _avatarBytes == null
                                ? Center(
                                    child: Text(
                                      _currentUser?.username.isNotEmpty == true
                                          ? _currentUser!.username[0].toUpperCase()
                                          : '?',
                                      style: TextStyle(
                                        fontSize: 36,
                                        color: Colors.grey[600],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.grey[700],
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              child: Icon(
                                Icons.camera_alt,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '点击更换头像',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 12,
                      ),
                    ),
                    SizedBox(height: 24),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          ListTile(
                            leading: Icon(Icons.person_outline, color: Colors.grey[600]),
                            title: Text('用户ID', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                            subtitle: Text(
                              _currentUser?.id ?? '未知',
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                color: Colors.grey[800],
                              ),
                            ),
                          ),
                          Divider(height: 1, color: Colors.grey[200]),
                          ListTile(
                            leading: Icon(Icons.badge_outlined, color: Colors.grey[600]),
                            title: Text('用户名', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                            subtitle: Text(
                              _currentUser?.username ?? '未知',
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                color: Colors.grey[800],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '个性签名',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[500],
                            ),
                          ),
                          SizedBox(height: 12),
                          TextFormField(
                            controller: _bioController,
                            maxLines: 3,
                            maxLength: 100,
                            decoration: InputDecoration(
                              hintText: '写点什么介绍一下自己吧...',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: EdgeInsets.all(12),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: Icon(Icons.key_outlined, color: Colors.grey[600]),
                        title: Text('后量子公钥'),
                        subtitle: Text(
                          _currentUser?.kemPublicKey.isNotEmpty == true
                              ? '${_currentUser!.kemPublicKey.substring(0, 20)}...'
                              : '未设置',
                          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                        ),
                        trailing: Icon(Icons.chevron_right, color: Colors.grey[400]),
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              title: Text('我的后量子公钥'),
                              content: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('KEM 公钥 (ML-KEM-768):', style: TextStyle(fontWeight: FontWeight.bold)),
                                    SizedBox(height: 8),
                                    SelectableText(
                                      _currentUser?.kemPublicKey ?? '未设置',
                                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                                    ),
                                    SizedBox(height: 16),
                                    Text('签名公钥:', style: TextStyle(fontWeight: FontWeight.bold)),
                                    SizedBox(height: 8),
                                    SelectableText(
                                      _currentUser?.sigPublicKey ?? '未设置',
                                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                                    ),
                                  ],
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: Text('关闭'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    SizedBox(height: 32),
                    Text(
                      'Quantalk v1.0.0',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

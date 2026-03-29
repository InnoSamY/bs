import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_base/services/auth_service.dart';
import 'package:flutter_base/screens/login_screen.dart';
import 'dart:io';
import 'dart:convert';

/// 注册界面
/// 
/// 提供新用户注册功能，包括：
/// - 头像上传（从相册选择）
/// - 用户名输入
/// - 密码输入（至少6位）
/// - 个性签名输入
/// 
/// 注册成功后会显示用户ID，需要用户牢记
/// 同时会自动生成后量子密钥对（ML-KEM + 签名）
class RegisterScreen extends StatefulWidget {
  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  // ==================== 表单控制器 ====================

  /// 表单全局键，用于表单验证
  final _formKey = GlobalKey<FormState>();

  /// 用户名输入控制器
  final _usernameController = TextEditingController();

  /// 密码输入控制器
  final _passwordController = TextEditingController();

  /// 个性签名输入控制器
  final _bioController = TextEditingController();

  /// 认证服务实例
  final _authService = AuthService();

  // ==================== 状态变量 ====================

  /// 选择的头像文件
  File? _avatarFile;

  /// 是否正在注册中（显示加载指示器）
  bool _isLoading = false;

  /// 是否隐藏密码（用于切换显示/隐藏）
  bool _obscurePassword = true;

  @override
  void dispose() {
    // 释放控制器资源
    _usernameController.dispose();
    _passwordController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  /// 从相册选择头像图片
  /// 
  /// 使用 image_picker 插件打开相册
  /// 用户选择图片后更新 _avatarFile 状态
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _avatarFile = File(pickedFile.path);
      });
    }
  }

  /// 将图片文件转换为 Base64 字符串
  Future<String> _imageToBase64(File? imageFile) async {
    if (imageFile == null) return '';
    try {
      final bytes = await imageFile.readAsBytes();
      return base64Encode(bytes);
    } catch (e) {
      print('图片转 Base64 失败: $e');
      return '';
    }
  }

  /// 执行注册操作
  ///
  /// 流程：
  /// 1. 验证表单输入
  /// 2. 调用 AuthService 进行注册（会自动生成后量子密钥对）
  /// 3. 注册成功显示用户ID对话框
  /// 4. 注册失败显示错误提示
  Future<void> _register() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        // 将头像图片转换为 Base64
        final avatarBase64 = await _imageToBase64(_avatarFile);

        // 调用认证服务进行注册
        final user = await _authService.register(
          username: _usernameController.text.trim(),
          password: _passwordController.text.trim(),
          avatar: avatarBase64,
          bio: _bioController.text.trim(),
        );

        // 显示注册成功对话框，展示用户ID
        showDialog(
          context: context,
          barrierDismissible: false, // 禁止点击外部关闭
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Text('注册成功'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('您的用户ID是：'),
                SizedBox(height: 12),
                // 用户ID展示框
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    user.id,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: Colors.grey[800],
                    ),
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  '请牢记您的用户ID，登录时需要使用！',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  // 跳转到登录页面
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => LoginScreen()),
                  );
                },
                child: Text('确定'),
              ),
            ],
          ),
        );
      } catch (error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text('注册'),
        backgroundColor: Colors.grey[800],
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24),
          child: Container(
            width: 400,
            padding: EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.grey[100],
                        border: Border.all(color: Colors.grey[300]!, width: 2),
                      ),
                      child: ClipOval(
                        child: _avatarFile != null
                            ? Image.file(_avatarFile!, fit: BoxFit.cover)
                            : Icon(Icons.camera_alt, size: 36, color: Colors.grey[500]),
                      ),
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '点击上传头像',
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                  SizedBox(height: 32),
                  TextFormField(
                    controller: _usernameController,
                    decoration: InputDecoration(
                      labelText: '用户名',
                      prefixIcon: Icon(Icons.person_outline, color: Colors.grey[600]),
                    ),
                    validator: (value) {
                      if (value!.isEmpty) {
                        return '请输入用户名';
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: '密码',
                      prefixIcon: Icon(Icons.lock_outline, color: Colors.grey[600]),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off : Icons.visibility,
                          color: Colors.grey[500],
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                    ),
                    obscureText: _obscurePassword,
                    validator: (value) {
                      if (value!.isEmpty) {
                        return '请输入密码';
                      }
                      if (value.length < 6) {
                        return '密码长度至少6位';
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: 16),
                  TextFormField(
                    controller: _bioController,
                    decoration: InputDecoration(
                      labelText: '个性签名',
                      prefixIcon: Icon(Icons.edit_outlined, color: Colors.grey[600]),
                    ),
                    maxLines: 2,
                  ),
                  SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _register,
                      child: _isLoading
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text('注册', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                    ),
                  ),
                  SizedBox(height: 16),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => LoginScreen()),
                      );
                    },
                    child: Text(
                      '已有账号？立即登录',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

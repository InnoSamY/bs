import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_base/services/auth_service.dart';
import 'package:flutter_base/services/crypto_service.dart';
import 'package:flutter_base/screens/login_screen.dart';
import 'dart:io';

/// 注册界面
/// 
/// 提供用户注册功能，包含以下特性：
/// 1. 用户名、密码、个性签名输入
/// 2. 头像上传
/// 3. 生成后量子加密密钥对
/// 4. 表单验证
/// 5. 注册成功后显示用户ID
class RegisterScreen extends StatefulWidget {
  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _bioController = TextEditingController();
  final _authService = AuthService();
  final _cryptoService = CryptoService();
  File? _avatarFile;
  bool _isLoading = false;
  bool _obscurePassword = true;
  
  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _bioController.dispose();
    super.dispose();
  }
  
  /// 选择图片
  /// 
  /// 从相册中选择头像图片。
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    
    if (pickedFile != null) {
      setState(() {
        _avatarFile = File(pickedFile.path);
      });
    }
  }
  
  /// 执行注册
  /// 
  /// 生成密钥对并调用认证服务进行注册。
  Future<void> _register() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });
      
      try {
        // 生成后量子密钥对
        final keyPair = _cryptoService.generateKeyPair();
        String publicKey = keyPair['publicKey']!;
        
        final user = await _authService.register(
          username: _usernameController.text.trim(),
          password: _passwordController.text.trim(),
          avatar: _avatarFile?.path ?? '',
          bio: _bioController.text.trim(),
          publicKey: publicKey,
        );
        
        // 显示注册成功对话框，展示用户ID
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Text('注册成功'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('您的用户ID是：'),
                SizedBox(height: 10),
                Container(
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue),
                  ),
                  child: SelectableText(
                    user.id,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  '请牢记您的用户ID，登录时需要使用！',
                  style: TextStyle(color: Colors.red, fontSize: 12),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
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
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue[600]!, Colors.blue[900]!],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(20),
            child: SizedBox(
              width: 400,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 20,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                padding: EdgeInsets.all(30),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      /// 头像上传区域
                      GestureDetector(
                        onTap: _pickImage,
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.blue,
                              width: 3,
                            ),
                          ),
                          child: ClipOval(
                            child: _avatarFile != null
                                ? Image.file(
                                    _avatarFile!,
                                    fit: BoxFit.cover,
                                  )
                                : Container(
                                    color: Colors.blue[100],
                                    child: Icon(
                                      Icons.camera_alt,
                                      size: 40,
                                      color: Colors.blue,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      SizedBox(height: 10),
                      Text(
                        '点击上传头像',
                        style: TextStyle(color: Colors.blue[600]),
                      ),
                      SizedBox(height: 40),
                      /// 用户名输入框
                      TextFormField(
                        controller: _usernameController,
                        decoration: InputDecoration(
                          labelText: '用户名',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          prefixIcon: Icon(Icons.person, color: Colors.blue),
                          filled: true,
                          fillColor: Colors.blue[50],
                        ),
                        validator: (value) {
                          if (value!.isEmpty) {
                            return '请输入用户名';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 20),
                      /// 密码输入框
                      TextFormField(
                        controller: _passwordController,
                        decoration: InputDecoration(
                          labelText: '密码',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          prefixIcon: Icon(Icons.lock, color: Colors.blue),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility : Icons.visibility_off,
                              color: Colors.blue,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                          filled: true,
                          fillColor: Colors.blue[50],
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
                      SizedBox(height: 20),
                      /// 个性签名输入框
                      TextFormField(
                        controller: _bioController,
                        decoration: InputDecoration(
                          labelText: '个性签名',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          prefixIcon: Icon(Icons.edit, color: Colors.blue),
                          filled: true,
                          fillColor: Colors.blue[50],
                        ),
                        maxLines: 2,
                      ),
                      SizedBox(height: 40),
                      /// 注册按钮
                      ElevatedButton(
                        onPressed: _isLoading ? null : _register,
                        child: _isLoading
                            ? CircularProgressIndicator(color: Colors.white)
                            : Text(
                                '注册',
                                style: TextStyle(fontSize: 16),
                              ),
                        style: ElevatedButton.styleFrom(
                          minimumSize: Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          backgroundColor: Colors.blue[600],
                          elevation: 5,
                        ),
                      ),
                      SizedBox(height: 20),
                      /// 跳转到登录页面的链接
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => LoginScreen()),
                          );
                        },
                        child: Text(
                          '已有账号？立即登录',
                          style: TextStyle(color: Colors.blue[600]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

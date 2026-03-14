import 'package:flutter/material.dart';
import 'package:flutter_base/screens/login_screen.dart';
import 'package:flutter_base/screens/register_screen.dart';
import 'package:flutter_base/screens/contacts_screen.dart';
import 'package:flutter_base/screens/add_contact_screen.dart';
import 'package:flutter_base/screens/call_screen.dart';
import 'package:flutter_base/services/auth_service.dart';

/// 应用入口
/// 初始化 Flutter 绑定并启动安全语音通话应用。
void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MyApp());
}

/// 应用主组件
/// 配置应用的主题、路由和初始页面。
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '安全语音通话',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => LoginScreen(),
        '/login': (context) => LoginScreen(),
        '/register': (context) => RegisterScreen(),
        '/contacts': (context) => ContactsScreen(),
        '/add_contact': (context) => AddContactScreen(),
      },
    );
  }
}

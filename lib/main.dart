import 'package:flutter/material.dart';
import 'package:flutter_base/screens/login_screen.dart';
import 'package:flutter_base/screens/register_screen.dart';
import 'package:flutter_base/screens/contacts_screen.dart';
import 'package:flutter_base/screens/add_contact_screen.dart';
import 'package:flutter_base/screens/call_screen.dart';
import 'package:flutter_base/services/auth_service.dart';

void main(List<String> args) {
  runApp(MyApp());
}

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

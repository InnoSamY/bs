import 'package:flutter/material.dart';
import 'package:flutter_base/services/contact_service.dart';

/// 添加联系人界面
///
/// 提供添加新联系人的功能：
/// - 输入对方用户ID
/// - 发送添加请求
///
/// 添加成功后，对方需要接受请求才能成为联系人
class AddContactScreen extends StatefulWidget {
  @override
  _AddContactScreenState createState() => _AddContactScreenState();
}

class _AddContactScreenState extends State<AddContactScreen> {
  final _formKey = GlobalKey<FormState>();
  final _contactIdController = TextEditingController();
  final _contactService = ContactService();
  bool _isLoading = false;

  @override
  void dispose() {
    _contactIdController.dispose();
    super.dispose();
  }

  Future<void> _addContact() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        await _contactService.addContact(
          contactId: _contactIdController.text.trim(),
          verificationMessage: '请求添加您为联系人',
        );

        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('联系人添加请求已发送')),
        );
      } catch (error) {
        String errorMessage = error.toString();
        if (errorMessage.startsWith('Exception: ')) {
          errorMessage = errorMessage.substring('Exception: '.length);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
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
        title: Text('添加联系人'),
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
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.person_add_outlined,
                      size: 36,
                      color: Colors.grey[600],
                    ),
                  ),
                  SizedBox(height: 24),
                  Text(
                    '添加联系人',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[800],
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '输入对方的用户ID发送好友请求',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[500],
                    ),
                  ),
                  SizedBox(height: 32),
                  TextFormField(
                    controller: _contactIdController,
                    decoration: InputDecoration(
                      labelText: '联系人ID',
                      prefixIcon: Icon(Icons.person_outline, color: Colors.grey[600]),
                    ),
                    validator: (value) {
                      if (value!.isEmpty) {
                        return '请输入联系人ID';
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _addContact,
                      child: _isLoading
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text('发送添加请求', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
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

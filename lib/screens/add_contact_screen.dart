import 'package:flutter/material.dart';
import 'package:flutter_base/services/contact_service.dart';

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
        
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('联系人添加请求已发送')),
        );
      } catch (error) {
        String errorMessage = error.toString();
        // 提取错误信息中的实际消息
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
      appBar: AppBar(
        title: Text('添加联系人'),
        backgroundColor: Colors.blue[600],
      ),
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
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.blue[100],
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.person_add,
                          size: 40,
                          color: Colors.blue,
                        ),
                      ),
                      SizedBox(height: 30),
                      Text(
                        '添加联系人',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[900],
                        ),
                      ),
                      SizedBox(height: 40),
                      TextFormField(
                        controller: _contactIdController,
                        decoration: InputDecoration(
                          labelText: '联系人ID',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          prefixIcon: Icon(Icons.person, color: Colors.blue),
                          filled: true,
                          fillColor: Colors.blue[50],
                        ),
                        validator: (value) {
                          if (value!.isEmpty) {
                            return '请输入联系人ID';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 40),
                      ElevatedButton(
                        onPressed: _isLoading ? null : _addContact,
                        child: _isLoading
                            ? CircularProgressIndicator(color: Colors.white)
                            : Text(
                                '发送添加请求',
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

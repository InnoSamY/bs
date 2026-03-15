import 'package:flutter/material.dart';
import 'package:flutter_base/services/contact_service.dart';

class ContactRequestsScreen extends StatefulWidget {
  @override
  _ContactRequestsScreenState createState() => _ContactRequestsScreenState();
}

class _ContactRequestsScreenState extends State<ContactRequestsScreen> {
  final _contactService = ContactService();
  List<dynamic> _receivedRequests = [];
  List<dynamic> _sentRequests = [];
  bool _isLoading = false;
  int _currentTab = 0;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final requests = await _contactService.getContactRequests();
      setState(() {
        _receivedRequests = requests['received'] ?? [];
        _sentRequests = requests['sent'] ?? [];
      });
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('获取请求列表失败: $error')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _acceptRequest(String requestId) async {
    try {
      await _contactService.acceptContactRequest(requestId: requestId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已接受联系人请求')),
      );
      _loadRequests();
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('接受请求失败: $error')),
      );
    }
  }

  Future<void> _rejectRequest(String requestId) async {
    try {
      await _contactService.rejectContactRequest(requestId: requestId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已拒绝联系人请求')),
      );
      _loadRequests();
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('拒绝请求失败: $error')),
      );
    }
  }

  Widget _buildReceivedRequests() {
    if (_receivedRequests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[300]),
            SizedBox(height: 16),
            Text(
              '暂无收到的请求',
              style: TextStyle(color: Colors.grey[500], fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(12),
      itemCount: _receivedRequests.length,
      itemBuilder: (context, index) {
        final request = _receivedRequests[index];
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
              ),
              child: Center(
                child: Text(
                  request['username']?[0]?.toUpperCase() ?? '?',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[700],
                  ),
                ),
              ),
            ),
            title: Text(
              request['username'] ?? '未知用户',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey[800],
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (request['verificationMessage'] != null && request['verificationMessage'].isNotEmpty)
                  Text(
                    '验证消息: ${request['verificationMessage']}',
                    style: TextStyle(color: Colors.grey[500], fontStyle: FontStyle.italic),
                  ),
                Text(
                  '请求时间: ${_formatDate(request['requestedAt'])}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(Icons.check, color: Colors.green),
                  onPressed: () => _acceptRequest(request['id']),
                  tooltip: '接受',
                ),
                IconButton(
                  icon: Icon(Icons.close, color: Colors.red),
                  onPressed: () => _rejectRequest(request['id']),
                  tooltip: '拒绝',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSentRequests() {
    if (_sentRequests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.send_outlined, size: 64, color: Colors.grey[300]),
            SizedBox(height: 16),
            Text(
              '暂无发送的请求',
              style: TextStyle(color: Colors.grey[500], fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(12),
      itemCount: _sentRequests.length,
      itemBuilder: (context, index) {
        final request = _sentRequests[index];
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
              ),
              child: Center(
                child: Text(
                  request['username']?[0]?.toUpperCase() ?? '?',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[700],
                  ),
                ),
              ),
            ),
            title: Text(
              request['username'] ?? '未知用户',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey[800],
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (request['verificationMessage'] != null && request['verificationMessage'].isNotEmpty)
                  Text(
                    '验证消息: ${request['verificationMessage']}',
                    style: TextStyle(color: Colors.grey[500], fontStyle: FontStyle.italic),
                  ),
                Text(
                  '发送时间: ${_formatDate(request['requestedAt'])}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                ),
              ],
            ),
            trailing: Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '等待确认',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '未知';
    try {
      final date = DateTime.parse(dateStr);
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    } catch (e) {
      return '未知';
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('联系人请求'),
          backgroundColor: Colors.grey[800],
          elevation: 0,
          bottom: TabBar(
            onTap: (index) {
              setState(() {
                _currentTab = index;
              });
            },
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white,
            splashFactory: NoSplash.splashFactory,
            tabs: [
              Tab(
                icon: Icon(Icons.download_outlined),
                text: '收到的请求',
              ),
              Tab(
                icon: Icon(Icons.upload_outlined),
                text: '发送的请求',
              ),
            ],
          ),
        ),
        body: _isLoading
            ? Center(child: CircularProgressIndicator(color: Colors.grey[600]))
            : TabBarView(
                children: [
                  _buildReceivedRequests(),
                  _buildSentRequests(),
                ],
              ),
      ),
    );
  }
}

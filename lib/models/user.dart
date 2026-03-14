/// 用户模型类
/// 
/// 表示应用中的用户实体，包含用户的基本信息和安全凭证。
class User {
  final String id;
  final String username;
  final String password;
  final String avatar;
  final String bio;
  final String publicKey;
  final String token;
  
  /// 构造函数
  /// 
  /// 参数：
  /// - id: 用户唯一标识
  /// - username: 用户名
  /// - password: 密码
  /// - avatar: 头像路径
  /// - bio: 个性签名
  /// - publicKey: 后量子加密公钥
  /// - token: JWT 认证令牌
  User({
    required this.id,
    required this.username,
    required this.password,
    required this.avatar,
    required this.bio,
    required this.publicKey,
    this.token = '',
  });
  
  /// 从 JSON 创建用户对象
  /// 
  /// 参数：
  /// - json: JSON 格式的用户数据
  /// 
  /// 返回：
  /// - User: 用户对象
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      username: json['username'],
      password: json['password'] ?? '',
      avatar: json['avatar'] ?? '',
      bio: json['bio'] ?? '',
      publicKey: json['publicKey'] ?? '',
      token: json['token'] ?? '',
    );
  }
  
  /// 将用户对象转换为 JSON
  /// 
  /// 返回：
  /// - Map<String, dynamic>: JSON 格式的用户数据
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'password': password,
      'avatar': avatar,
      'bio': bio,
      'publicKey': publicKey,
      'token': token,
    };
  }
}

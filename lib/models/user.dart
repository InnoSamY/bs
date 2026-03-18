/// 用户模型类
/// 
/// 表示应用中的用户实体，包含用户的基本信息和后量子安全凭证。
/// 
/// 安全凭证说明：
/// - kemPublicKey: ML-KEM 公钥（用于密钥封装）
/// - sigPublicKey: 签名公钥（用于数字签名验证）
/// 
/// 注意：私钥只在客户端本地存储，不上传到服务器
class User {
  final String id;
  final String username;
  final String password;
  final String avatar;
  final String bio;
  
  // 后量子加密公钥（ML-KEM）
  final String kemPublicKey;
  
  // 后量子签名公钥
  final String sigPublicKey;
  
  final String token;
  
  /// 构造函数
  User({
    required this.id,
    required this.username,
    required this.password,
    required this.avatar,
    required this.bio,
    required this.kemPublicKey,
    required this.sigPublicKey,
    this.token = '',
  });
  
  /// 从 JSON 创建用户对象
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? '',
      username: json['username'] ?? '',
      password: json['password'] ?? '',
      avatar: json['avatar'] ?? '',
      bio: json['bio'] ?? '',
      kemPublicKey: json['kemPublicKey'] ?? json['publicKey'] ?? '',
      sigPublicKey: json['sigPublicKey'] ?? '',
      token: json['token'] ?? '',
    );
  }
  
  /// 将用户对象转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'password': password,
      'avatar': avatar,
      'bio': bio,
      'kemPublicKey': kemPublicKey,
      'sigPublicKey': sigPublicKey,
      'token': token,
    };
  }
  
  /// 复制并修改用户对象
  User copyWith({
    String? id,
    String? username,
    String? password,
    String? avatar,
    String? bio,
    String? kemPublicKey,
    String? sigPublicKey,
    String? token,
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      password: password ?? this.password,
      avatar: avatar ?? this.avatar,
      bio: bio ?? this.bio,
      kemPublicKey: kemPublicKey ?? this.kemPublicKey,
      sigPublicKey: sigPublicKey ?? this.sigPublicKey,
      token: token ?? this.token,
    );
  }
}

/// 用户密钥存储模型
/// 
/// 用于本地存储用户的私钥信息
/// 注意：私钥只在本地存储，绝不上传到服务器
class UserKeys {
  final String userId;
  final String kemPublicKey;
  final String kemSecretKey;
  final String sigPublicKey;
  final String sigSecretKey;
  
  UserKeys({
    required this.userId,
    required this.kemPublicKey,
    required this.kemSecretKey,
    required this.sigPublicKey,
    required this.sigSecretKey,
  });
  
  factory UserKeys.fromJson(Map<String, dynamic> json) {
    return UserKeys(
      userId: json['userId'] ?? '',
      kemPublicKey: json['kemPublicKey'] ?? '',
      kemSecretKey: json['kemSecretKey'] ?? '',
      sigPublicKey: json['sigPublicKey'] ?? '',
      sigSecretKey: json['sigSecretKey'] ?? '',
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'kemPublicKey': kemPublicKey,
      'kemSecretKey': kemSecretKey,
      'sigPublicKey': sigPublicKey,
      'sigSecretKey': sigSecretKey,
    };
  }
}

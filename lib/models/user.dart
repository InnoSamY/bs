class User {
  final String id;
  final String username;
  final String password;
  final String avatar;
  final String bio;
  final String publicKey;
  final String token;
  
  User({
    required this.id,
    required this.username,
    required this.password,
    required this.avatar,
    required this.bio,
    required this.publicKey,
    this.token = '',
  });
  
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

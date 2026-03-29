import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 密钥存储服务类
/// 
/// 提供用户密钥对的本地安全存储功能。
/// 
/// 主要功能：
/// 1. 存储和获取 ML-KEM 密钥对
/// 2. 存储和获取签名密钥对
/// 3. 检查密钥是否存在
/// 4. 清除所有密钥
/// 5. 导出公钥
/// 
/// 安全说明：
/// - 私钥使用 SharedPreferences 本地存储
/// - 私钥绝不上传到服务器
/// - 建议未来使用 Keychain/Keystore 等更安全的存储方式
class KeyStorageService {
  // ==================== 存储键名常量 ====================
  
  /// ML-KEM 公钥存储键
  static const _kemPublicKey = 'kemPublicKey';
  
  /// ML-KEM 私钥存储键
  static const _kemPrivateKey = 'kemPrivateKey';
  
  /// 签名公钥存储键
  static const _sigPublicKey = 'sigPublicKey';
  
  /// 签名私钥存储键
  static const _sigPrivateKey = 'sigPrivateKey';

  // ==================== ML-KEM 密钥管理 ====================

  /// 保存 ML-KEM 密钥对
  /// 
  /// 参数：
  /// - publicKey: Base64 编码的公钥
  /// - privateKey: Base64 编码的私钥
  Future<void> saveKemKeyPair({
    required String publicKey,
    required String privateKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kemPublicKey, publicKey);
    await prefs.setString(_kemPrivateKey, privateKey);
  }

  /// 获取 ML-KEM 密钥对
  /// 
  /// 返回：
  /// - Map 包含 publicKey 和 privateKey，如果不存在则返回 null
  Future<Map<String, String>?> getKemKeyPair() async {
    final prefs = await SharedPreferences.getInstance();
    final publicKey = prefs.getString(_kemPublicKey);
    final privateKey = prefs.getString(_kemPrivateKey);
    if (publicKey == null || privateKey == null) return null;
    return {'publicKey': publicKey, 'privateKey': privateKey};
  }

  // ==================== 签名密钥管理 ====================

  /// 保存签名密钥对
  /// 
  /// 参数：
  /// - publicKey: Base64 编码的公钥
  /// - privateKey: Base64 编码的私钥
  Future<void> saveSignatureKeyPair({
    required String publicKey,
    required String privateKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sigPublicKey, publicKey);
    await prefs.setString(_sigPrivateKey, privateKey);
  }

  /// 获取签名密钥对
  /// 
  /// 返回：
  /// - Map 包含 publicKey 和 privateKey，如果不存在则返回 null
  Future<Map<String, String>?> getSignatureKeyPair() async {
    final prefs = await SharedPreferences.getInstance();
    final publicKey = prefs.getString(_sigPublicKey);
    final privateKey = prefs.getString(_sigPrivateKey);
    if (publicKey == null || privateKey == null) return null;
    return {'publicKey': publicKey, 'privateKey': privateKey};
  }

  // ==================== 密钥检查与清理 ====================

  /// 检查是否拥有所有必需的密钥
  /// 
  /// 返回：true 如果 ML-KEM 和签名密钥都存在
  Future<bool> hasAllKeys() async {
    final kem = await getKemKeyPair();
    final sig = await getSignatureKeyPair();
    return kem != null && sig != null;
  }

  /// 清除所有存储的密钥
  /// 
  /// 警告：此操作不可逆，清除后需要重新生成密钥
  Future<void> clearKeys() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kemPublicKey);
    await prefs.remove(_kemPrivateKey);
    await prefs.remove(_sigPublicKey);
    await prefs.remove(_sigPrivateKey);
  }

  // ==================== 公钥导出 ====================

  /// 导出所有公钥
  /// 
  /// 用于向服务器上传公钥或分享给其他用户。
  /// 
  /// 返回：
  /// - Map 包含 encryptionPublicKey（KEM 公钥）和 signaturePublicKey（签名公钥）
  Future<Map<String, String>> exportAllPublicKeys() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'encryptionPublicKey': prefs.getString(_kemPublicKey) ?? '',
      'signaturePublicKey': prefs.getString(_sigPublicKey) ?? '',
    };
  }
}

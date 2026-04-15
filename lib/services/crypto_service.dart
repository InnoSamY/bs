import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

/// 密码学服务（Crypto Service）
/// 
/// 提供对称加密与辅助密码学工具，包括：
/// 1. 对称加密（AES-256-GCM）
/// 2. 哈希函数（SHA-256）
/// 3. 密钥派生
/// 
/// 设计理念：
/// - 专注于对称加密和辅助密码学工具
/// - 提供简化的高级API
/// - 确保安全性和可靠性
class CryptoService {
  // 单例模式
  static final CryptoService _instance = CryptoService._internal();
  CryptoService._internal();
  factory CryptoService() => _instance;

  // ========== 对称加密（AES-256-GCM） ==========

  /// AES-256-GCM加密
  /// 
  /// 使用AES-256-GCM算法加密数据，提供认证加密。
  /// 
  /// 参数：
  /// - key: Base64编码的密钥（32字节）
  /// - plaintext: 明文
  /// 
  /// 返回：
  /// - ciphertext: Base64编码的密文
  /// - iv: Base64编码的初始化向量
  /// - tag: Base64编码的认证标签
  Map<String, String> encryptAesGcm(String key, String plaintext) {
    print('执行AES-256-GCM加密...');
    print('  原文: $plaintext');

    try {
      final keyBytes = base64Decode(key);
      
      final aesKey = keyBytes.length >= 32 
          ? keyBytes.sublist(0, 32)
          : Uint8List.fromList(List<int>.filled(32 - keyBytes.length, 0) + keyBytes);
      
      final iv = _generateRandomBytes(12);
      
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          true,
          AEADParameters(KeyParameter(aesKey), 128, iv, Uint8List(0)),
        );
      
      final plaintextBytes = utf8.encode(plaintext);
      final encrypted = cipher.process(Uint8List.fromList(plaintextBytes));
      
      final tag = encrypted.sublist(encrypted.length - 16);
      final ciphertext = encrypted.sublist(0, encrypted.length - 16);

      final ciphertextBase64 = base64Encode(ciphertext);
      final ivBase64 = base64Encode(iv);
      final tagBase64 = base64Encode(tag);

      print('✓ AES-256-GCM加密成功');
      print('  明文长度: ${plaintext.length} 字节');
      print('  密文: $ciphertextBase64');
      print('  密文长度: ${ciphertext.length} 字节');
      print('  IV: $ivBase64');
      print('  认证标签: $tagBase64');

      return {
        'ciphertext': ciphertextBase64,
        'iv': ivBase64,
        'tag': tagBase64,
      };
    } catch (e) {
      print('✗ AES-256-GCM加密失败: $e');
      rethrow;
    }
  }

  /// AES-256-GCM解密
  /// 
  /// 使用AES-256-GCM算法解密数据，验证认证标签。
  /// 
  /// 参数：
  /// - key: Base64编码的密钥（32字节）
  /// - ciphertext: Base64编码的密文
  /// - iv: Base64编码的初始化向量
  /// - tag: Base64编码的认证标签
  /// 
  /// 返回：解密后的明文
  String decryptAesGcm(String key, String ciphertext, String iv, String tag) {
    print('执行AES-256-GCM解密...');
    print('  密文: $ciphertext');

    try {
      final keyBytes = base64Decode(key);
      
      final aesKey = keyBytes.length >= 32 
          ? keyBytes.sublist(0, 32)
          : Uint8List.fromList(List<int>.filled(32 - keyBytes.length, 0) + keyBytes);
      
      final ciphertextBytes = base64Decode(ciphertext);
      final ivBytes = base64Decode(iv);
      final tagBytes = base64Decode(tag);

      final encrypted = Uint8List(ciphertextBytes.length + tagBytes.length);
      encrypted.setAll(0, ciphertextBytes);
      encrypted.setAll(ciphertextBytes.length, tagBytes);

      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          false,
          AEADParameters(KeyParameter(aesKey), 128, ivBytes, Uint8List(0)),
        );
      
      final decrypted = cipher.process(encrypted);
      
      final decryptedText = utf8.decode(decrypted);

      print('✓ AES-256-GCM解密成功');
      print('  密文长度: ${ciphertext.length} 字节');
      print('  明文: $decryptedText');
      print('  明文长度: ${decryptedText.length} 字节');

      return decryptedText;
    } catch (e) {
      print('✗ AES-256-GCM解密失败: $e');
      rethrow;
    }
  }

  // ========== 哈希函数和密钥派生 ==========

  /// SHA-256哈希
  /// 
  /// 计算数据的SHA-256哈希值。
  /// 
  /// 参数：
  /// - data: 输入数据
  /// 
  /// 返回：Base64编码的哈希值
  String sha256Hash(String data) {
    print('执行 SHA-256 哈希...');
    print('  原文: $data');
    final bytes = utf8.encode(data);
    final hash = sha256.convert(bytes);
    final hashBase64 = base64Encode(hash.bytes);
    print('✓ SHA-256 哈希成功');
    print('  哈希值: $hashBase64');
    return hashBase64;
  }

  /// 派生AES-256密钥（SHA-256）
  /// 
  /// 使用SHA-256从输入派生32字节AES-256密钥。
  /// 
  /// 参数：
  /// - input: 输入数据（如共享密钥）
  /// 
  /// 返回：Base64编码的32字节AES-256密钥
  String deriveAesKey(String input) {
    print('派生 AES-256 密钥（SHA-256）...');
    print('  输入: $input');
    final bytes = utf8.encode(input);
    final hash = sha256.convert(bytes);
    final aesKey = base64Encode(hash.bytes);
    print('✓ AES-256 密钥派生成功');
    print('  派生密钥: $aesKey');
    return aesKey;
  }

  // ========== 内部辅助方法 ==========

  /// 生成随机字节
  Uint8List _generateRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }
}

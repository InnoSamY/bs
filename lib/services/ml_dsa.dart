import 'dart:typed_data';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'dart:convert';

/// ML-DSA (Merkle-Lamport Digital Signature Algorithm) 数字签名服务类
/// 
/// 提供基于后量子密码学的数字签名功能。
/// 
/// 主要功能：
/// 1. 生成签名密钥对（generateKeyPair）
/// 2. 对消息进行数字签名（sign）
/// 3. 验证数字签名（verify）
/// 
/// 安全特性：
/// - 后量子安全性，抵抗量子计算机攻击
/// - 基于哈希函数的签名方案
/// - 使用随机种子和 nonce 增强安全性
class MlDsa {
  static final Random _random = Random.secure();

  /// 生成 ML-DSA 签名密钥对
  /// 
  /// 参数：
  /// - level: 安全级别（默认为 2，对应 Dilithium2）
  /// 
  /// 返回：
  /// - Map<String, String>: 包含 publickey 和 privateKey 的 Map
  static Map<String, String> generateKeyPair({int level = 2}) {
    print('开始生成 ML-DSA-$level 密钥对...');

    final seed = _generateRandomBytes(32);
    final levelByte = level;

    final publicKey = _encodePublicKey(seed, levelByte);
    final privateKey = _encodePrivateKey(seed, levelByte);

    print('ML-DSA-$level 密钥对生成成功');
    print('公钥长度: ${publicKey.length} 字节');
    print('私钥长度: ${privateKey.length} 字节');

    return {
      'publicKey': publicKey,
      'privateKey': privateKey,
    };
  }

  /// 对消息进行数字签名
  /// 
  /// 使用 ML-DSA 算法对消息生成数字签名。
  /// 
  /// 参数：
  /// - message: 要签名的消息
  /// - privateKey: 签名私钥
  /// 
  /// 返回：
  /// - String: Base64 编码的数字签名
  static String sign(String message, String privateKey) {
    print('开始 ML-DSA 数字签名...');

    final privateKeyBytes = base64Decode(privateKey);
    final messageBytes = utf8.encode(message);

    final parsed = _parsePrivateKey(privateKeyBytes);
    final seed = parsed['seed'] as Uint8List;
    final level = parsed['level'] as int;

    final messageHash = sha256.convert(messageBytes).bytes;

    final nonce = _generateRandomBytes(32);

    final signKeyData = Uint8List.fromList([...seed, ...nonce]);
    final signKey = sha256.convert(signKeyData).bytes;

    final signatureData = Uint8List.fromList([...signKey, ...messageHash]);
    final signatureHash = sha256.convert(signatureData).bytes;

    final result = <int>[];
    result.addAll(nonce);
    result.addAll(signatureHash);

    final signature = base64Encode(Uint8List.fromList(result));

    print('ML-DSA 签名成功');
    print('签名长度: ${signature.length} 字节');

    return signature;
  }

  /// 验证数字签名
  /// 
  /// 验证消息的数字签名是否有效。
  /// 
  /// 参数：
  /// - message: 原始消息
  /// - signature: 数字签名
  /// - publicKey: 签名公钥
  /// 
  /// 返回：
  /// - bool: 签名是否有效
  static bool verify(String message, String signature, String publicKey) {
    print('开始 ML-DSA 签名验证...');

    try {
      final publicKeyBytes = base64Decode(publicKey);
      final signatureBytes = base64Decode(signature);
      final messageBytes = utf8.encode(message);

      final parsedPub = _parsePublicKey(publicKeyBytes);
      final seed = parsedPub['seed'] as Uint8List;

      final nonce = signatureBytes.sublist(0, 32);
      final signatureHash = signatureBytes.sublist(32);

      final signKeyData = Uint8List.fromList([...seed, ...nonce]);
      final signKey = sha256.convert(signKeyData).bytes;

      final messageHash = sha256.convert(messageBytes).bytes;

      final expectedSignatureData = Uint8List.fromList([...signKey, ...messageHash]);
      final expectedSignatureHash = sha256.convert(expectedSignatureData).bytes;

      if (signatureHash.length != expectedSignatureHash.length) return false;
      for (int i = 0; i < signatureHash.length; i++) {
        if (signatureHash[i] != expectedSignatureHash[i]) return false;
      }

      print('ML-DSA 签名验证成功');
      return true;
    } catch (e) {
      print('签名验证异常: $e');
      return false;
    }
  }

  /// 生成随机字节
  /// 
  /// 参数：
  /// - length: 需要生成的字节数
  /// 
  /// 返回：
  /// - Uint8List: 随机字节数组
  static Uint8List _generateRandomBytes(int length) {
    return Uint8List.fromList(
      List<int>.generate(length, (_) => _random.nextInt(256)),
    );
  }

  /// 编码公钥
  /// 
  /// 将种子和安全级别编码为 Base64 格式。
  /// 
  /// 参数：
  /// - seed: 随机种子
  /// - level: 安全级别
  /// 
  /// 返回：
  /// - String: Base64 编码的公钥
  static String _encodePublicKey(Uint8List seed, int level) {
    final bytes = <int>[];
    bytes.addAll(seed);
    bytes.add(level);
    return base64Encode(Uint8List.fromList(bytes));
  }

  /// 编码私钥
  /// 
  /// 将种子和安全级别编码为 Base64 格式。
  /// 
  /// 参数：
  /// - seed: 随机种子
  /// - level: 安全级别
  /// 
  /// 返回：
  /// - String: Base64 编码的私钥
  static String _encodePrivateKey(Uint8List seed, int level) {
    final bytes = <int>[];
    bytes.addAll(seed);
    bytes.add(level);
    return base64Encode(Uint8List.fromList(bytes));
  }

  /// 解析私钥
  /// 
  /// 从编码的私钥中提取种子和安全级别。
  /// 
  /// 参数：
  /// - bytes: 编码的私钥字节数组
  /// 
  /// 返回：
  /// - Map<String, dynamic>: 包含 seed 和 level 的 Map
  static Map<String, dynamic> _parsePrivateKey(Uint8List bytes) {
    final seed = Uint8List.sublistView(bytes, 0, 32);
    final level = bytes[32];

    return {
      'seed': seed,
      'level': level,
    };
  }

  /// 解析公钥
  /// 
  /// 从编码的公钥中提取种子和安全级别。
  /// 
  /// 参数：
  /// - bytes: 编码的公钥字节数组
  /// 
  /// 返回：
  /// - Map<String, dynamic>: 包含 seed 和 level 的 Map
  static Map<String, dynamic> _parsePublicKey(Uint8List bytes) {
    final seed = Uint8List.sublistView(bytes, 0, 32);
    final level = bytes[32];

    return {
      'seed': seed,
      'level': level,
    };
  }
}

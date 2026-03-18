import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// 后量子数字签名服务（PQC Signature Service）
/// 
/// ⚠️ 重要说明：
/// 这是基于哈希函数的后量子签名原型实现，用于概念验证和演示目的。
/// 实现基于 Lamport 一次性签名（OTS）思路。
/// 
/// 本实现采用以下方案：
/// - 基于 SHA-256 哈希函数构建
/// - 实现 Lamport OTS 签名方案的核心思想
/// - 提供完整的签名和验证功能
/// 
/// ❌ 这不是标准的 FIPS 204 ML-DSA (Dilithium) 实现
/// ✅ 这是一个基于哈希的后量子签名原型，用于：
/// - 演示后量子签名的基本概念
/// - 展示基于哈希的签名思路
/// - 提供可运行的概念验证代码
/// 
/// 📝 论文/文档中应描述为：
/// "系统采用基于哈希函数的后量子签名原型方案，安全性建立在 SHA-256 的
/// 抗原像攻击和抗碰撞性之上，用于演示后量子签名的概念。"
/// 
/// 生产环境建议使用经过审计的标准密码学库。
class PqcSignatureService {
  final Random _random = Random.secure();

  /// 生成签名密钥对
  /// 
  /// 基于 Lamport OTS 思想的实现：
  /// - 私钥：为每个消息位生成两个随机值
  /// - 公钥：对私钥中的每个随机值进行哈希
  /// 
  /// 返回：
  /// - publicKey: Base64 编码的公钥
  /// - privateKey: Base64 编码的私钥
  Map<String, String> generateKeyPair() {
    print('生成后量子签名密钥对（基于哈希的原型实现）...');

    // 对于 256 位哈希，我们需要 256 对密钥
    const int bits = 256;
    final privateKeyParts = <Uint8List>[];
    final publicKeyParts = <Uint8List>[];

    // 生成私钥和公钥
    for (int i = 0; i < bits; i++) {
      // 为每个位生成两个随机值
      final k0 = _generateRandomBytes(32);
      final k1 = _generateRandomBytes(32);
      privateKeyParts.add(k0);
      privateKeyParts.add(k1);

      // 计算公钥（对私钥值进行哈希）
      final pk0 = sha256.convert(k0).bytes;
      final pk1 = sha256.convert(k1).bytes;
      publicKeyParts.add(Uint8List.fromList(pk0));
      publicKeyParts.add(Uint8List.fromList(pk1));
    }

    // 构建私钥和公钥字节数组
    final privateKeyBuilder = BytesBuilder();
    for (final part in privateKeyParts) {
      privateKeyBuilder.add(part);
    }

    final publicKeyBuilder = BytesBuilder();
    for (final part in publicKeyParts) {
      publicKeyBuilder.add(part);
    }

    final privateKey = base64Encode(privateKeyBuilder.toBytes());
    final publicKey = base64Encode(publicKeyBuilder.toBytes());

    print('✓ 签名密钥对生成成功');
    print('  公钥长度: ${publicKeyBuilder.length} 字节');
    print('  私钥长度: ${privateKeyBuilder.length} 字节');

    return {
      'publicKey': publicKey,
      'privateKey': privateKey,
    };
  }

  /// 签名消息
  /// 
  /// 基于 Lamport OTS 思想的实现：
  /// 1. 计算消息哈希（SHA-256）
  /// 2. 根据哈希值的每一位，选择私钥中对应的随机值作为签名
  /// 
  /// 参数：
  /// - privateKey: Base64 编码的私钥
  /// - message: 要签名的消息
  /// 
  /// 返回：Base64 编码的签名
  String signMessage(String privateKey, String message) {
    print('执行后量子签名（基于哈希的原型实现）...');

    final privateKeyBytes = base64Decode(privateKey);
    const int bits = 256;
    const int keySize = 32;
    const int expectedPrivateKeyLength = bits * 2 * keySize;

    if (privateKeyBytes.length != expectedPrivateKeyLength) {
      throw ArgumentError('私钥格式错误，长度应为 $expectedPrivateKeyLength 字节');
    }

    // 计算消息哈希
    final messageBytes = utf8.encode(message);
    final messageHash = sha256.convert(messageBytes).bytes;

    // 构建签名
    final signatureBuilder = BytesBuilder();
    for (int i = 0; i < bits; i++) {
      // 获取哈希的第 i 位
      final bit = (messageHash[i ~/ 8] >> (i % 8)) & 1;
      // 根据位值选择对应的私钥部分
      final index = (i * 2 + bit) * keySize;
      final keyPart = privateKeyBytes.sublist(index, index + keySize);
      signatureBuilder.add(keyPart);
    }

    final signature = base64Encode(signatureBuilder.toBytes());

    print('✓ 签名成功');
    print('  签名长度: ${signatureBuilder.length} 字节');

    return signature;
  }

  /// 验证签名
  /// 
  /// 基于 Lamport OTS 思想的实现：
  /// 1. 计算消息哈希（SHA-256）
  /// 2. 根据哈希值的每一位，对签名中的对应值进行哈希
  /// 3. 验证结果是否与公钥匹配
  /// 
  /// 参数：
  /// - publicKey: Base64 编码的公钥
  /// - message: 原始消息
  /// - signature: Base64 编码的签名
  /// 
  /// 返回：签名是否有效
  bool verifyMessage(String publicKey, String message, String signature) {
    print('验证后量子签名（基于哈希的原型实现）...');

    try {
      final publicKeyBytes = base64Decode(publicKey);
      final signatureBytes = base64Decode(signature);
      const int bits = 256;
      const int keySize = 32;
      const int expectedPublicKeyLength = bits * 2 * keySize;
      const int expectedSignatureLength = bits * keySize;

      if (publicKeyBytes.length != expectedPublicKeyLength) {
        print('公钥格式错误，长度应为 $expectedPublicKeyLength 字节');
        return false;
      }

      if (signatureBytes.length != expectedSignatureLength) {
        print('签名格式错误，长度应为 $expectedSignatureLength 字节');
        return false;
      }

      // 计算消息哈希
      final messageBytes = utf8.encode(message);
      final messageHash = sha256.convert(messageBytes).bytes;

      // 验证签名
      for (int i = 0; i < bits; i++) {
        // 获取哈希的第 i 位
        final bit = (messageHash[i ~/ 8] >> (i % 8)) & 1;
        // 从签名中获取对应部分
        final sigIndex = i * keySize;
        final sigPart = signatureBytes.sublist(sigIndex, sigIndex + keySize);
        // 计算签名部分的哈希
        final sigHash = sha256.convert(sigPart).bytes;
        // 从公钥中获取对应部分
        final pubIndex = (i * 2 + bit) * keySize;
        final pubPart = publicKeyBytes.sublist(pubIndex, pubIndex + keySize);
        // 比较哈希值和公钥部分
        if (!_constantTimeEquals(sigHash, pubPart)) {
          print('签名验证失败：第 $i 位不匹配');
          return false;
        }
      }

      print('✓ 签名验证成功');
      return true;
    } catch (e) {
      print('✗ 签名验证异常: $e');
      return false;
    }
  }

  /// 导出公钥（返回 Base64 字符串）
  String exportPublicKey(String publicKey) {
    return publicKey;
  }

  /// 导出私钥（返回 Base64 字符串）
  String exportPrivateKey(String privateKey) {
    return privateKey;
  }

  /// 导入公钥
  String importPublicKey(String publicKeyBase64) {
    // 验证格式
    final bytes = base64Decode(publicKeyBase64);
    const int bits = 256;
    const int keySize = 32;
    const int expectedLength = bits * 2 * keySize;
    if (bytes.length != expectedLength) {
      throw ArgumentError('公钥格式错误，应为 $expectedLength 字节');
    }
    return publicKeyBase64;
  }

  /// 导入私钥
  String importPrivateKey(String privateKeyBase64) {
    // 验证格式
    final bytes = base64Decode(privateKeyBase64);
    const int bits = 256;
    const int keySize = 32;
    const int expectedLength = bits * 2 * keySize;
    if (bytes.length != expectedLength) {
      throw ArgumentError('私钥格式错误，应为 $expectedLength 字节');
    }
    return privateKeyBase64;
  }

  // ========== 内部辅助方法 ==========

  /// 生成随机字节
  Uint8List _generateRandomBytes(int length) {
    return Uint8List.fromList(
      List<int>.generate(length, (_) => _random.nextInt(256)),
    );
  }

  /// 常量时间比较（防止时序攻击）
  bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }
}

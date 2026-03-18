import 'dart:convert';
import 'dart:typed_data';
import 'package:pqcrypto/pqcrypto.dart';

/// 后量子密钥封装服务（PQC KEM Service）
/// 
/// 使用标准 ML-KEM（Kyber）算法实现密钥封装机制。
/// 基于 pqcrypto 包提供的标准实现。
///
/// 安全级别：ML-KEM-768（192位安全强度）
/// 
/// 主要功能：
/// - 生成密钥对
/// - 密钥封装（encapsulate）
/// - 密钥解封装（decapsulate）
class PqcKemService {
  late final KyberKem _kyberKem;

  PqcKemService() {
    // 使用 ML-KEM-768（Kyber-768），提供 192 位安全强度
    _kyberKem = PqcKem.kyber768;
  }

  /// 生成 ML-KEM 密钥对
  /// 
  /// 返回：
  /// - publicKey: Base64 编码的公钥
  /// - privateKey: Base64 编码的私钥
  Map<String, String> generateKeyPair() {
    print('生成 ML-KEM-768 密钥对...');
    
    final (publicKey, privateKey) = _kyberKem.generateKeyPair();
    
    final publicKeyBase64 = base64Encode(publicKey);
    final privateKeyBase64 = base64Encode(privateKey);

    print('✓ ML-KEM-768 密钥对生成成功');
    print('  公钥长度: ${publicKey.length} 字节');
    print('  私钥长度: ${privateKey.length} 字节');

    return {
      'publicKey': publicKeyBase64,
      'privateKey': privateKeyBase64,
    };
  }

  /// 密钥封装
  /// 
  /// 使用对方公钥封装生成共享密钥和密文
  /// 
  /// 参数：
  /// - publicKey: Base64 编码的公钥
  /// 
  /// 返回：
  /// - ciphertext: Base64 编码的密文
  /// - sharedSecret: Base64 编码的共享密钥
  Map<String, String> encapsulate(String publicKey) {
    print('执行 ML-KEM 密钥封装...');
    
    final publicKeyBytes = base64Decode(publicKey);
    final (ciphertext, sharedSecret) = _kyberKem.encapsulate(publicKeyBytes);
    
    final ciphertextBase64 = base64Encode(ciphertext);
    final sharedSecretBase64 = base64Encode(sharedSecret);

    print('✓ ML-KEM 密钥封装成功');
    print('  密文长度: ${ciphertext.length} 字节');
    print('  共享密钥长度: ${sharedSecret.length} 字节');

    return {
      'ciphertext': ciphertextBase64,
      'sharedSecret': sharedSecretBase64,
    };
  }

  /// 密钥解封装
  /// 
  /// 使用本地私钥解封装密文，恢复共享密钥
  /// 
  /// 参数：
  /// - privateKey: Base64 编码的私钥
  /// - ciphertext: Base64 编码的密文
  /// 
  /// 返回：
  /// - sharedSecret: Base64 编码的共享密钥
  String decapsulate(String privateKey, String ciphertext) {
    print('执行 ML-KEM 密钥解封装...');
    
    final privateKeyBytes = base64Decode(privateKey);
    final ciphertextBytes = base64Decode(ciphertext);
    
    final sharedSecret = _kyberKem.decapsulate(privateKeyBytes, ciphertextBytes);
    final sharedSecretBase64 = base64Encode(sharedSecret);

    print('✓ ML-KEM 密钥解封装成功');
    print('  共享密钥长度: ${sharedSecret.length} 字节');

    return sharedSecretBase64;
  }

  /// 派生 AES-256 密钥
  /// 
  /// 从共享密钥派生 AES-256 密钥（用于加密通话数据）
  /// 
  /// 参数：
  /// - sharedSecret: Base64 编码的共享密钥
  /// 
  /// 返回：32 字节 AES-256 密钥
  Uint8List deriveAesKey(String sharedSecret) {
    final sharedSecretBytes = base64Decode(sharedSecret);
    // ML-KEM-768 生成的共享密钥已经是 32 字节，可以直接使用
    // 如果需要额外派生，可以使用 HKDF
    return sharedSecretBytes.sublist(0, 32);
  }
}

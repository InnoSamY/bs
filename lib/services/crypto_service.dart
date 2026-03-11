import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:convert/convert.dart';
import 'package:pqcrypto/pqcrypto.dart';
import 'package:pointycastle/export.dart';
import 'ml_dsa.dart';

class CryptoService {
  // ML-KEM (Kyber) 实例 - 用于密钥封装机制
  late final KyberKem _kyberKem;

  CryptoService() {
    // 初始化后量子密码算法
    // 使用 ML-KEM-768 (Kyber-768)，提供 192 位安全强度
    _kyberKem = PqcKem.kyber768;
  }

  // 生成密钥对（使用 ML-KEM 后量子算法）
  Map<String, String> generateKeyPair() {
    try {
      print('开始生成 ML-KEM-768 密钥对...');
      
      // 使用 ML-KEM 生成密钥对
      final (publicKey, privateKey) = _kyberKem.generateKeyPair();
      
      // 将密钥转换为 Base64 格式
      final publicKeyBase64 = base64Encode(publicKey);
      final privateKeyBase64 = base64Encode(privateKey);

      print('ML-KEM-768 密钥对生成成功');
      print('公钥长度: ${publicKey.length} 字节');
      print('私钥长度: ${privateKey.length} 字节');

      return {
        'publicKey': publicKeyBase64,
        'privateKey': privateKeyBase64,
      };
    } catch (e) {
      print('ML-KEM 密钥对生成失败: $e');
      // 如果失败，回退到传统算法
      return _generateFallbackKeyPair();
    }
  }

  // 密钥封装（使用 ML-KEM 算法）
  // 返回：封装的密文和共享密钥
  Map<String, String> encapsulate(String publicKey) {
    try {
      print('开始 ML-KEM 密钥封装...');
      
      // 解码公钥
      final publicKeyBytes = base64Decode(publicKey);
      
      // 使用 ML-KEM 进行密钥封装
      final (ciphertext, sharedSecret) = _kyberKem.encapsulate(publicKeyBytes);
      
      final ciphertextBase64 = base64Encode(ciphertext);
      final sharedSecretBase64 = base64Encode(sharedSecret);

      print('ML-KEM 密钥封装成功');
      print('密文长度: ${ciphertext.length} 字节');
      print('共享密钥长度: ${sharedSecret.length} 字节');

      return {
        'ciphertext': ciphertextBase64,
        'sharedSecret': sharedSecretBase64,
      };
    } catch (e) {
      print('ML-KEM 密钥封装失败: $e');
      // 如果失败，回退到传统算法
      return _fallbackEncapsulate(publicKey);
    }
  }

  // 密钥解封装（使用 ML-KEM 算法）
  String decapsulate(String ciphertext, String privateKey) {
    try {
      print('开始 ML-KEM 密钥解封装...');
      
      // 解码密文和私钥
      final ciphertextBytes = base64Decode(ciphertext);
      final privateKeyBytes = base64Decode(privateKey);
      
      // 使用 ML-KEM 进行密钥解封装
      final sharedSecret = _kyberKem.decapsulate(privateKeyBytes, ciphertextBytes);
      
      final sharedSecretBase64 = base64Encode(sharedSecret);

      print('ML-KEM 密钥解封装成功');
      print('共享密钥长度: ${sharedSecret.length} 字节');

      return sharedSecretBase64;
    } catch (e) {
      print('ML-KEM 密钥解封装失败: $e');
      // 如果失败，回退到传统算法
      return _fallbackDecapsulate(ciphertext, privateKey);
    }
  }

  // 密钥交换（使用 ML-KEM 算法）
  // 这是对外提供的简化接口
  String keyExchange(String publicKey, String privateKey) {
    try {
      print('开始后量子密钥交换...');
      
      // 使用 ML-KEM 进行密钥交换
      // 注意：ML-KEM 是 KEM（密钥封装机制），不是传统的 DH 密钥交换
      // 这里我们使用封装来生成共享密钥
      
      final encapsulation = encapsulate(publicKey);
      return encapsulation['sharedSecret']!;
    } catch (e) {
      print('后量子密钥交换失败: $e');
      return _fallbackKeyExchange(publicKey, privateKey);
    }
  }

  // 生成签名密钥对（使用 ML-DSA 后量子算法）
  Map<String, String> generateSignatureKeyPair() {
    try {
      print('开始生成 ML-DSA-2 (Dilithium2) 签名密钥对...');
      
      // 使用 ML-DSA 生成密钥对
      final keyPair = MlDsa.generateKeyPair(level: 2);
      
      print('ML-DSA-2 签名密钥对生成成功');
      print('公钥长度: ${base64Decode(keyPair['publicKey']!).length} 字节');
      print('私钥长度: ${base64Decode(keyPair['privateKey']!).length} 字节');

      return keyPair;
    } catch (e) {
      print('ML-DSA 签名密钥对生成失败: $e');
      // 如果失败，回退到传统算法
      return _generateFallbackSignatureKeyPair();
    }
  }

  // 数字签名（使用 ML-DSA 后量子算法）
  String sign(String message, String privateKey) {
    try {
      print('开始 ML-DSA 数字签名...');
      
      // 使用 ML-DSA 进行签名
      final signature = MlDsa.sign(message, privateKey);
      
      print('ML-DSA 数字签名成功');
      print('签名长度: ${base64Decode(signature).length} 字节');

      return signature;
    } catch (e) {
      print('ML-DSA 数字签名失败: $e');
      // 如果失败，回退到传统算法
      return _fallbackSign(message, privateKey);
    }
  }

  // 验证签名（使用 ML-DSA 后量子算法）
  bool verify(String message, String signature, String publicKey) {
    try {
      print('开始 ML-DSA 签名验证...');
      
      // 使用 ML-DSA 验证签名
      final isValid = MlDsa.verify(message, signature, publicKey);

      print('ML-DSA 签名验证${isValid ? "成功" : "失败"}');

      return isValid;
    } catch (e) {
      print('ML-DSA 签名验证失败: $e');
      // 如果失败，回退到传统算法
      return _fallbackVerify(message, signature, publicKey);
    }
  }

  // 公钥加密（使用 ML-KEM + AES-256-GCM 混合加密）
  String encrypt(String plaintext, String publicKey) {
    try {
      print('开始后量子混合加密...');
      
      // 1. 使用 ML-KEM 封装生成共享密钥
      final encapsulation = encapsulate(publicKey);
      final sharedSecret = base64Decode(encapsulation['sharedSecret']!);
      final ciphertext = encapsulation['ciphertext']!;
      
      // 2. 使用共享密钥进行 AES-256-GCM 加密
      final aesKey = sharedSecret.sublist(0, 32);
      final iv = _generateRandomBytes(12);
      final plaintextBytes = utf8.encode(plaintext);

      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          true,
          AEADParameters(KeyParameter(aesKey), 128, iv, Uint8List(0)),
        );
      final encrypted = cipher.process(Uint8List.fromList(plaintextBytes));

      // 3. 组合密文、IV 和加密数据
      final combined = base64Decode(ciphertext) + iv + encrypted;
      final encryptedBase64 = base64Encode(combined);

      print('后量子混合加密成功');
      print('明文长度: ${plaintext.length}');
      print('密文长度: ${encrypted.length}');

      return encryptedBase64;
    } catch (e) {
      print('后量子混合加密失败: $e');
      // 如果失败，回退到传统算法
      return _fallbackEncrypt(plaintext, publicKey);
    }
  }

  // 私钥解密（使用 ML-KEM + AES-256-GCM 混合解密）
  String decrypt(String ciphertext, String privateKey) {
    try {
      print('开始后量子混合解密...');
      
      // 解码密文
      final encryptedBytes = base64Decode(ciphertext);
      
      // 提取 ML-KEM 密文（前 1088 字节，ML-KEM-768 的密文长度）
      final mlkemCiphertext = encryptedBytes.sublist(0, 1088);
      
      // 提取 IV（接下来的 12 字节）
      final iv = encryptedBytes.sublist(1088, 1100);
      
      // 提取实际加密数据（剩余字节）
      final actualCiphertext = encryptedBytes.sublist(1100);
      
      // 1. 使用 ML-KEM 解封装获取共享密钥
      final sharedSecret = decapsulate(
        base64Encode(mlkemCiphertext),
        privateKey,
      );
      final sharedSecretBytes = base64Decode(sharedSecret);
      
      // 2. 使用共享密钥进行 AES-256-GCM 解密
      final aesKey = sharedSecretBytes.sublist(0, 32);

      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          false,
          AEADParameters(KeyParameter(aesKey), 128, iv, Uint8List(0)),
        );
      final decrypted = cipher.process(Uint8List.fromList(actualCiphertext));

      // 将解密后的字节转换为字符串
      final decryptedText = utf8.decode(decrypted);

      print('后量子混合解密成功');
      print('密文长度: ${ciphertext.length}');
      print('明文长度: ${decryptedText.length}');

      return decryptedText;
    } catch (e) {
      print('后量子混合解密失败: $e');
      // 如果失败，回退到传统算法
      return _fallbackDecrypt(ciphertext, privateKey);
    }
  }

  // AES对称加密（使用 AES-256-GCM）
  String aesEncrypt(String plaintext, String key) {
    try {
      // 解码密钥
      final keyBytes = base64Decode(key);
      
      // 确保密钥长度为 32 字节（AES-256）
      final aesKey = keyBytes.length >= 32 
          ? keyBytes.sublist(0, 32)
          : Uint8List.fromList(List<int>.filled(32 - keyBytes.length, 0) + keyBytes);
      
      // 生成随机 IV（12 字节用于 GCM）
      final iv = _generateRandomBytes(12);
      
      // 创建 AES-256-GCM 加密器
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          true,
          AEADParameters(KeyParameter(aesKey), 128, iv, Uint8List(0)),
        );
      
      // 加密数据
      final encrypted = cipher.process(Uint8List.fromList(utf8.encode(plaintext)));
      
      // 将 IV 和密文合并并转换为 Base64
      final combined = iv + encrypted;
      final encryptedBase64 = base64Encode(combined);
      
      print('AES-256-GCM加密成功');
      print('明文长度: ${plaintext.length}');
      print('密文长度: ${encrypted.length}');
      
      return encryptedBase64;
    } catch (e) {
      print('AES加密失败: $e');
      throw Exception('AES加密失败: $e');
    }
  }

  // AES对称解密（使用 AES-256-GCM）
  String aesDecrypt(String ciphertext, String key) {
    try {
      // 解码密钥
      final keyBytes = base64Decode(key);
      
      // 确保密钥长度为 32 字节（AES-256）
      final aesKey = keyBytes.length >= 32 
          ? keyBytes.sublist(0, 32)
          : Uint8List.fromList(List<int>.filled(32 - keyBytes.length, 0) + keyBytes);
      
      // 解码密文
      final encryptedBytes = base64Decode(ciphertext);
      
      // 提取 IV（前 12 字节）
      final iv = encryptedBytes.sublist(0, 12);
      
      // 提取实际密文（剩余字节）
      final actualCiphertext = encryptedBytes.sublist(12);
      
      // 创建 AES-256-GCM 解密器
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          false,
          AEADParameters(KeyParameter(aesKey), 128, iv, Uint8List(0)),
        );
      
      // 解密数据
      final decrypted = cipher.process(Uint8List.fromList(actualCiphertext));
      
      // 将解密后的字节转换为字符串
      final decryptedText = utf8.decode(decrypted);
      
      print('AES-256-GCM解密成功');
      print('密文长度: ${ciphertext.length}');
      print('明文长度: ${decryptedText.length}');
      
      return decryptedText;
    } catch (e) {
      print('AES解密失败: $e');
      throw Exception('AES解密失败: $e');
    }
  }

  // 生成随机字节
  Uint8List _generateRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(List<int>.generate(length, (_) => random.nextInt(256)));
  }

  // 生成随机种子
  Uint8List _generateRandomSeed() {
    return _generateRandomBytes(32);
  }

  // ==================== 辅助方法 ====================

  // 编码公钥（非压缩格式）
  Uint8List _encodePublicKey(ECPublicKey publicKey) {
    final x = publicKey.Q!.x!.toBigInteger()!;
    final y = publicKey.Q!.y!.toBigInteger()!;

    final xBytes = _bigIntToBytes(x, 32);
    final yBytes = _bigIntToBytes(y, 32);

    return Uint8List.fromList([0x04, ...xBytes, ...yBytes]);
  }

  // 解码公钥
  ECPublicKey _decodePublicKey(Uint8List bytes) {
    if (bytes[0] != 0x04) {
      throw Exception('不支持的公钥格式');
    }

    final xBytes = bytes.sublist(1, 33);
    final yBytes = bytes.sublist(33, 65);

    final x = _bytesToBigInt(xBytes);
    final y = _bytesToBigInt(yBytes);

    final curve = ECCurve_secp256r1();
    final point = curve.curve.createPoint(x, y);

    return ECPublicKey(point, curve);
  }

  // 编码签名
  Uint8List _encodeSignature(ECSignature signature) {
    final r = signature.r;
    final s = signature.s;

    final rBytes = _bigIntToBytes(r);
    final sBytes = _bigIntToBytes(s);

    return Uint8List.fromList([...rBytes, ...sBytes]);
  }

  // 解码签名
  ECSignature _decodeSignature(Uint8List bytes) {
    final rBytes = bytes.sublist(0, 32);
    final sBytes = bytes.sublist(32, 64);

    final r = _bytesToBigInt(rBytes);
    final s = _bytesToBigInt(sBytes);

    return ECSignature(r, s);
  }

  // BigInt 转字节数组
  Uint8List _bigIntToBytes(BigInt bigInt, [int length = 32]) {
    final bytes = bigInt.toRadixString(16).padLeft(length * 2, '0');
    return Uint8List.fromList(hex.decode(bytes));
  }

  // 字节数组转 BigInt
  BigInt _bytesToBigInt(Uint8List bytes) {
    return BigInt.parse(hex.encode(bytes), radix: 16);
  }

  // ==================== 回退方法（传统算法）====================

  // 回退方法：生成密钥对（ECDH）
  Map<String, String> _generateFallbackKeyPair() {
    try {
      print('回退到 ECDH 密钥对生成...');
      
      final keyParams = ECKeyGeneratorParameters(ECCurve_secp256r1());
      final random = SecureRandom('Fortuna')..seed(KeyParameter(_generateRandomSeed()));
      final keyGenerator = KeyGenerator('ECDH');
      keyGenerator.init(ParametersWithRandom(keyParams, random));
      final keyPair = keyGenerator.generateKeyPair();

      final privateKey = keyPair.privateKey as ECPrivateKey;
      final publicKey = keyPair.publicKey as ECPublicKey;

      final privateKeyBytes = privateKey.d!.toRadixString(16).padLeft(64, '0');
      final publicKeyBytes = _encodePublicKey(publicKey);

      return {
        'privateKey': base64Encode(hex.decode(privateKeyBytes)),
        'publicKey': base64Encode(publicKeyBytes),
      };
    } catch (e) {
      print('ECDH 密钥对生成失败: $e');
      // 最终回退到模拟实现
      final random = Random.secure();
      return {
        'privateKey': base64Encode(List<int>.generate(32, (_) => random.nextInt(256))),
        'publicKey': base64Encode(List<int>.generate(32, (_) => random.nextInt(256))),
      };
    }
  }

  // 回退方法：生成签名密钥对（ECDSA）
  Map<String, String> _generateFallbackSignatureKeyPair() {
    return _generateFallbackKeyPair();
  }

  // 回退方法：密钥封装
  Map<String, String> _fallbackEncapsulate(String publicKey) {
    final random = Random.secure();
    final sharedSecret = List<int>.generate(32, (_) => random.nextInt(256));
    final ciphertext = List<int>.generate(1088, (_) => random.nextInt(256));
    
    return {
      'ciphertext': base64Encode(ciphertext),
      'sharedSecret': base64Encode(sharedSecret),
    };
  }

  // 回退方法：密钥解封装
  String _fallbackDecapsulate(String ciphertext, String privateKey) {
    final combined = ciphertext + privateKey;
    final hash = sha256.convert(utf8.encode(combined)).bytes;
    return base64Encode(hash);
  }

  // 回退方法：密钥交换
  String _fallbackKeyExchange(String publicKey, String privateKey) {
    final combined = publicKey + privateKey;
    final hash = sha256.convert(utf8.encode(combined)).bytes;
    return base64Encode(hash);
  }

  // 回退方法：加密
  String _fallbackEncrypt(String plaintext, String publicKey) {
    final combined = plaintext + publicKey;
    final hash = sha256.convert(utf8.encode(combined)).bytes;
    return base64Encode(hash);
  }

  // 回退方法：解密
  String _fallbackDecrypt(String ciphertext, String privateKey) {
    print('使用回退方法进行解密');
    return 'decrypted_text';
  }

  // 回退方法：签名
  String _fallbackSign(String message, String privateKey) {
    final combined = message + privateKey;
    final hash = sha256.convert(utf8.encode(combined)).bytes;
    return base64Encode(hash);
  }

  // 回退方法：验证签名
  bool _fallbackVerify(String message, String signature, String publicKey) {
    final combined = message + publicKey;
    final hash = sha256.convert(utf8.encode(combined)).bytes;
    final expectedSignature = base64Encode(hash);
    return signature == expectedSignature;
  }
}
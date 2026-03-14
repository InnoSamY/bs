import 'package:flutter_test/flutter_test.dart';
import 'package:quanta_talk/services/crypto_service.dart';
import 'package:quanta_talk/services/ml_dsa.dart';

void main() {
  group('ML-DSA 后量子签名测�?, () {
    test('ML-DSA 密钥对生成测�?, () {
      print('\n========== ML-DSA-2 密钥对生成测�?==========');
      final keyPair = MlDsa.generateKeyPair(level: 2);
      
      expect(keyPair['publicKey'], isNotNull);
      expect(keyPair['privateKey'], isNotNull);
      expect(keyPair['publicKey']!.isNotEmpty, true);
      expect(keyPair['privateKey']!.isNotEmpty, true);
      
      print('公钥: ${keyPair['publicKey']}');
      print('私钥: ${keyPair['privateKey']}');
    });

    test('ML-DSA 签名和验证测�?, () {
      print('\n========== ML-DSA 签名验证测试 ==========');
      
      // 生成密钥�?      final keyPair = MlDsa.generateKeyPair(level: 2);
      final publicKey = keyPair['publicKey']!;
      final privateKey = keyPair['privateKey']!;
      
      // 测试消息
      const message = '这是一条测试消息，用于验证ML-DSA后量子签名算�?;
      
      print('原始消息: $message');
      
      // 签名
      final signature = MlDsa.sign(message, privateKey);
      print('签名: $signature');
      
      // 验证签名
      final isValid = MlDsa.verify(message, signature, publicKey);
      print('签名验证结果: $isValid');
      
      expect(isValid, true);
    });

    test('ML-DSA 错误签名验证测试', () {
      print('\n========== ML-DSA 错误签名验证测试 ==========');
      
      // 生成密钥�?      final keyPair = MlDsa.generateKeyPair(level: 2);
      final publicKey = keyPair['publicKey']!;
      final privateKey = keyPair['privateKey']!;
      
      // 签名
      final signature = MlDsa.sign('原始消息', privateKey);
      
      // 使用篡改的消息验�?      final isValid = MlDsa.verify('篡改的消�?, signature, publicKey);
      print('使用篡改消息验证结果: $isValid');
      
      expect(isValid, false);
    });

    test('ML-DSA 不同安全级别测试', () {
      print('\n========== ML-DSA 不同安全级别测试 ==========');
      
      for (var level in [2, 3, 5]) {
        print('\n--- ML-DSA-$level (${level == 2 ? '128' : level == 3 ? '192' : '256'}位安�? ---');
        final keyPair = MlDsa.generateKeyPair(level: level);
        print('公钥长度: ${keyPair['publicKey']!.length}');
        print('私钥长度: ${keyPair['privateKey']!.length}');
      }
    });
  });

  group('CryptoService 集成测试', () {
    test('CryptoService 后量子签名测�?, () {
      print('\n========== CryptoService 后量子签名测�?==========');
      
      final cryptoService = CryptoService();
      
      // 生成签名密钥�?      final keyPair = cryptoService.generateSignatureKeyPair();
      final publicKey = keyPair['publicKey']!;
      final privateKey = keyPair['privateKey']!;
      
      print('签名公钥长度: ${publicKey.length}');
      print('签名私钥长度: ${privateKey.length}');
      
      // 测试消息
      const message = '测试CryptoService的ML-DSA签名功能';
      
      // 签名
      final signature = cryptoService.sign(message, privateKey);
      print('签名长度: ${signature.length}');
      
      // 验证签名
      final isValid = cryptoService.verify(message, signature, publicKey);
      print('验证结果: $isValid');
      
      expect(isValid, true);
    });

    test('CryptoService 完整加密流程测试', () {
      print('\n========== CryptoService 完整加密流程测试 ==========');
      
      final cryptoService = CryptoService();
      
      // 步骤1: 生成ML-KEM密钥�?      print('\n--- 步骤1: 生成ML-KEM密钥�?---');
      final encKeyPair = cryptoService.generateKeyPair();
      print('加密公钥长度: ${encKeyPair['publicKey']!.length}');
      print('加密私钥长度: ${encKeyPair['privateKey']!.length}');
      
      // 步骤2: 生成ML-DSA密钥�?      print('\n--- 步骤2: 生成ML-DSA密钥�?---');
      final sigKeyPair = cryptoService.generateSignatureKeyPair();
      print('签名公钥长度: ${sigKeyPair['publicKey']!.length}');
      print('签名私钥长度: ${sigKeyPair['privateKey']!.length}');
      
      // 步骤3: 加密消息
      print('\n--- 步骤3: 加密消息 ---');
      const plaintext = '这是一条需要加密和签名的敏感消�?;
      final ciphertext = cryptoService.encrypt(plaintext, encKeyPair['publicKey']!);
      print('明文: $plaintext');
      print('密文长度: ${ciphertext.length}');
      
      // 步骤4: 签名消息
      print('\n--- 步骤4: 签名消息 ---');
      final signature = cryptoService.sign(plaintext, sigKeyPair['privateKey']!);
      print('签名长度: ${signature.length}');
      
      // 步骤5: 解密消息
      print('\n--- 步骤5: 解密消息 ---');
      final decrypted = cryptoService.decrypt(ciphertext, encKeyPair['privateKey']!);
      print('解密�? $decrypted');
      
      // 步骤6: 验证签名
      print('\n--- 步骤6: 验证签名 ---');
      final isValid = cryptoService.verify(plaintext, signature, sigKeyPair['publicKey']!);
      print('签名验证: $isValid');
      
      print('\n�?完整加密流程测试通过�?);
      
      expect(decrypted, equals(plaintext));
      expect(isValid, true);
    });
  });
}


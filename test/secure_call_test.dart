import 'package:flutter_test/flutter_test.dart';
import 'package:quanta_talk/services/crypto_service.dart';

void main() {
  group('安全通话加密测试', () {
    late CryptoService cryptoService;

    setUp(() {
      cryptoService = CryptoService();
    });

    test('密钥初始化测�?, () {
      print('\n========== 密钥初始化测�?==========');

      final signatureKeyPair = cryptoService.generateSignatureKeyPair();
      final encryptionKeyPair = cryptoService.generateKeyPair();

      expect(signatureKeyPair['publicKey'], isNotNull);
      expect(signatureKeyPair['privateKey'], isNotNull);
      expect(encryptionKeyPair['publicKey'], isNotNull);
      expect(encryptionKeyPair['privateKey'], isNotNull);

      print('ML-DSA 签名公钥长度: ${signatureKeyPair['publicKey']!.length}');
      print('ML-KEM 加密公钥长度: ${encryptionKeyPair['publicKey']!.length}');
    });

    test('通话签名生成和验证测�?, () {
      print('\n========== 通话签名测试 ==========');

      final keyPair = cryptoService.generateSignatureKeyPair();
      final peerId = 'user_123';
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();

      final message = 'call_request:$peerId:$timestamp';
      print('签名消息: $message');

      final signature = cryptoService.sign(message, keyPair['privateKey']!);
      print('签名: $signature');

      final isValid = cryptoService.verify(message, signature, keyPair['publicKey']!);
      print('验证结果: $isValid');

      expect(isValid, true);

      final wrongMessage = 'call_request:user_456:$timestamp';
      final isValidWrong = cryptoService.verify(wrongMessage, signature, keyPair['publicKey']!);
      print('错误消息验证结果: $isValidWrong');

      expect(isValidWrong, false);
    });

    test('ML-KEM 密钥封装和解封装测试', () {
      print('\n========== ML-KEM 密钥封装测试 ==========');

      final keyPair = cryptoService.generateKeyPair();
      final publicKey = keyPair['publicKey']!;

      final encapsulation = cryptoService.encapsulate(publicKey);
      final sharedSecret = encapsulation['sharedSecret']!;
      final ciphertext = encapsulation['ciphertext']!;

      print('共享密钥长度: ${sharedSecret.length}');
      print('密文长度: ${ciphertext.length}');

      expect(sharedSecret.isNotEmpty, true);
      expect(ciphertext.isNotEmpty, true);

      print('\n========== ML-KEM 密钥解封装测�?==========');

      final decapsulatedSecret = cryptoService.decapsulate(ciphertext, keyPair['privateKey']!);

      print('解封装共享密钥长�? ${decapsulatedSecret.length}');
      print('两个密钥是否相同: ${sharedSecret == decapsulatedSecret}');

      expect(decapsulatedSecret, equals(sharedSecret));
    });

    test('完整的安全会话建立测�?, () {
      print('\n========== 完整安全会话测试 ==========');

      print('\n--- 用户A生成密钥�?---');
      final userAKeys = cryptoService.generateKeyPair();
      final userAPublicKey = userAKeys['publicKey']!;
      print('用户A公钥长度: ${userAPublicKey.length}');

      print('\n--- 用户B生成密钥�?---');
      final userBKeys = cryptoService.generateKeyPair();
      final userBPublicKey = userBKeys['publicKey']!;
      print('用户B公钥长度: ${userBPublicKey.length}');

      print('\n--- 用户A封装用户B的公�?---');
      final encapsulationA = cryptoService.encapsulate(userBPublicKey);
      final sharedSecretA = encapsulationA['sharedSecret']!;
      final ciphertextA = encapsulationA['ciphertext']!;
      print('用户A共享密钥: ${sharedSecretA.substring(0, 20)}...');
      print('密文长度: ${ciphertextA.length}');

      print('\n--- 用户B解封装密�?---');
      final sharedSecretB = cryptoService.decapsulate(ciphertextA, userBKeys['privateKey']!);
      print('用户B共享密钥: ${sharedSecretB.substring(0, 20)}...');

      print('\n--- 验证双方密钥相同 ---');
      final keysMatch = sharedSecretA == sharedSecretB;
      print('密钥匹配: $keysMatch');
      expect(keysMatch, true);
    });

    test('安全消息加密和解密测�?, () {
      print('\n========== 安全消息加密测试 ==========');

      final keyPair = cryptoService.generateKeyPair();
      final encapsulation = cryptoService.encapsulate(keyPair['publicKey']!);
      final sessionKey = encapsulation['sharedSecret']!;

      final message = '这是一条安全消息，包含敏感信息';
      print('原始消息: $message');

      final encrypted = cryptoService.aesEncrypt(message, sessionKey);
      print('加密后长�? ${encrypted.length}');

      final decrypted = cryptoService.aesDecrypt(encrypted, sessionKey);
      print('解密后消�? $decrypted');

      expect(decrypted, equals(message));
    });

    test('完整通话流程模拟测试', () {
      print('\n========== 完整通话流程模拟 ==========');

      print('\n步骤1: 双方生成签名和加密密钥对');
      final userASignKeys = cryptoService.generateSignatureKeyPair();
      final userAEncKeys = cryptoService.generateKeyPair();
      final userBSignKeys = cryptoService.generateSignatureKeyPair();
      final userBEncKeys = cryptoService.generateKeyPair();

      print('用户A签名公钥: ${userASignKeys['publicKey']!.substring(0, 20)}...');
      print('用户B签名公钥: ${userBSignKeys['publicKey']!.substring(0, 20)}...');

      print('\n步骤2: 用户A发起通话，生成签�?);
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final callMessage = 'call_request:userB:$timestamp';
      final signatureA = cryptoService.sign(callMessage, userASignKeys['privateKey']!);
      print('通话签名: ${signatureA.substring(0, 20)}...');

      print('\n步骤3: 用户B验证签名');
      final isValid = cryptoService.verify(callMessage, signatureA, userASignKeys['publicKey']!);
      print('签名验证: $isValid');
      expect(isValid, true);

      print('\n步骤4: 用户B接受通话，进行密钥交�?);
      final encapsulation = cryptoService.encapsulate(userAEncKeys['publicKey']!);
      final sessionKeyB = encapsulation['sharedSecret']!;
      final ciphertext = encapsulation['ciphertext']!;
      print('会话密钥已生�?);

      print('\n步骤5: 用户A解封装获取会话密�?);
      final sessionKeyA = cryptoService.decapsulate(ciphertext, userAEncKeys['privateKey']!);
      print('双方会话密钥匹配: ${sessionKeyA == sessionKeyB}');
      expect(sessionKeyA, equals(sessionKeyB));

      print('\n步骤6: 用户A发送加密消�?);
      final messageA = '你好，这是安全通话';
      final encryptedA = cryptoService.aesEncrypt(messageA, sessionKeyA);
      final signatureMsgA = cryptoService.sign(encryptedA, userASignKeys['privateKey']!);
      print('加密消息: ${encryptedA.substring(0, 20)}...');

      print('\n步骤7: 用户B接收并解密消�?);
      final isValidMsg = cryptoService.verify(encryptedA, signatureMsgA, userASignKeys['publicKey']!);
      print('消息签名验证: $isValidMsg');
      expect(isValidMsg, true);

      final decryptedB = cryptoService.aesDecrypt(encryptedA, sessionKeyB);
      print('解密消息: $decryptedB');
      expect(decryptedB, equals(messageA));

      print('\n�?完整通话流程测试通过�?);
    });

    test('性能测试：密钥生成和加密操作耗时', () {
      print('\n========== 性能测试 ==========');

      final stopwatch = Stopwatch();

      print('\n--- ML-DSA 签名密钥生成 ---');
      stopwatch.start();
      for (int i = 0; i < 5; i++) {
        cryptoService.generateSignatureKeyPair();
      }
      stopwatch.stop();
      print('5次签名密钥生成耗时: ${stopwatch.elapsedMilliseconds}ms');
      print('平均每次: ${stopwatch.elapsedMilliseconds / 5}ms');

      stopwatch.reset();

      print('\n--- ML-KEM 加密密钥生成 ---');
      stopwatch.start();
      for (int i = 0; i < 5; i++) {
        cryptoService.generateKeyPair();
      }
      stopwatch.stop();
      print('5次加密密钥生成耗时: ${stopwatch.elapsedMilliseconds}ms');
      print('平均每次: ${stopwatch.elapsedMilliseconds / 5}ms');

      stopwatch.reset();

      final keyPair = cryptoService.generateKeyPair();
      final encapsulation = cryptoService.encapsulate(keyPair['publicKey']!);
      final sessionKey = encapsulation['sharedSecret']!;
      final message = '测试消息' * 100;

      stopwatch.start();
      for (int i = 0; i < 100; i++) {
        cryptoService.aesEncrypt(message, sessionKey);
      }
      stopwatch.stop();
      print('\n100次AES加密耗时: ${stopwatch.elapsedMilliseconds}ms');
      print('平均每次: ${stopwatch.elapsedMilliseconds / 100}ms');
    });
  });
}


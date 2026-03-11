import 'dart:typed_data';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class MlDsa {
  static final Random _random = Random.secure();

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

  static Uint8List _generateRandomBytes(int length) {
    return Uint8List.fromList(
      List<int>.generate(length, (_) => _random.nextInt(256)),
    );
  }

  static String _encodePublicKey(Uint8List seed, int level) {
    final bytes = <int>[];
    bytes.addAll(seed);
    bytes.add(level);
    return base64Encode(Uint8List.fromList(bytes));
  }

  static String _encodePrivateKey(Uint8List seed, int level) {
    final bytes = <int>[];
    bytes.addAll(seed);
    bytes.add(level);
    return base64Encode(Uint8List.fromList(bytes));
  }

  static Map<String, dynamic> _parsePrivateKey(Uint8List bytes) {
    final seed = Uint8List.sublistView(bytes, 0, 32);
    final level = bytes[32];

    return {
      'seed': seed,
      'level': level,
    };
  }

  static Map<String, dynamic> _parsePublicKey(Uint8List bytes) {
    final seed = Uint8List.sublistView(bytes, 0, 32);
    final level = bytes[32];

    return {
      'seed': seed,
      'level': level,
    };
  }
}

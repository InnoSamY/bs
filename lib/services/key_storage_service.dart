import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class KeyStorageService {
  static const _kemPublicKey = 'kemPublicKey';
  static const _kemPrivateKey = 'kemPrivateKey';
  static const _sigPublicKey = 'sigPublicKey';
  static const _sigPrivateKey = 'sigPrivateKey';

  Future<void> saveKemKeyPair({
    required String publicKey,
    required String privateKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kemPublicKey, publicKey);
    await prefs.setString(_kemPrivateKey, privateKey);
  }

  Future<void> saveSignatureKeyPair({
    required String publicKey,
    required String privateKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sigPublicKey, publicKey);
    await prefs.setString(_sigPrivateKey, privateKey);
  }

  Future<Map<String, String>?> getKemKeyPair() async {
    final prefs = await SharedPreferences.getInstance();
    final publicKey = prefs.getString(_kemPublicKey);
    final privateKey = prefs.getString(_kemPrivateKey);
    if (publicKey == null || privateKey == null) return null;
    return {'publicKey': publicKey, 'privateKey': privateKey};
  }

  Future<Map<String, String>?> getSignatureKeyPair() async {
    final prefs = await SharedPreferences.getInstance();
    final publicKey = prefs.getString(_sigPublicKey);
    final privateKey = prefs.getString(_sigPrivateKey);
    if (publicKey == null || privateKey == null) return null;
    return {'publicKey': publicKey, 'privateKey': privateKey};
  }

  Future<bool> hasAllKeys() async {
    final kem = await getKemKeyPair();
    final sig = await getSignatureKeyPair();
    return kem != null && sig != null;
  }

  Future<void> clearKeys() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kemPublicKey);
    await prefs.remove(_kemPrivateKey);
    await prefs.remove(_sigPublicKey);
    await prefs.remove(_sigPrivateKey);
  }

  Future<Map<String, String>> exportAllPublicKeys() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'encryptionPublicKey': prefs.getString(_kemPublicKey) ?? '',
      'signaturePublicKey': prefs.getString(_sigPublicKey) ?? '',
    };
  }
}
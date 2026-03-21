import 'package:encrypt/encrypt.dart' as enc;
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'dart:typed_data'; // 💡 补上这把“扳手”，Uint8List 报错就消失了

class EncryptionService {
  
  // 💡 派生密钥：根据用户输入的单篇密码生成 AES 密钥
  static enc.Key _deriveKey(String password) {
    final hash = sha256.convert(utf8.encode(password)).bytes;
    return enc.Key(Uint8List.fromList(hash));
  }

  // 💡 AES-256-GCM 加密
  static String encrypt(String plainText, String password) {
    final key = _deriveKey(password);
    final iv = enc.IV.fromLength(16); // 初始向量
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
    
    final encrypted = encrypter.encrypt(plainText, iv: iv);
    // 将 IV 和密文一起保存，方便解密
    return "${iv.base64}:${encrypted.base64}";
  }

  // 💡 AES-256-GCM 解密
  static String decrypt(String combinedText, String password) {
    try {
      final parts = combinedText.split(':');
      final iv = enc.IV.fromBase64(parts[0]);
      final cipherText = parts[1];
      
      final key = _deriveKey(password);
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
      
      return encrypter.decrypt64(cipherText, iv: iv);
    } catch (e) {
      return "解密失败：密码错误";
    }
  }

  // 生成密码哈希，仅用于校验，不用于解密
  static String hashPassword(String password) {
    return sha256.convert(utf8.encode(password)).toString();
  }
  // 💡 校验密码是否匹配存储的哈希值
  static bool verifyPassword(String inputPassword, String? storedHash) {
    if (storedHash == null) return false;
    return hashPassword(inputPassword) == storedHash;
  }
}
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:purevideo/core/utils/supported_enum.dart';

class SecureStorageService {
  static const _storage = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true));

  static Future<void> saveData(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      debugPrint('SecureStorage write failed ($key): $e');
    }
  }

  static Future<String?> getData(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      debugPrint('SecureStorage read failed ($key): $e');
      try {
        await _storage.delete(key: key);
      } catch (_) {}
      return null;
    }
  }

  static Future<void> deleteData(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (e) {
      debugPrint('SecureStorage delete failed ($key): $e');
    }
  }

  static Future<void> clearStorage() async {
    try {
      await _storage.deleteAll();
    } catch (e) {
      debugPrint('SecureStorage deleteAll failed: $e');
    }
  }

  static Future<void> saveServiceData(
    SupportedService service,
    String key,
    String value,
  ) async {
    await saveData('$service:$key', value);
  }

  static Future<String?> getServiceData(
    SupportedService service,
    String key,
  ) async {
    return await getData('$service:$key');
  }

  static Future<void> deleteServiceData(
    SupportedService service,
    String key,
  ) async {
    await deleteData('$service:$key');
  }

  static Future<void> clearServiceStorage(SupportedService service) async {
    try {
      final allEntries = await _storage.readAll();
      for (final key in allEntries.keys) {
        if (key.startsWith('$service:')) {
          await deleteData(key);
        }
      }
    } catch (e) {
      debugPrint('SecureStorage clearServiceStorage failed: $e');
    }
  }
}

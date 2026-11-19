import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DeviceUtils {
  static const MethodChannel _channel = MethodChannel('purevideo/device');
  static bool _isTv = false;

  static bool get isTv => _isTv;

  static Future<void> init() async {
    try {
      final res = await _channel.invokeMethod<bool>('isTv');
      _isTv = res ?? false;
    } catch (_) {
      _isTv = false;
    }
  }

  static bool isWideLayout(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return _isTv || size.width >= 680;
  }
}

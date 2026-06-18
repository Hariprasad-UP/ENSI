import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../input/input_backend.dart';
import '../models/device.dart';

/// Builds and persists this device's stable [DeviceInfo] identity (FR-2/FR-4).
class IdentityService {
  static const _idKey = 'ensi.device.id';

  /// Load (or create + persist) this device's identity.
  static Future<DeviceInfo> load(InputBackend backend) async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_idKey);
    if (id == null) {
      id = const Uuid().v4();
      await prefs.setString(_idKey, id);
    }

    final name = await _deviceName();
    final displays = await backend.queryDisplays();

    return DeviceInfo(
      id: id,
      name: name,
      platform: _currentPlatform(),
      displays: displays,
      canReceiveInput: backend.canReceiveInput,
    );
  }

  static DevicePlatform _currentPlatform() {
    if (Platform.isWindows) return DevicePlatform.windows;
    if (Platform.isMacOS) return DevicePlatform.macos;
    if (Platform.isLinux) return DevicePlatform.linux;
    if (Platform.isAndroid) return DevicePlatform.android;
    if (Platform.isIOS) return DevicePlatform.ios;
    return DevicePlatform.unknown;
  }

  static Future<String> _deviceName() async {
    final info = DeviceInfoPlugin();
    try {
      if (Platform.isWindows) return (await info.windowsInfo).computerName;
      if (Platform.isMacOS) return (await info.macOsInfo).computerName;
      if (Platform.isLinux) return (await info.linuxInfo).name;
      if (Platform.isAndroid) return (await info.androidInfo).model;
      if (Platform.isIOS) return (await info.iosInfo).name;
    } catch (_) {
      // fall through
    }
    return Platform.localHostname;
  }
}

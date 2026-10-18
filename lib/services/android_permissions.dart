import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Requests only permissions supported by the Android version on the device.
class AndroidPermissions {
  static const _platform = MethodChannel('com.offgridsos/platform');

  static List<Permission> nearbyPermissionsForSdk(int sdk) => [
    Permission.locationWhenInUse,
    if (sdk >= 31) ...[
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
    ],
    if (sdk >= 33) Permission.nearbyWifiDevices,
  ];

  static Future<Map<Permission, PermissionStatus>> requestNearby() async {
    final sdk = await _platform.invokeMethod<int>('getAndroidSdkVersion');
    if (sdk == null) throw StateError('ไม่สามารถอ่านเวอร์ชัน Android ได้');
    return nearbyPermissionsForSdk(sdk).request();
  }

  static Future<bool> requestBluetooth() async {
    final sdk = await _platform.invokeMethod<int>('getAndroidSdkVersion');
    if (sdk == null) return false;
    if (sdk < 31) return true;
    final result = await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
    ].request();
    return result.values.every((status) => status.isGranted);
  }
}

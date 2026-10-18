import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppNotifications with WidgetsBindingObserver {
  static final instance = AppNotifications();
  static const channel = MethodChannel('com.offgridsos/platform');
  final enabled = ValueNotifier<bool>(false);
  final background = ValueNotifier<bool>(false);
  bool _observing = false;
  bool foreground = true;
  String? activeThread;
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground) refresh();
  }

  Future<void> refresh() async {
    if (!supported) return;
    try {
      enabled.value =
          await channel.invokeMethod<bool>('notificationsEnabled') ?? false;
    } catch (_) {}
  }

  Future<bool> request() async {
    if (!supported) return false;
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    try {
      final sdk = await channel.invokeMethod<int>('getAndroidSdkVersion') ?? 0;
      if (sdk >= 33) await Permission.notification.request();
      await refresh();
      return enabled.value;
    } catch (_) {
      return false;
    }
  }

  Future<void> startBackground() async {
    if (!supported) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('background_messaging') == false) return;
    await request();
    try {
      background.value =
          await channel.invokeMethod<bool>('startMessaging') ?? false;
    } catch (_) {
      background.value = false;
    }
  }

  Future<void> setBackground(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('background_messaging', value);
    if (value) {
      await startBackground();
    } else {
      await stopBackground();
    }
  }

  Future<void> stopBackground() async {
    if (!supported) return;
    try {
      await channel.invokeMethod<void>('stopMessaging');
    } catch (_) {}
    background.value = false;
  }

  Future<void> show({
    required String id,
    required String title,
    required String text,
    String? thread,
  }) async {
    if (!supported ||
        (foreground && activeThread == thread && thread != null)) {
      return;
    }
    try {
      await channel.invokeMethod<void>('showMessage', {
        'id': id,
        'title': title,
        'text': text,
        'thread': thread,
      });
    } catch (_) {}
  }
}

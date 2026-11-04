import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppNotifications with WidgetsBindingObserver {
  static final instance = AppNotifications();
  static const channel = MethodChannel('com.offgridsos/platform');
  final enabled = ValueNotifier<bool>(false);
  final sound = ValueNotifier<bool>(true);
  final taps = ValueNotifier<int>(0);
  bool _listeningForTaps = false;

  /// Notification taps are delivered through a counter rather than carrying
  /// payloads in the stream. The payload remains in Android's pending slot and
  /// is consumed exactly once by [takeChatTap]/[takeSosTap].
  void listenForTaps() {
    if (!supported || _listeningForTaps) return;
    _listeningForTaps = true;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'notificationTap') taps.value++;
    });
  }

  final background = ValueNotifier<bool>(false);
  bool _observing = false;
  bool foreground = true;
  String? activeThread;
  Object? activeRoomToken;
  final activeThreadAliases = <String>{};
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
      sound.value =
          await channel.invokeMethod<bool>('notificationSound') ?? true;
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

  Future<void> setSound(bool value) async {
    if (!supported) return;
    try {
      final saved = await channel.invokeMethod<bool>('setNotificationSound', {
        'enabled': value,
      });
      if (saved != null) sound.value = saved;
    } catch (_) {}
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
    String? sosDevice,
    String? owner,
    String? transport,
  }) async {
    if (!supported ||
        (foreground &&
            thread != null &&
            (activeThread == thread || activeThreadAliases.contains(thread)))) {
      return;
    }
    try {
      await channel.invokeMethod<void>('showMessage', {
        'id': id,
        'title': title,
        'text': text,
        'thread': thread,
        'sosDevice': sosDevice,
        'owner': owner,
        'transport': transport,
      });
    } catch (_) {}
  }

  Future<Map<String, String>?> takeSosTap() async {
    if (!supported) return null;
    try {
      final data = await channel.invokeMapMethod<String, String>('takeSosTap');
      return data;
    } catch (_) {
      return null;
    }
  }

  Future<void> cancel(String id) async {
    if (!supported) return;
    try {
      await channel.invokeMethod<void>('cancelMessage', {'id': id});
    } catch (_) {}
  }

  Future<Map<String, String>?> takeChatTap() async {
    if (!supported) return null;
    try {
      final data = await channel.invokeMapMethod<String, String>('takeChatTap');
      if (data == null ||
          (data['owner']?.isEmpty ?? true) ||
          (data['thread']?.isEmpty ?? true) ||
          !['nearby', 'cloud'].contains(data['transport'])) {
        return null;
      }
      return data;
    } catch (_) {
      return null;
    }
  }
}

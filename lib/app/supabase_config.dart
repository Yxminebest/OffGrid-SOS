import 'package:flutter/foundation.dart';

class SupabaseConfig {
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://evfopzvqsngrunopxgvl.supabase.co',
  );

  static const String publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  static const String _webRedirectOverride = String.fromEnvironment(
    'SUPABASE_WEB_REDIRECT',
  );

  static String get webRedirect {
    if (_webRedirectOverride.isNotEmpty) {
      return _webRedirectOverride;
    }
    return Uri.base.origin;
  }

  static const String iosRedirect =
      'com.kittaporn.offgridsos://login-callback/';

  static const String androidRedirect =
      'com.kittaporn.offgridsos://login-callback/';

  static String get mobileRedirect =>
      defaultTargetPlatform == TargetPlatform.android
      ? androidRedirect
      : iosRedirect;

  static String get emailRedirectTo => kIsWeb ? webRedirect : mobileRedirect;

  static String get passwordRecoveryRedirectTo =>
      kIsWeb ? webRedirect : mobileRedirect;

  static bool get isConfigured => url.isNotEmpty && publishableKey.isNotEmpty;
}

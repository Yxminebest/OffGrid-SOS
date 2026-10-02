import 'package:flutter/foundation.dart';

class SupabaseConfig {
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://evfopzvqsngrunopxgvl.supabase.co',
  );

  static const String publishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static const String webRedirect = 'http://localhost:3000';
  static const String iosRedirect =
      'com.kittaporn.offgridsos://login-callback/';

  static String get emailRedirectTo =>
      kIsWeb ? webRedirect : iosRedirect;

  static bool get isConfigured =>
      url.isNotEmpty && publishableKey.isNotEmpty;
}

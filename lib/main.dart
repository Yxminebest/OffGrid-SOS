import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/supabase_config.dart';
import 'app/theme.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_shell.dart';
import 'models/user.dart';
import 'services/auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!SupabaseConfig.isConfigured) {
    runApp(const _MissingSupabaseKeyApp());
    return;
  }

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  runApp(const OffGridSosApp());
}

class OffGridSosApp extends StatefulWidget {
  const OffGridSosApp({super.key});

  @override
  State<OffGridSosApp> createState() =>
      _OffGridSosAppState();
}

class _OffGridSosAppState extends State<OffGridSosApp> {
  AppUser? _me;
  bool _loading = true;

  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();

    _restore();

    _authSubscription =
        AuthService.authStateChanges.listen(
      (data) async {
        switch (data.event) {
          case AuthChangeEvent.signedIn:
          case AuthChangeEvent.initialSession:
          case AuthChangeEvent.userUpdated:
          case AuthChangeEvent.tokenRefreshed:
            if (data.session != null) {
              await _restore();
            }
            break;

          case AuthChangeEvent.signedOut:
            if (mounted) {
              setState(() {
                _me = null;
                _loading = false;
              });
            }
            break;

          default:
            break;
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        // Supabase can emit refresh/network errors while offline.
        // Offline-First mode must not crash because of that.
      },
    );
  }

  Future<void> _restore() async {
    try {
      final identity =
          await AuthService.restoreIdentity();

      if (!mounted) return;

      setState(() {
        _me = identity;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _logout() async {
    await AuthService.clear();

    if (!mounted) return;

    setState(() {
      _me = null;
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'offgrid-sos',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: _loading
          ? const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            )
          : _me == null
              ? LoginScreen(
                  onDone: (identity) {
                    setState(() {
                      _me = identity;
                    });
                  },
                )
              : HomeShell(
                  me: _me!,
                  onLogout: _logout,
                ),
    );
  }
}

class _MissingSupabaseKeyApp extends StatelessWidget {
  const _MissingSupabaseKeyApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: 560),
                child: Column(
                  mainAxisAlignment:
                      MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.key_off_outlined,
                      size: 64,
                      color: AppColors.error,
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'ยังไม่ได้ใส่ Supabase Publishable Key',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const SelectableText(
                      'flutter run -d chrome --web-port=3000 '
                      '--dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_KEY',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Project URL: ${SupabaseConfig.url}',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

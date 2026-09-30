import 'package:flutter/material.dart';
import 'app/theme.dart';
import 'features/home/home_shell.dart';
import 'features/welcome/welcome_screen.dart';
import 'models/local_identity.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RescueLinkApp());
}

class RescueLinkApp extends StatefulWidget {
  const RescueLinkApp({super.key});

  @override
  State<RescueLinkApp> createState() => _RescueLinkAppState();
}

class _RescueLinkAppState extends State<RescueLinkApp> {
  LocalIdentity? _me;

  Future<void> _logout() async {
    await IdentityService.clear();
    if (!mounted) return;
    setState(() => _me = null);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RescueLink',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: _me == null
          ? WelcomeScreen(onDone: (identity) => setState(() => _me = identity))
          : HomeShell(me: _me!, onLogout: _logout),
    );
  }
}

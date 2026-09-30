import 'package:flutter/material.dart';
import 'app/theme.dart';
import 'features/home/home_shell.dart';
import 'features/welcome/welcome_screen.dart';
import 'models/local_identity.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OffGridApp());
}

class OffGridApp extends StatefulWidget {
  const OffGridApp({super.key});

  @override
  State<OffGridApp> createState() => _OffGridAppState();
}

class _OffGridAppState extends State<OffGridApp> {
  LocalIdentity? _me;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    IdentityService.load().then((id) {
      if (!mounted) return;
      setState(() {
        _me = id;
        _loading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RescueLink',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: _loading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _me == null
              ? WelcomeScreen(onDone: (id) => setState(() => _me = id))
              : HomeShell(me: _me!),
    );
  }
}

import 'package:flutter/material.dart';
import 'api.dart';
import 'chat_list.dart';

void main() => runApp(const FmChatApp());

class FmChatApp extends StatelessWidget {
  const FmChatApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'FM Chat',
        theme: ThemeData(colorSchemeSeed: const Color(0xFF0B4F6C), useMaterial3: true),
        home: const Gate(),
      );
}

class Gate extends StatefulWidget {
  const Gate({super.key});
  @override
  State<Gate> createState() => _GateState();
}

class _GateState extends State<Gate> {
  Map<String, dynamic>? _user;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Api.loadToken();
      _user = await Api.me();
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!),
            const SizedBox(height: 12),
            FilledButton(onPressed: _start, child: const Text('Coba lagi')),
          ]),
        ),
      );
    }
    if (_user == null) return LoginPage(onLogin: (u) => setState(() => _user = u));
    return HomePage(
      user: _user!,
      onLogout: () async {
        await Api.logout();
        if (mounted) setState(() => _user = null);
      },
    );
  }
}

class LoginPage extends StatefulWidget {
  final void Function(Map<String, dynamic>) onLogin;
  const LoginPage({super.key, required this.onLogin});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final u = await Api.login(_email.text.trim(), _pass.text);
      widget.onLogin(u);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('FM Chat', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pass,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                  onSubmitted: (_) => _busy ? null : _submit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Text(_busy ? 'Memproses...' : 'Masuk'),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  final Map<String, dynamic> user;
  final VoidCallback onLogout;
  const HomePage({super.key, required this.user, required this.onLogout});

  @override
  Widget build(BuildContext context) => ChatListPage(user: user, onLogout: onLogout);
}

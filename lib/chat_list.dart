import 'dart:async';
import 'package:flutter/material.dart';
import 'api.dart';

class ChatListPage extends StatefulWidget {
  final Map<String, dynamic> user;
  final VoidCallback onLogout;
  const ChatListPage({super.key, required this.user, required this.onLogout});
  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  List<dynamic> _items = [];
  bool _loading = true;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final data = await Api.getJson('/chats');
      if (mounted) {
        setState(() {
          _items = data as List;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && !silent) setState(() => _error = e.toString());
    }
    if (mounted && !silent) setState(() => _loading = false);
  }

  Color _warna(String s) {
    final m = RegExp(r'hsl\((\d+),(\d+)%,(\d+)%\)').firstMatch(s);
    if (m == null) return Colors.blueGrey;
    return HSLColor.fromAHSL(
      1,
      double.parse(m[1]!),
      int.parse(m[2]!) / 100,
      int.parse(m[3]!) / 100,
    ).toColor();
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!),
          const SizedBox(height: 12),
          FilledButton(onPressed: _load, child: const Text('Coba lagi')),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(silent: true),
      child: _items.isEmpty
          ? ListView(children: const [
              SizedBox(height: 120),
              Center(child: Text('Belum ada percakapan.')),
            ])
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: _items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final it = _items[i] as Map<String, dynamic>;
                final nama = (it['nama'] ?? '').toString();
                final belum = (it['belum'] ?? 0) as int;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _warna((it['warna'] ?? '').toString()),
                    foregroundColor: Colors.white,
                    child: it['grup'] == true
                        ? const Icon(Icons.group)
                        : Text(nama.isEmpty ? '?' : nama[0].toUpperCase()),
                  ),
                  title: Text(nama, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text((it['cuplikan'] ?? '').toString(),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text((it['waktu'] ?? '').toString(),
                          style: const TextStyle(fontSize: 12)),
                      if (belum > 0)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0B7A9E),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text('$belum',
                              style: const TextStyle(color: Colors.white, fontSize: 12)),
                        ),
                    ],
                  ),
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Ruang obrolan menyusul di langkah 3.')),
                  ),
                );
              },
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FM Chat'), actions: [
        TextButton(onPressed: widget.onLogout, child: const Text('Keluar')),
      ]),
      body: _body(),
    );
  }
}

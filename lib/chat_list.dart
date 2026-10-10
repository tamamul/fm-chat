import 'dart:async';
import 'package:flutter/material.dart';
import 'api.dart';
import 'chat_room.dart';

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
    _muatDariCache();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _muatDariCache() async {
    final c = await Api.readCache('chats');
    if (c is List && mounted && _items.isEmpty) {
      setState(() {
        _items = c;
        _loading = false;
      });
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && _items.isEmpty) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final data = await Api.getJson('/chats');
      Api.writeCache('chats', data);
      if (mounted) {
        setState(() {
          _items = data as List;
          _error = null;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          if (_items.isEmpty) _error = e.toString();
        });
      }
    }
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

  Future<void> _buka(bool grup, int id, String nama) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChatRoomPage(grup: grup, id: id, nama: nama)),
    );
    _load(silent: true);
  }

  Future<void> _chatBaru() async {
    List<dynamic> users;
    try {
      users = await Api.getJson('/pengguna') as List;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      return;
    }
    if (!mounted) return;
    final pilih = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Mulai chat dengan', style: TextStyle(fontWeight: FontWeight.bold))),
            ...users.map((u) => ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(u['name'].toString()),
                  subtitle: Text(u['role'].toString()),
                  onTap: () => Navigator.pop(ctx, Map<String, dynamic>.from(u)),
                )),
          ],
        ),
      ),
    );
    if (pilih == null || !mounted) return;
    await _buka(false, (pilih['id'] as num).toInt(), pilih['name'].toString());
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
                final grup = it['grup'] == true;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _warna((it['warna'] ?? '').toString()),
                    foregroundColor: Colors.white,
                    child: grup
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
                  onTap: () => _buka(grup, (it['id'] as num).toInt(), nama),
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
      floatingActionButton: FloatingActionButton(
        onPressed: _chatBaru,
        child: const Icon(Icons.edit),
      ),
    );
  }
}
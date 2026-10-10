import 'dart:io';
import 'package:flutter/material.dart';
import 'api.dart';
import 'chat_room.dart';

class SharedItem {
  final String? filePath;
  final String? text;
  final String name;

  SharedItem.file(String path)
      : filePath = path,
        text = null,
        name = path.split('/').last;

  SharedItem.text(String t)
      : filePath = null,
        text = t,
        name = t.length > 40 ? '${t.substring(0, 40)}...' : t;

  // Kalau jalurnya ada sebagai file, anggap file; kalau tidak, anggap teks/tautan.
  factory SharedItem.dariPath(String p) {
    if (File(p).existsSync()) return SharedItem.file(p);
    return SharedItem.text(p);
  }
}

class SharePage extends StatefulWidget {
  final List<SharedItem> items;
  const SharePage({super.key, required this.items});
  @override
  State<SharePage> createState() => _SharePageState();
}

class _SharePageState extends State<SharePage> {
  final _caption = TextEditingController();
  List<Map<String, dynamic>> _chats = [];
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  String? _error;
  bool _mengirim = false;
  String _progress = '';

  bool get _adaFile => widget.items.any((e) => e.filePath != null);

  List<Map<String, dynamic>> _toMaps(List raw) =>
      raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final cached = await Api.readCache('chats');
    if (cached is List && mounted) {
      setState(() {
        _chats = _toMaps(cached);
        _loading = false;
      });
    }
    try {
      final r = await Future.wait([Api.getJson('/chats'), Api.getJson('/pengguna')]);
      if (!mounted) return;
      setState(() {
        _chats = _toMaps(r[0] as List);
        _users = _toMaps(r[1] as List);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          if (_chats.isEmpty) _error = e.toString();
        });
      }
    }
  }

  String _ringkasan() {
    final n = widget.items.length;
    if (n == 1) return widget.items.first.name;
    final nama = widget.items.take(3).map((e) => e.name).join(', ');
    return '$n item: $nama${n > 3 ? ', ...' : ''}';
  }

  Future<void> _pilih(bool grup, int id, String nama) async {
    if (_mengirim) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Kirim ke $nama?'),
        content: Text(_ringkasan()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Kirim')),
        ],
      ),
    );
    if (ok != true) return;

    final path = grup ? '/grup/$id/kirim' : '/obrolan/$id';
    final caption = _caption.text.trim();
    final gagal = <String>[];
    var sukses = 0;
    setState(() => _mengirim = true);

    for (var i = 0; i < widget.items.length; i++) {
      final it = widget.items[i];
      if (mounted) setState(() => _progress = 'Mengirim ${i + 1} dari ${widget.items.length}...');
      try {
        if (it.filePath != null) {
          final size = await File(it.filePath!).length();
          if (size > 100 * 1024 * 1024) throw ApiError('lebih dari 100 MB');
          await Api.uploadFile(path, it.filePath!, it.name, caption: i == 0 ? caption : '');
        } else {
          var t = it.text!;
          if (t.length > 2000) t = t.substring(0, 2000);
          await Api.postJson(path, {'body': t});
        }
        sukses++;
      } catch (e) {
        gagal.add('${it.name}: $e');
      }
    }

    if (!mounted) return;
    setState(() => _mengirim = false);
    if (gagal.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Sebagian gagal dikirim'),
          content: Text(gagal.join('\n')),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
    }
    if (sukses > 0 && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ChatRoomPage(grup: grup, id: id, nama: nama)),
      );
    }
  }

  Widget _judul(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54)),
      );

  Widget _list() {
    if (_loading && _chats.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_error != null && _chats.isEmpty && _users.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              setState(() {
                _loading = true;
                _error = null;
              });
              _load();
            },
            child: const Text('Coba lagi'),
          ),
        ]),
      );
    }
    final idPribadi = _chats
        .where((c) => c['grup'] != true)
        .map((c) => (c['id'] as num).toInt())
        .toSet();
    final lain = _users.where((u) => !idPribadi.contains((u['id'] as num).toInt())).toList();
    final children = <Widget>[];

    if (_chats.isNotEmpty) {
      children.add(_judul('Percakapan'));
      for (final c in _chats) {
        final grup = c['grup'] == true;
        final nama = (c['nama'] ?? '').toString();
        children.add(ListTile(
          leading: CircleAvatar(
            child: grup ? const Icon(Icons.group) : Text(nama.isEmpty ? '?' : nama[0].toUpperCase()),
          ),
          title: Text(nama, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(grup ? 'Grup' : 'Pribadi'),
          onTap: () => _pilih(grup, (c['id'] as num).toInt(), nama),
        ));
      }
    }
    if (lain.isNotEmpty) {
      children.add(_judul('Pengguna lain'));
      for (final u in lain) {
        final nama = (u['name'] ?? '').toString();
        children.add(ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person)),
          title: Text(nama),
          subtitle: Text((u['role'] ?? '').toString()),
          onTap: () => _pilih(false, (u['id'] as num).toInt(), nama),
        ));
      }
    }
    if (children.isEmpty) return const Center(child: Text('Belum ada tujuan.'));
    return ListView(children: children);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_mengirim,
      child: Scaffold(
        appBar: AppBar(title: const Text('Kirim ke...')),
        body: Stack(children: [
          Column(children: [
            Container(
              width: double.infinity,
              color: const Color(0xFFEEF4F8),
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Icon(_adaFile ? Icons.insert_drive_file : Icons.text_snippet, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(_ringkasan(), maxLines: 3, overflow: TextOverflow.ellipsis),
                ),
              ]),
            ),
            if (_adaFile)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: TextField(
                  controller: _caption,
                  decoration: const InputDecoration(
                    labelText: 'Keterangan (opsional)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            Expanded(child: _list()),
          ]),
          if (_mengirim)
            Container(
              color: Colors.black38,
              child: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(_progress),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
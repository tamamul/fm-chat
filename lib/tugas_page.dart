import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'api.dart';
import 'pratinjau.dart';
import 'util.dart';
import 'waktu.dart';

class TugasPage extends StatefulWidget {
  const TugasPage({super.key});
  @override
  State<TugasPage> createState() => _TugasPageState();
}

class _TugasPageState extends State<TugasPage> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  List<Map<String, dynamic>> _toList(List raw) =>
      raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();

  Future<void> _muat({bool diam = false}) async {
    if (!diam) {
      final c = await Api.readCache('tugas');
      if (c is List && mounted) {
        setState(() {
          _items = _toList(c);
          _loading = false;
        });
      }
    }
    try {
      final d = await Api.getJson('/kumpul') as List;
      Api.writeCache('tugas', d);
      if (mounted) {
        setState(() {
          _items = _toList(d);
          _loading = false;
          _error = null;
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

  Future<void> _buka(Map<String, dynamic> it) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TugasDetailPage(folder: it)));
    _muat(diam: true);
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!),
          const SizedBox(height: 12),
          FilledButton(onPressed: _muat, child: const Text('Coba lagi')),
        ]),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: () => _muat(diam: true),
        child: _items.isEmpty
            ? ListView(children: const [
                SizedBox(height: 120),
                Center(child: Text('Belum ada tugas untuk dikumpulkan.')),
              ])
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: _items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final it = _items[i];
                  final (teks, lewat) = infoTenggat(it['tenggat'] as String?);
                  final jumlah = (it['jumlah'] as num).toInt();
                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.assignment)),
                    title: Text(it['name'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
                    isThreeLine: true,
                    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Dari ${it['pemilik']}'),
                      Text(teks, style: TextStyle(color: lewat ? Colors.red : null)),
                      Text(
                        jumlah > 0 ? '$jumlah file terkumpul' : 'Belum mengumpulkan',
                        style: TextStyle(color: jumlah > 0 ? const Color(0xFF2E7D32) : Colors.black54),
                      ),
                    ]),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _buka(it),
                  );
                },
              ),
      );
    }
    return Scaffold(appBar: AppBar(title: const Text('Tugas')), body: body);
  }
}

class TugasDetailPage extends StatefulWidget {
  final Map<String, dynamic> folder;
  const TugasDetailPage({super.key, required this.folder});
  @override
  State<TugasDetailPage> createState() => _TugasDetailPageState();
}

class _TugasDetailPageState extends State<TugasDetailPage> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  double? _prog;
  String _namaUnggah = '';

  int get _id => (widget.folder['id'] as num).toInt();

  @override
  void initState() {
    super.initState();
    _muat();
  }

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  List<Map<String, dynamic>> get _files =>
      ((_data?['files'] ?? []) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  Future<void> _muat({bool diam = false}) async {
    if (!diam) {
      final c = await Api.readCache('tugas_$_id');
      if (c is Map && mounted) {
        setState(() {
          _data = Map<String, dynamic>.from(c);
          _loading = false;
        });
      }
    }
    try {
      final d = await Api.getJson('/kumpul/$_id');
      Api.writeCache('tugas_$_id', d);
      if (mounted) {
        setState(() {
          _data = Map<String, dynamic>.from(d as Map);
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          if (_data == null) _error = e.toString();
        });
      }
    }
  }

  Future<PlatformFile?> _ambilFile() async {
    try {
      return await FilePicker.pickFile();
    } catch (_) {
      _snack('Tidak bisa membuka pemilih file.');
      return null;
    }
  }

  Future<void> _unggah() async {
    final f = await _ambilFile();
    if (f == null) return;
    final bytes = await f.length() ?? 0;
    if (bytes > 100 * 1024 * 1024) {
      _snack('Ukuran file maksimal 100 MB.');
      return;
    }
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kumpulkan file ini?'),
        content: Text('${f.name}\n(${ukuranFile(bytes)})'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Kumpulkan')),
        ],
      ),
    );
    if (ok != true) return;
    final path = await lokalPath(f);
    if (path == null) {
      _snack('File tidak bisa dibaca.');
      return;
    }
    setState(() {
      _namaUnggah = f.name;
      _prog = 0;
    });
    var terakhir = 0.0;
    try {
      await Api.uploadFile('/kumpul/$_id/unggah', path, f.name, onProgress: (s, t) {
        if (t <= 0) return;
        final p = s / t;
        if (p - terakhir < 0.01 && p < 1) return;
        terakhir = p;
        if (mounted) setState(() => _prog = p);
      });
      _snack('Tugas terkumpul: ${f.name}');
      await _muat(diam: true);
    } catch (e) {
      _snack('Gagal mengumpulkan: $e');
    } finally {
      if (path != f.path) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _namaUnggah = '';
          _prog = null;
        });
      }
    }
  }

  Future<void> _hapus(Map<String, dynamic> f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus kiriman ini?'),
        content: Text(f['name'].toString()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Hapus')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.deleteJson('/kumpul/file/${f['id']}');
      await _muat(diam: true);
    } catch (e) {
      _snack(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final folder = (_data?['folder'] as Map?) ?? widget.folder;
    final (teks, lewat) = infoTenggat(folder['tenggat'] as String?);
    final files = _files;

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null && _data == null) {
      body = Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!),
          const SizedBox(height: 12),
          FilledButton(onPressed: _muat, child: const Text('Coba lagi')),
        ]),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: () => _muat(diam: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 88),
          children: [
            Container(
              width: double.infinity,
              color: const Color(0xFFEEF4F8),
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Dari ${folder['pemilik'] ?? 'Guru'}'),
                const SizedBox(height: 4),
                Text(teks, style: TextStyle(fontWeight: FontWeight.bold, color: lewat ? Colors.red : null)),
                if (lewat)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text('Kiriman setelah tenggat akan ditandai terlambat.',
                        style: TextStyle(fontSize: 12, color: Colors.black54)),
                  ),
              ]),
            ),
            if (_namaUnggah.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Mengumpulkan $_namaUnggah · ${((_prog ?? 0) * 100).round()}%',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(value: _prog ?? 0),
                ]),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('Kiriman Anda (${files.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54)),
            ),
            if (files.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('Belum ada kiriman. Ketuk "Unggah tugas" di bawah.')),
              ),
            for (final f in files)
              ListTile(
                leading: IkonFile(nama: f['name'].toString(), url: f['url'].toString(), ukuran: 40),
                title: Text(f['name'].toString(), maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${ukuranFile((f['size'] as num).toInt())} · ${fmtWaktu(DateTime.parse(f['waktu'].toString()))}'
                  '${f['terlambat'] == true ? ' · Terlambat' : ''}',
                  style: TextStyle(color: f['terlambat'] == true ? Colors.red : null),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Hapus kiriman',
                  onPressed: () => _hapus(f),
                ),
                onTap: () => bukaPintar(context, files, f),
              ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(folder['name'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: body,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _namaUnggah.isNotEmpty ? null : _unggah,
        icon: const Icon(Icons.upload_file),
        label: const Text('Unggah tugas'),
      ),
    );
  }
}
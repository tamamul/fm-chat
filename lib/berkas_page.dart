import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'api.dart';
import 'util.dart';

class BerkasPage extends StatefulWidget {
  const BerkasPage({super.key});
  @override
  State<BerkasPage> createState() => _BerkasPageState();
}

class _BerkasPageState extends State<BerkasPage> {
  int? _folderId;
  final List<int?> _stack = []; // induk-induk dari folder saat ini (null = akar)
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _mengunggah = false;
  String? _error;

  String get _cacheKey => 'berkas_${_folderId ?? 0}';

  List<Map<String, dynamic>> _list(String k) =>
      ((_data?[k] ?? []) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  @override
  void initState() {
    super.initState();
    _muat();
  }

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _muat({bool diam = false}) async {
    final fid = _folderId;
    if (!diam) {
      final c = await Api.readCache(_cacheKey);
      if (fid != _folderId) return;
      if (c is Map && mounted) {
        setState(() {
          _data = Map<String, dynamic>.from(c);
          _loading = false;
        });
      } else if (mounted) {
        setState(() {
          _data = null;
          _loading = true;
          _error = null;
        });
      }
    }
    try {
      final d = await Api.getJson(fid == null ? '/berkas' : '/berkas?folder=$fid');
      Api.writeCache('berkas_${fid ?? 0}', d);
      if (fid != _folderId) return; // pengguna sudah pindah folder
      if (mounted) {
        setState(() {
          _data = Map<String, dynamic>.from(d as Map);
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (fid != _folderId) return;
      if (mounted) {
        setState(() {
          _loading = false;
          if (_data == null) _error = e.toString();
        });
      }
    }
  }

  void _masuk(int id) {
    _stack.add(_folderId);
    setState(() => _folderId = id);
    _muat();
  }

  void _naik() {
    if (_stack.isEmpty) return;
    setState(() => _folderId = _stack.removeLast());
    _muat();
  }

  // Ketuk jejak lokasi: pindah ke folder tertentu, atau ke akar (i == -1).
  void _keJejak(List<Map<String, dynamic>> j, int i) {
    _stack.clear();
    if (i >= 0) {
      _stack.add(null);
      for (var k = 0; k < i; k++) {
        _stack.add(j[k]['id'] as int);
      }
    }
    setState(() => _folderId = i >= 0 ? j[i]['id'] as int : null);
    _muat();
  }

  Future<String?> _tanya(String judul, {String isi = '', String tombol = 'Simpan'}) {
    final c = TextEditingController(text: isi);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(judul),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(tombol)),
        ],
      ),
    );
  }

  Future<void> _unggah() async {
    PlatformFile? f;
    try {
      f = await FilePicker.pickFile();
    } catch (_) {
      _snack('Tidak bisa membuka pemilih file.');
      return;
    }
    if (f == null) return;
    final bytes = await f.length() ?? 0;
    if (bytes > 100 * 1024 * 1024) {
      _snack('Ukuran file maksimal 100 MB.');
      return;
    }
    final path = await lokalPath(f);
    if (path == null) {
      _snack('File tidak bisa dibaca.');
      return;
    }
    setState(() => _mengunggah = true);
    try {
      await Api.uploadFile('/berkas/unggah', path, f.name,
          fields: {if (_folderId != null) 'folder_id': '$_folderId'});
      _snack('Terunggah: ${f.name}');
      await _muat(diam: true);
    } catch (e) {
      _snack('Gagal mengunggah: $e');
    } finally {
      if (path != f.path) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
      if (mounted) setState(() => _mengunggah = false);
    }
  }

  Future<void> _folderBaru() async {
    final nama = await _tanya('Folder baru', tombol: 'Buat');
    if (nama == null || nama.isEmpty) return;
    try {
      await Api.postJson('/berkas/folder', {'name': nama, if (_folderId != null) 'parent_id': _folderId});
      await _muat(diam: true);
    } catch (e) {
      _snack(e.toString());
    }
  }

  Future<void> _gantiNama(bool folder, Map<String, dynamic> it) async {
    final nama = await _tanya('Ganti nama', isi: it['name'].toString());
    if (nama == null || nama.isEmpty || nama == it['name']) return;
    try {
      await Api.postJson(folder ? '/berkas/folder/${it['id']}/nama' : '/berkas/${it['id']}/nama', {'name': nama});
      await _muat(diam: true);
    } catch (e) {
      _snack(e.toString());
    }
  }

  Future<void> _hapus(bool folder, Map<String, dynamic> it) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(folder ? 'Hapus folder?' : 'Hapus file?'),
        content: Text(it['name'].toString()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Hapus')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.deleteJson(folder ? '/berkas/folder/${it['id']}' : '/berkas/${it['id']}');
      await _muat(diam: true);
    } catch (e) {
      _snack(e.toString());
    }
  }

  Future<void> _bagikan(Map<String, dynamic> it) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _BagikanSheet(file: it),
    );
    _muat(diam: true);
  }

  void _tambah() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text('Unggah file'),
            onTap: () {
              Navigator.pop(ctx);
              _unggah();
            },
          ),
          ListTile(
            leading: const Icon(Icons.create_new_folder_outlined),
            title: const Text('Folder baru'),
            onTap: () {
              Navigator.pop(ctx);
              _folderBaru();
            },
          ),
        ]),
      ),
    );
  }

  Widget _remah(List<Map<String, dynamic>> j) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(children: [
        TextButton(onPressed: () => _keJejak(j, -1), child: const Text('Berkas')),
        for (var i = 0; i < j.length; i++) ...[
          const Icon(Icons.chevron_right, size: 18),
          TextButton(
            onPressed: i == j.length - 1 ? null : () => _keJejak(j, i),
            child: Text(j[i]['name'].toString()),
          ),
        ],
      ]),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!),
          const SizedBox(height: 12),
          FilledButton(onPressed: _muat, child: const Text('Coba lagi')),
        ]),
      );
    }
    final folders = _list('folders');
    final files = _list('files');
    final j = _list('jejak');
    return RefreshIndicator(
      onRefresh: () => _muat(diam: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (j.isNotEmpty) _remah(j),
          if (folders.isEmpty && files.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 120),
              child: Center(child: Text('Folder ini kosong.')),
            ),
          for (final f in folders)
            ListTile(
              leading: const Icon(Icons.folder, size: 36, color: Color(0xFFF2B01E)),
              title: Text(f['name'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => _masuk(f['id'] as int),
              trailing: PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'nama') _gantiNama(true, f);
                  if (v == 'hapus') _hapus(true, f);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'nama', child: Text('Ganti nama')),
                  PopupMenuItem(value: 'hapus', child: Text('Hapus')),
                ],
              ),
            ),
          for (final f in files) _barisFile(f),
        ],
      ),
    );
  }

  Widget _barisFile(Map<String, dynamic> f) {
    final nama = f['name'].toString();
    final penerima = (f['penerima'] as List).length;
    final info = [
      ukuranFile((f['size'] as num).toInt()),
      if (penerima > 0) 'dibagikan ke $penerima',
      if (f['tautan'] != null) 'tautan aktif',
    ].join(' · ');
    return ListTile(
      leading: Icon(ikonFile(nama), size: 32),
      title: Text(nama, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(info),
      onTap: () => bukaBerkas(context, f['url'].toString(), nama),
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          if (v == 'buka') bukaBerkas(context, f['url'].toString(), nama);
          if (v == 'bagi') _bagikan(f);
          if (v == 'nama') _gantiNama(false, f);
          if (v == 'hapus') _hapus(false, f);
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'buka', child: Text('Buka')),
          PopupMenuItem(value: 'bagi', child: Text('Bagikan')),
          PopupMenuItem(value: 'nama', child: Text('Ganti nama')),
          PopupMenuItem(value: 'hapus', child: Text('Hapus')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final j = _list('jejak');
    return PopScope(
      canPop: _folderId == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _naik();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_folderId == null
              ? 'Berkas'
              : (j.isNotEmpty ? j.last['name'].toString() : 'Folder')),
          leading: _folderId == null
              ? null
              : IconButton(icon: const Icon(Icons.arrow_back), onPressed: _naik),
          bottom: _mengunggah
              ? const PreferredSize(
                  preferredSize: Size.fromHeight(3),
                  child: LinearProgressIndicator(),
                )
              : null,
        ),
        body: _body(),
        floatingActionButton: FloatingActionButton(onPressed: _tambah, child: const Icon(Icons.add)),
      ),
    );
  }
}

class _BagikanSheet extends StatefulWidget {
  final Map<String, dynamic> file;
  const _BagikanSheet({required this.file});
  @override
  State<_BagikanSheet> createState() => _BagikanSheetState();
}

class _BagikanSheetState extends State<_BagikanSheet> {
  List<Map<String, dynamic>> _users = [];
  late Set<int> _penerima;
  String? _tautan;
  bool _loading = true;
  bool _sibuk = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _penerima = ((widget.file['penerima'] ?? []) as List)
        .map((e) => ((e as Map)['id'] as num).toInt())
        .toSet();
    _tautan = widget.file['tautan'] as String?;
    _muat();
  }

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _muat() async {
    try {
      final u = await Api.getJson('/pengguna') as List;
      if (mounted) {
        setState(() {
          _users = u.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _toggle(int uid, bool nyala) async {
    if (_sibuk) return;
    setState(() => _sibuk = true);
    final id = widget.file['id'];
    try {
      if (nyala) {
        await Api.postJson('/berkas/$id/penerima', {'user_id': uid});
        _penerima.add(uid);
      } else {
        await Api.deleteJson('/berkas/$id/penerima/$uid');
        _penerima.remove(uid);
      }
    } catch (e) {
      _snack(e.toString());
    }
    if (mounted) setState(() => _sibuk = false);
  }

  Future<void> _buatTautan() async {
    setState(() => _sibuk = true);
    try {
      final r = await Api.postJson('/berkas/${widget.file['id']}/tautan', {});
      _tautan = (r as Map)['tautan'] as String?;
    } catch (e) {
      _snack(e.toString());
    }
    if (mounted) setState(() => _sibuk = false);
  }

  Future<void> _matikanTautan() async {
    setState(() => _sibuk = true);
    try {
      await Api.deleteJson('/berkas/${widget.file['id']}/tautan');
      _tautan = null;
    } catch (e) {
      _snack(e.toString());
    }
    if (mounted) setState(() => _sibuk = false);
  }

  Widget _judul(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54)),
      );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(children: [
          ListTile(
            title: Text(widget.file['name'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: const Text('Bagikan file'),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(children: [
              _judul('Tautan publik (berlaku 7 hari)'),
              if (_tautan == null)
                ListTile(
                  leading: const Icon(Icons.link),
                  title: const Text('Buat tautan'),
                  onTap: _sibuk ? null : _buatTautan,
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SelectableText(_tautan!),
                ),
                Row(children: [
                  TextButton.icon(
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Salin'),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _tautan!));
                      _snack('Tautan disalin.');
                    },
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.link_off, size: 18),
                    label: const Text('Matikan'),
                    onPressed: _sibuk ? null : _matikanTautan,
                  ),
                ]),
              ],
              _judul('Bagikan ke pengguna'),
              if (_loading)
                const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
              else if (_error != null)
                Padding(padding: const EdgeInsets.all(16), child: Text(_error!))
              else
                for (final u in _users)
                  CheckboxListTile(
                    value: _penerima.contains((u['id'] as num).toInt()),
                    onChanged: _sibuk ? null : (v) => _toggle((u['id'] as num).toInt(), v ?? false),
                    title: Text(u['name'].toString()),
                    subtitle: Text(u['role'].toString()),
                  ),
            ]),
          ),
        ]),
      ),
    );
  }
}
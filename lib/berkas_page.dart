import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api.dart';
import 'lokal.dart';
import 'util.dart';
import 'bagikan_sheet.dart';
import 'pratinjau.dart';

const _opsiFilter = [
  ('semua', 'Semua'),
  ('hp', 'Di HP'),
  ('cloud', 'Cloud'),
  ('gambar', 'Gambar'),
  ('dokumen', 'Dokumen'),
  ('media', 'Audio/Video'),
];

class BerkasPage extends StatefulWidget {
  final bool aktif;
  const BerkasPage({super.key, this.aktif = true});
  @override
  State<BerkasPage> createState() => _BerkasPageState();
}

class _BerkasPageState extends State<BerkasPage> {
  int? _folderId;
  Map<String, dynamic>? _data;
  Map<String, dynamic>? _hasilCari;
  bool _loading = true;
  String? _error;
  double? _progUnggah;
  String _namaUnggah = '';
  bool _cari = false;
  String _q = '';
  final _qCtl = TextEditingController();
  Timer? _debounce;
  String _filter = 'semua';
  final Set<String> _pilih = {};

  String get _cacheKey => 'berkas_${_folderId ?? 0}';
  bool get _modePilih => _pilih.isNotEmpty;

  List<Map<String, dynamic>> _list(String k) =>
      ((_data?[k] ?? []) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  @override
  void initState() {
    super.initState();
    Lokal.berubah.addListener(_onLokal);
    _muat();
  }

  @override
  void dispose() {
    Lokal.berubah.removeListener(_onLokal);
    _debounce?.cancel();
    _qCtl.dispose();
    super.dispose();
  }

  void _onLokal() {
    if (mounted) setState(() {});
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
      if (fid != _folderId) return;
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

  // ---------- navigasi ----------

  void _masuk(int id) {
    _pilih.clear();
    setState(() => _folderId = id);
    _muat();
  }

  void _naik() {
    final folder = _data?['folder'];
    final induk = folder is Map ? folder['parent_id'] : null;
    _pilih.clear();
    setState(() => _folderId = induk is int ? induk : null);
    _muat();
  }

  void _keJejak(List<Map<String, dynamic>> j, int i) {
    _pilih.clear();
    setState(() => _folderId = i >= 0 ? j[i]['id'] as int : null);
    _muat();
  }

  // ---------- cari dan filter ----------

  void _ubahCari(String v) {
    setState(() => _q = v);
    _debounce?.cancel();
    final q = v.trim();
    if (q.length < 2) {
      setState(() => _hasilCari = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _cariServer(q));
  }

  Future<void> _cariServer(String q) async {
    try {
      final d = await Api.getJson('/berkas/cari?q=${Uri.encodeQueryComponent(q)}');
      if (q != _q.trim() || !mounted) return;
      setState(() => _hasilCari = Map<String, dynamic>.from(d as Map));
    } catch (_) {
      if (mounted) setState(() => _hasilCari = null);
    }
  }

  void _tutupCari() {
    _debounce?.cancel();
    _qCtl.clear();
    setState(() {
      _cari = false;
      _q = '';
      _hasilCari = null;
    });
  }

  bool _cocok(Map<String, dynamic> f) {
    final url = f['url'].toString();
    switch (_filter) {
      case 'hp':
        return Lokal.ada(url);
      case 'cloud':
        return !Lokal.ada(url);
      default:
        return kategoriFile(f['name'].toString()) == _filter;
    }
  }

  List<Map<String, dynamic>> _tampil() {
    final sumber = _hasilCari ?? _data;
    List<Map<String, dynamic>> ambil(String k, String tipe) => ((sumber?[k] ?? []) as List)
        .map((e) => {...Map<String, dynamic>.from(e as Map), 'tipe': tipe})
        .toList();
    var folders = ambil('folders', 'folder');
    var files = ambil('files', 'file');
    final q = _q.trim().toLowerCase();
    if (_hasilCari == null && q.isNotEmpty) {
      folders = folders.where((e) => e['name'].toString().toLowerCase().contains(q)).toList();
      files = files.where((e) => e['name'].toString().toLowerCase().contains(q)).toList();
    }
    if (_filter != 'semua') {
      folders = [];
      files = files.where(_cocok).toList();
    }
    return [...folders, ...files];
  }

  // ---------- pilih banyak ----------

  String _kunciItem(Map<String, dynamic> it) => '${it['tipe'] == 'folder' ? 'd' : 'f'}:${it['id']}';

  void _toggle(Map<String, dynamic> it) {
    final k = _kunciItem(it);
    setState(() {
      if (!_pilih.remove(k)) _pilih.add(k);
    });
  }

  void _pilihSemua(List<Map<String, dynamic>> items) {
    setState(() {
      _pilih
        ..clear()
        ..addAll(items.map(_kunciItem));
    });
  }

  void _ketuk(Map<String, dynamic> it) {
    if (_modePilih) {
      _toggle(it);
      return;
    }
    if (it['tipe'] == 'folder') {
      if (_cari) _tutupCari();
      _masuk(it['id'] as int);
    } else {
    final files = _tampil().where((e) => e['tipe'] != 'folder').toList();
      bukaPintar(context, files, it);
    }
  }

  // ---------- aksi ----------

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
    final path = await lokalPath(f);
    if (path == null) {
      _snack('File tidak bisa dibaca.');
      return;
    }
    setState(() {
      _namaUnggah = f.name;
      _progUnggah = 0;
    });
    var terakhir = 0.0;
    try {
      await Api.uploadFile('/berkas/unggah', path, f.name,
          fields: {if (_folderId != null) 'folder_id': '$_folderId'},
          onProgress: (s, t) {
            if (t <= 0) return;
            final p = s / t;
            if (p - terakhir < 0.01 && p < 1) return;
            terakhir = p;
            if (mounted) setState(() => _progUnggah = p);
          });
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
      if (mounted) {
        setState(() {
          _namaUnggah = '';
          _progUnggah = null;
        });
      }
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

  Future<void> _gantiNama(Map<String, dynamic> it) async {
    final folder = it['tipe'] == 'folder';
    final nama = await _tanya('Ganti nama', isi: it['name'].toString());
    if (nama == null || nama.isEmpty || nama == it['name']) return;
    try {
      await Api.postJson(folder ? '/berkas/folder/${it['id']}/nama' : '/berkas/${it['id']}/nama', {'name': nama});
      await _muat(diam: true);
      if (_cari && _q.trim().length >= 2) _cariServer(_q.trim());
    } catch (e) {
      _snack(e.toString());
    }
  }

  Future<void> _hapusDaftar(List<int> files, List<int> folders) async {
    final ringkas = [
      if (files.isNotEmpty) '${files.length} file',
      if (folders.isNotEmpty) '${folders.length} folder beserta seluruh isinya',
    ].join(' dan ');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Hapus $ringkas?'),
        content: const Text(
            'Tindakan ini tidak bisa dibatalkan. File yang sudah dibagikan juga hilang bagi penerimanya.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Hapus')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final r = await Api.postJson('/berkas/hapus', {'files': files, 'folders': folders});
      final ids = (r is Map && r['file_ids'] is List) ? r['file_ids'] as List : <dynamic>[];
      for (final id in ids) {
        await Lokal.hapus('/berkas/$id/unduh');
      }
      if (mounted) setState(_pilih.clear);
      await _muat(diam: true);
      if (_cari && _q.trim().length >= 2) _cariServer(_q.trim());
      _snack('Terhapus.');
    } catch (e) {
      _snack(e.toString());
    }
  }

  void _hapusPilihan() {
    final files = <int>[];
    final folders = <int>[];
    for (final k in _pilih) {
      final id = int.tryParse(k.substring(2));
      if (id == null) continue;
      if (k.startsWith('d:')) {
        folders.add(id);
      } else {
        files.add(id);
      }
    }
    _hapusDaftar(files, folders);
  }

  Future<void> _bagikan(Map<String, dynamic> it) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => BagikanSheet(jenis: it['tipe'] == 'folder' ? 'folder' : 'file', item: it),
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

  Future<void> _infoPenyimpanan() async {
    final akar = await Lokal.akar();
    final total = await Lokal.totalUkuran();
    if (!mounted) return;
    final hapus = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Penyimpanan di HP'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('File yang sudah diunduh memakai ${ukuranFile(total)}.'),
            const SizedBox(height: 8),
            const Text(
                'Disimpan di memori internal aplikasi (tidak terlihat di File Manager). Tidak hilang saat "Hapus cache", tapi hilang saat aplikasi dicopot atau keluar akun.'),
            const SizedBox(height: 8),
            SelectableText(akar.path, style: const TextStyle(fontSize: 11)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tutup')),
          FilledButton(
            onPressed: total == 0 ? null : () => Navigator.pop(ctx, true),
            child: const Text('Hapus semua unduhan'),
          ),
        ],
      ),
    );
    if (hapus == true) {
      await Lokal.hapusSemua();
      _snack('Semua unduhan di HP dihapus.');
    }
  }

  // ---------- tampilan ----------

  PreferredSizeWidget _appBar(List<Map<String, dynamic>> items, List<Map<String, dynamic>> j) {
    if (_modePilih) {
      return AppBar(
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_pilih.clear)),
        title: Text('${_pilih.length} dipilih'),
        actions: [
          IconButton(
            icon: const Icon(Icons.select_all),
            tooltip: 'Pilih semua',
            onPressed: () => _pilihSemua(items),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Hapus',
            onPressed: _hapusPilihan,
          ),
        ],
      );
    }
    if (_cari) {
      return AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _tutupCari),
        title: TextField(
          controller: _qCtl,
          autofocus: true,
          onChanged: _ubahCari,
          decoration: const InputDecoration(hintText: 'Cari file atau folder...', border: InputBorder.none),
        ),
        actions: [
          if (_q.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _qCtl.clear();
                _ubahCari('');
              },
            ),
        ],
      );
    }
    return AppBar(
      title: Text(_folderId == null ? 'Berkas' : (j.isNotEmpty ? j.last['name'].toString() : 'Folder')),
      leading: _folderId == null ? null : IconButton(icon: const Icon(Icons.arrow_back), onPressed: _naik),
      actions: [
        IconButton(icon: const Icon(Icons.search), onPressed: () => setState(() => _cari = true)),
        PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'simpan') _infoPenyimpanan();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'simpan', child: Text('Penyimpanan di HP')),
          ],
        ),
      ],
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

  Widget _bannerUnggah() {
    final p = _progUnggah ?? 0;
    return Container(
      width: double.infinity,
      color: const Color(0xFFEEF4F8),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Mengunggah $_namaUnggah · ${(p * 100).round()}%',
            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: p),
      ]),
    );
  }

  Widget _chips() {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          for (final e in _opsiFilter)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(e.$2),
                selected: _filter == e.$1,
                onSelected: (_) => setState(() => _filter = e.$1),
              ),
            ),
        ],
      ),
    );
  }

  String _kosongTeks() {
    if (_q.trim().isNotEmpty) return 'Tidak ada hasil untuk "${_q.trim()}".';
    if (_filter != 'semua') return 'Tidak ada file untuk filter ini.';
    return 'Folder ini kosong.';
  }

  Widget _baris(Map<String, dynamic> it, bool hasil) {
    final folder = it['tipe'] == 'folder';
    final nama = it['name'].toString();
    final sel = _pilih.contains(_kunciItem(it));
    final induk = (folder ? it['induk_nama'] : it['folder_nama'])?.toString() ?? 'Berkas';
    final url = folder ? '' : it['url'].toString();

    final info = <String>[];
    if (!folder) {
      info.add(ukuranFile((it['size'] as num).toInt()));
      final n = (it['penerima'] as List).length + ((it['grup_dibagi'] ?? 0) as int);
      if (n > 0) info.add('dibagikan ke $n');
      if (it['tautan'] != null) info.add('tautan aktif');
    } else {
      final n = (it['dibagi'] ?? 0) as int;
      if (n > 0) info.add('dibagikan ke $n');
    }
    if (hasil) info.add('di $induk');

    Widget leading;
    if (sel) {
      leading = Icon(Icons.check_circle, size: 32, color: Theme.of(context).colorScheme.primary);
    } else if (folder) {
      leading = const Icon(Icons.folder, size: 36, color: Color(0xFFF2B01E));
    } else {
      leading = IkonFile(nama: nama, url: url, ukuran: 40);
    }

    Widget trailing;
    if (_modePilih) {
      trailing = Checkbox(value: sel, onChanged: (_) => _toggle(it));
    } else if (folder) {
      trailing = PopupMenuButton<String>(
      	onSelected: (v) {
      	  if (v == 'buka') {
              bukaPintar(context, _tampil().where((e) => e['tipe'] != 'folder').toList(), it);
            }
            if (v == 'luar') bukaBerkas(context, url, nama);
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'bagi', child: Text('Bagikan')),
          PopupMenuItem(value: 'nama', child: Text('Ganti nama')),
          PopupMenuItem(value: 'hapus', child: Text('Hapus')),
        ],
      );
    } else {
      trailing = Row(mainAxisSize: MainAxisSize.min, children: [
        StatusUnduh(url: url),
        PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'buka') bukaBerkas(context, url, nama);
            if (v == 'hp') Unduhan.mulai(context, url, nama, buka: false);
            if (v == 'lepas') Lokal.hapus(url);
            if (v == 'bagi') _bagikan(it);
            if (v == 'nama') _gantiNama(it);
            if (v == 'hapus') _hapusDaftar([it['id'] as int], []);
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'buka', child: Text('Pratinjau / buka')),
            const PopupMenuItem(value: 'luar', child: Text('Buka dengan aplikasi lain')),
            if (!Lokal.ada(url)) const PopupMenuItem(value: 'hp', child: Text('Simpan di HP')),
            if (Lokal.ada(url)) const PopupMenuItem(value: 'lepas', child: Text('Hapus dari HP')),
            const PopupMenuItem(value: 'bagi', child: Text('Bagikan')),
            const PopupMenuItem(value: 'nama', child: Text('Ganti nama')),
            const PopupMenuItem(value: 'hapus', child: Text('Hapus')),
          ],
        ),
      ]);
    }

    return ListTile(
      tileColor: sel ? const Color(0x1F0B7A9E) : null,
      leading: leading,
      title: Text(nama, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: info.isEmpty ? null : Text(info.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: trailing,
      onTap: () => _ketuk(it),
      onLongPress: () => _toggle(it),
    );
  }

  Widget _body(List<Map<String, dynamic>> items, List<Map<String, dynamic>> j, bool hasil) {
    if (_loading && _hasilCari == null) return const Center(child: CircularProgressIndicator());
    if (_error != null && _data == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!),
          const SizedBox(height: 12),
          FilledButton(onPressed: _muat, child: const Text('Coba lagi')),
        ]),
      );
    }
    return Column(children: [
      if (_namaUnggah.isNotEmpty) _bannerUnggah(),
      _chips(),
      Expanded(
        child: RefreshIndicator(
          onRefresh: () => _muat(diam: true),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              if (!_cari && j.isNotEmpty) _remah(j),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 120),
                  child: Center(child: Text(_kosongTeks())),
                ),
              for (final it in items) _baris(it, hasil),
            ],
          ),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final items = _tampil();
    final j = _list('jejak');
    final hasil = _hasilCari != null;
    return PopScope(
    canPop: !widget.aktif || (_folderId == null && !_modePilih && !_cari),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !widget.aktif) return;
        if (_modePilih) {
          setState(_pilih.clear);
        } else if (_cari) {
          _tutupCari();
        } else {
          _naik();
        }
      },
      child: Scaffold(
        appBar: _appBar(items, j),
        body: _body(items, j, hasil),
        floatingActionButton: _modePilih
            ? null
            : FloatingActionButton(onPressed: _tambah, child: const Icon(Icons.add)),
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
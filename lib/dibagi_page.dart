import 'package:flutter/material.dart';
import 'api.dart';
import 'lokal.dart';
import 'util.dart';
import 'pratinjau.dart';

class DibagiPage extends StatefulWidget {
  final bool aktif;
  const DibagiPage({super.key, this.aktif = true});
  @override
  State<DibagiPage> createState() => _DibagiPageState();
}

class _DibagiPageState extends State<DibagiPage> {
  int? _folderId;
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  String get _cacheKey => 'dibagi_${_folderId ?? 0}';

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
    super.dispose();
  }

  void _onLokal() {
    if (mounted) setState(() {});
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
      final d = await Api.getJson(fid == null ? '/dibagi' : '/dibagi/folder/$fid');
      Api.writeCache('dibagi_${fid ?? 0}', d);
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

  void _masuk(int id) {
    setState(() => _folderId = id);
    _muat();
  }

  void _naik() {
    final induk = _data?['induk'];
    setState(() => _folderId = induk is int ? induk : null);
    _muat();
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _data == null) {
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
    return RefreshIndicator(
      onRefresh: () => _muat(diam: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (folders.isEmpty && files.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 120),
              child: Center(
                child: Text(_folderId == null
                    ? 'Belum ada yang dibagikan kepada Anda.'
                    : 'Folder ini kosong.'),
              ),
            ),
          for (final f in folders)
            ListTile(
              leading: const Icon(Icons.folder_shared, size: 36, color: Color(0xFFF2B01E)),
              title: Text(f['name'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${f['pemilik']}'),
              onTap: () => _masuk((f['id'] as num).toInt()),
            ),
          for (final f in files) _barisFile(f),
        ],
      ),
    );
  }

  Widget _barisFile(Map<String, dynamic> f) {
    final nama = f['name'].toString();
    final url = f['url'].toString();
      return ListTile(
      leading: IkonFile(nama: nama, url: url, ukuran: 40),
      title: Text(nama, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${f['pemilik']} · ${ukuranFile((f['size'] as num).toInt())}'),
      onTap: () => bukaPintar(context, _list('files'), f),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        StatusUnduh(url: url),
        PopupMenuButton<String>(
                    onSelected: (v) {
            if (v == 'buka') bukaPintar(context, _list('files'), f);
            if (v == 'luar') bukaBerkas(context, url, nama);
            if (v == 'unduhan') simpanKeUnduhan(context, url, nama);
            if (v == 'hp') Unduhan.mulai(context, url, nama, buka: false);
            if (v == 'lepas') Lokal.hapus(url);
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'buka', child: Text('Pratinjau / buka')),
            const PopupMenuItem(value: 'luar', child: Text('Buka dengan aplikasi lain')),
            const PopupMenuItem(value: 'unduhan', child: Text('Simpan ke Unduhan')),
            if (!Lokal.ada(url)) const PopupMenuItem(value: 'hp', child: Text('Simpan di HP')),
            if (Lokal.ada(url)) const PopupMenuItem(value: 'lepas', child: Text('Hapus dari HP')),
          ],
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nama = (_data?['folder'] is Map) ? (_data!['folder'] as Map)['name'].toString() : null;
    return PopScope(
      canPop: !widget.aktif || _folderId == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !widget.aktif) return;
        _naik();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_folderId == null ? 'Dibagikan kepada saya' : (nama ?? 'Folder')),
          leading: _folderId == null
              ? null
              : IconButton(icon: const Icon(Icons.arrow_back), onPressed: _naik),
        ),
        body: _body(),
      ),
    );
  }
}

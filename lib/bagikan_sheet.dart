import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api.dart';

class BagikanSheet extends StatefulWidget {
  final String jenis; // 'file' atau 'folder'
  final Map<String, dynamic> item;
  const BagikanSheet({super.key, required this.jenis, required this.item});
  @override
  State<BagikanSheet> createState() => _BagikanSheetState();
}

class _BagikanSheetState extends State<BagikanSheet> {
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _grup = [];
  final Set<int> _uPilih = {};
  final Set<int> _gPilih = {};
  String? _tautan;
  String _cari = '';
  bool _loading = true;
  bool _sibuk = false;
  String? _error;

  bool get _folder => widget.jenis == 'folder';
  int get _id => (widget.item['id'] as num).toInt();

  @override
  void initState() {
    super.initState();
    _tautan = widget.item['tautan'] as String?;
    _muat();
  }

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  List<Map<String, dynamic>> _maps(dynamic raw) =>
      (raw as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  Future<void> _muat() async {
    try {
      final r = await Future.wait([
        Api.getJson('/berbagi/target'),
        Api.getJson('/berbagi/${widget.jenis}/$_id'),
      ]);
      final t = r[0] as Map;
      final s = r[1] as Map;
      if (!mounted) return;
      setState(() {
        _users = _maps(t['users']);
        _grup = _maps(t['grup']);
        _uPilih
          ..clear()
          ..addAll((s['users'] as List).map((e) => (e as num).toInt()));
        _gPilih
          ..clear()
          ..addAll((s['grup'] as List).map((e) => (e as num).toInt()));
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _toggle(String target, int tid, bool nyala) async {
    if (_sibuk) return;
    setState(() => _sibuk = true);
    try {
      if (nyala) {
        await Api.postJson('/berbagi/${widget.jenis}/$_id', {'target': target, 'target_id': tid});
      } else {
        await Api.deleteJson('/berbagi/${widget.jenis}/$_id/$target/$tid');
      }
      final set = target == 'user' ? _uPilih : _gPilih;
      if (nyala) {
        set.add(tid);
      } else {
        set.remove(tid);
      }
    } catch (e) {
      _snack(e.toString());
    }
    if (mounted) setState(() => _sibuk = false);
  }

  Future<void> _buatTautan() async {
    setState(() => _sibuk = true);
    try {
      final r = await Api.postJson('/berkas/$_id/tautan', {});
      _tautan = (r as Map)['tautan'] as String?;
    } catch (e) {
      _snack(e.toString());
    }
    if (mounted) setState(() => _sibuk = false);
  }

  Future<void> _matikanTautan() async {
    setState(() => _sibuk = true);
    try {
      await Api.deleteJson('/berkas/$_id/tautan');
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
    final q = _cari.trim().toLowerCase();
    final grup = _grup.where((g) => g['name'].toString().toLowerCase().contains(q)).toList();
    final users = _users.where((u) => u['name'].toString().toLowerCase().contains(q)).toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.8,
          child: Column(children: [
            ListTile(
              leading: Icon(_folder ? Icons.folder : Icons.insert_drive_file),
              title: Text(widget.item['name'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(_folder
                  ? 'Penerima bisa melihat dan mengunduh seluruh isi folder (hanya baca)'
                  : 'Bagikan file'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                onChanged: (v) => setState(() => _cari = v),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Cari grup atau pengguna',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text(_error!))
                      : ListView(children: [
                          if (!_folder) ...[
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
                          ],
                          if (grup.isNotEmpty) _judul('Grup'),
                          for (final g in grup)
                            CheckboxListTile(
                              secondary: const CircleAvatar(child: Icon(Icons.group)),
                              value: _gPilih.contains((g['id'] as num).toInt()),
                              onChanged: _sibuk
                                  ? null
                                  : (v) => _toggle('grup', (g['id'] as num).toInt(), v ?? false),
                              title: Text(g['name'].toString()),
                            ),
                          if (users.isNotEmpty) _judul('Pengguna'),
                          for (final u in users)
                            CheckboxListTile(
                              secondary: const CircleAvatar(child: Icon(Icons.person)),
                              value: _uPilih.contains((u['id'] as num).toInt()),
                              onChanged: _sibuk
                                  ? null
                                  : (v) => _toggle('user', (u['id'] as num).toInt(), v ?? false),
                              title: Text(u['name'].toString()),
                              subtitle: Text(u['role'].toString()),
                            ),
                        ]),
            ),
          ]),
        ),
      ),
    );
  }
}
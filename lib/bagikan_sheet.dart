import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api.dart';
import 'waktu.dart';

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
  Map<String, String> _izinMap = {};
  String _izin = 'baca';
  String? _tautan;
  String? _tenggat;
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
    _tenggat = widget.item['tenggat'] as String?;
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
        final iz = s['izin'];
        _izinMap = iz is Map ? iz.map((k, v) => MapEntry(k.toString(), v.toString())) : {};
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
        await Api.postJson('/berbagi/${widget.jenis}/$_id', {
          'target': target,
          'target_id': tid,
          if (_folder) 'izin': _izin,
        });
        _izinMap['$target:$tid'] = _izin;
      } else {
        await Api.deleteJson('/berbagi/${widget.jenis}/$_id/$target/$tid');
        _izinMap.remove('$target:$tid');
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

  String? _label(String target, int id) {
    if (!_folder) return null;
    return _izinMap['$target:$id'] == 'kumpul' ? 'Pengumpulan tugas' : 'Hanya baca';
  }

  Future<void> _simpanTenggat(String? iso) async {
    setState(() => _sibuk = true);
    try {
      await Api.postJson('/berkas/folder/$_id/tenggat', {'tenggat': iso});
      _tenggat = iso;
      widget.item['tenggat'] = iso;
    } catch (e) {
      _snack(e.toString());
    }
    if (mounted) setState(() => _sibuk = false);
  }

  Future<void> _pilihTenggat() async {
    final sekarang = DateTime.now();
    final awal = DateTime.tryParse(_tenggat ?? '')?.toLocal() ?? sekarang.add(const Duration(days: 7));
    final tgl = await showDatePicker(
      context: context,
      initialDate: awal,
      firstDate: DateTime(2020),
      lastDate: sekarang.add(const Duration(days: 730)),
    );
    if (tgl == null || !mounted) return;
    final jam = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: awal.hour, minute: awal.minute),
    );
    if (jam == null) return;
    final t = DateTime(tgl.year, tgl.month, tgl.day, jam.hour, jam.minute);
    await _simpanTenggat(t.toUtc().toIso8601String());
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

  Widget _izinPilihan() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _judul('Izin untuk penerima yang baru dicentang'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SegmentedButton<String>(
          segments: const [
            ButtonSegment<String>(value: 'baca', label: Text('Hanya baca')),
            ButtonSegment<String>(value: 'kumpul', label: Text('Pengumpulan tugas')),
          ],
          selected: {_izin},
          onSelectionChanged: (s) => setState(() => _izin = s.first),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        child: Text(
          _izin == 'baca'
              ? 'Penerima bisa melihat dan mengunduh seluruh isi folder.'
              : 'Penerima hanya bisa mengunggah file dan hanya melihat file miliknya sendiri. '
                  'Untuk mengubah izin penerima yang sudah dicentang, hilangkan centang lalu centang lagi.',
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.event),
        title: const Text('Tenggat pengumpulan'),
        subtitle: Text(infoTenggat(_tenggat).$1),
        trailing: _tenggat == null
            ? null
            : IconButton(
                icon: const Icon(Icons.clear),
                tooltip: 'Hapus tenggat',
                onPressed: _sibuk ? null : () => _simpanTenggat(null),
              ),
        onTap: _sibuk ? null : _pilihTenggat,
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final q = _cari.trim().toLowerCase();
    final grup = _grup.where((g) => g['name'].toString().toLowerCase().contains(q)).toList();
    final users = _users.where((u) => u['name'].toString().toLowerCase().contains(q)).toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.85,
          child: Column(children: [
            ListTile(
              leading: Icon(_folder ? Icons.folder : Icons.insert_drive_file),
              title: Text(widget.item['name'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(_folder ? 'Bagikan folder' : 'Bagikan file'),
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
                          if (_folder) _izinPilihan(),
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
                              subtitle: _gPilih.contains((g['id'] as num).toInt())
                                  ? (_label('grup', (g['id'] as num).toInt()) == null
                                      ? null
                                      : Text(_label('grup', (g['id'] as num).toInt())!))
                                  : null,
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
                              subtitle: Text(_uPilih.contains((u['id'] as num).toInt()) && _folder
                                  ? '${u['role']} · ${_label('user', (u['id'] as num).toInt())}'
                                  : u['role'].toString()),
                            ),
                        ]),
            ),
          ]),
        ),
      ),
    );
  }
}
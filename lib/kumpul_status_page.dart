import 'package:flutter/material.dart';
import 'api.dart';
import 'pratinjau.dart';
import 'util.dart';
import 'waktu.dart';

class KumpulStatusPage extends StatefulWidget {
  final Map<String, dynamic> folder; // id dan name
  const KumpulStatusPage({super.key, required this.folder});
  @override
  State<KumpulStatusPage> createState() => _KumpulStatusPageState();
}

class _KumpulStatusPageState extends State<KumpulStatusPage> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  bool _belumSaja = false;

  int get _id => (widget.folder['id'] as num).toInt();

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setState(() {
      _loading = _data == null;
      _error = null;
    });
    try {
      final d = await Api.getJson('/kumpul/$_id/status');
      if (mounted) {
        setState(() {
          _data = Map<String, dynamic>.from(d as Map);
          _loading = false;
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
    final d = _data!;
    final total = (d['total'] as num).toInt();
    final sudah = (d['sudah'] as num).toInt();
    final (teks, lewat) = infoTenggat((d['folder'] as Map)['tenggat'] as String?);
    final semua = (d['peserta'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final daftar = _belumSaja ? semua.where((e) => (e['jumlah'] as num) == 0).toList() : semua;

    if (total == 0) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Belum ada peserta. Bagikan folder ini ke grup atau pengguna dengan izin "Pengumpulan tugas".',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Container(
            width: double.infinity,
            color: const Color(0xFFEEF4F8),
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$sudah dari $total sudah mengumpulkan',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(teks, style: TextStyle(color: lewat ? Colors.red : null)),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: total == 0 ? 0 : sudah / total),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilterChip(
                label: const Text('Belum mengumpulkan saja'),
                selected: _belumSaja,
                onSelected: (v) => setState(() => _belumSaja = v),
              ),
            ),
          ),
          if (daftar.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('Semua sudah mengumpulkan.')),
            ),
          for (final p in daftar) _baris(p),
        ],
      ),
    );
  }

  Widget _baris(Map<String, dynamic> p) {
    final jumlah = (p['jumlah'] as num).toInt();
    final files = (p['files'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final terlambat = p['terlambat'] == true;

    final status = jumlah == 0
        ? 'Belum mengumpulkan'
        : '$jumlah file${terlambat ? ' · Ada yang terlambat' : ''}';
    final warna = jumlah == 0
        ? Colors.red
        : (terlambat ? Colors.orange.shade800 : const Color(0xFF2E7D32));

    final judul = Text(p['name'].toString());
    final sub = Text(status, style: TextStyle(color: warna));
    final ikon = Icon(
      jumlah == 0 ? Icons.radio_button_unchecked : Icons.check_circle,
      color: warna,
    );

    if (jumlah == 0) {
      return ListTile(leading: ikon, title: judul, subtitle: sub);
    }
    return ExpansionTile(
      leading: ikon,
      title: judul,
      subtitle: sub,
      children: [
        for (final f in files)
          ListTile(
            contentPadding: const EdgeInsets.only(left: 32, right: 16),
            leading: IkonFile(nama: f['name'].toString(), url: f['url'].toString(), ukuran: 36),
            title: Text(f['name'].toString(), maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${ukuranFile((f['size'] as num).toInt())} · ${fmtWaktu(DateTime.parse(f['waktu'].toString()))}'
              '${f['terlambat'] == true ? ' · Terlambat' : ''}',
              style: TextStyle(color: f['terlambat'] == true ? Colors.red : null),
            ),
            onTap: () => bukaPintar(context, files, f),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Pengumpulan: ${widget.folder['name']}', maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: _body(),
    );
  }
}
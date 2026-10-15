import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:video_player/video_player.dart';
import 'api.dart';
import 'lokal.dart';
import 'util.dart';

// Jenis yang bisa dipratinjau di dalam aplikasi: 'gambar', 'video', 'pdf'; selain itu null.
String? jenisPratinjau(String nama) {
  final n = nama.toLowerCase();
  if (RegExp(r'\.(jpg|jpeg|png|gif|webp|bmp)$').hasMatch(n)) return 'gambar';
  if (RegExp(r'\.(mp4|m4v|mov|mkv|webm|3gp)$').hasMatch(n)) return 'video';
  if (n.endsWith('.pdf')) return 'pdf';
  return null;
}

// Buka berkas: pratinjau di aplikasi kalau didukung, kalau tidak lewat aplikasi lain.
// [daftar] = file yang sedang tampil (untuk geser antar gambar), tiap item punya 'name' dan 'url'.
Future<void> bukaPintar(
  BuildContext context,
  List<Map<String, dynamic>> daftar,
  Map<String, dynamic> item,
) async {
  final nama = item['name'].toString();
  final url = item['url'].toString();
  final jenis = jenisPratinjau(nama);
  final nav = Navigator.of(context);

  if (jenis == null) {
    await bukaBerkas(context, url, nama);
    return;
  }
  if (jenis == 'gambar') {
    final galeri = daftar
        .where((e) => e['tipe'] != 'folder' && jenisPratinjau(e['name'].toString()) == 'gambar')
        .toList();
    var awal = galeri.indexWhere((e) => e['url'] == url);
    if (awal < 0) {
      galeri.insert(0, item);
      awal = 0;
    }
    await nav.push(MaterialPageRoute(
      builder: (_) => GaleriGambarPage(
        items: galeri.map((e) => (e['url'].toString(), e['name'].toString())).toList(),
        awal: awal,
      ),
    ));
    return;
  }
  await nav.push(MaterialPageRoute(
    builder: (_) => jenis == 'video'
        ? VideoPratinjauPage(url: url, nama: nama)
        : PdfPratinjauPage(url: url, nama: nama),
  ));
}

// Mengunduh file (dengan progres) lalu menampilkan [builder] dengan jalur lokalnya.
class MuatBerkas extends StatefulWidget {
  final String url;
  final String nama;
  final Widget Function(BuildContext context, String path) builder;
  const MuatBerkas({super.key, required this.url, required this.nama, required this.builder});
  @override
  State<MuatBerkas> createState() => _MuatBerkasState();
}

class _MuatBerkasState extends State<MuatBerkas> {
  String? _path;
  String? _error;
  double _prog = -1;
  Pembatal _batal = Pembatal();

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    _batal.batal = true;
    super.dispose();
  }

  void _ulang() {
    setState(() {
      _error = null;
      _prog = -1;
    });
    _muat();
  }

  Future<void> _muat() async {
    _batal = Pembatal();
    try {
      final p = await Api.download(widget.url, widget.nama, pembatal: _batal, onProgress: (d, t) {
        if (!mounted) return;
        final v = t > 0 ? d / t : -1.0;
        if ((v - _prog).abs() >= 0.01) setState(() => _prog = v);
      });
      if (mounted) setState(() => _path = p);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _path;
    if (p != null) return widget.builder(context, p);

    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, style: const TextStyle(color: Colors.white)),
          const SizedBox(height: 12),
          FilledButton(onPressed: _ulang, child: const Text('Coba lagi')),
          TextButton(
            onPressed: () => bukaBerkas(context, widget.url, widget.nama),
            child: const Text('Buka dengan aplikasi lain'),
          ),
        ]),
      );
    }
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 56,
          height: 56,
          child: CircularProgressIndicator(value: _prog < 0 ? null : _prog, color: Colors.white),
        ),
        const SizedBox(height: 12),
        Text(
          _prog < 0 ? 'Mengunduh...' : 'Mengunduh ${(_prog * 100).round()}%',
          style: const TextStyle(color: Colors.white),
        ),
      ]),
    );
  }
}

AppBar _barGelap(BuildContext context, String judul, String url, String nama) {
  return AppBar(
    backgroundColor: Colors.black,
    foregroundColor: Colors.white,
    title: Text(judul, style: const TextStyle(fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
    actions: [
      IconButton(
        icon: const Icon(Icons.download),
        tooltip: 'Simpan ke Unduhan',
        onPressed: () => simpanKeUnduhan(context, url, nama),
      ),
      IconButton(
        icon: const Icon(Icons.open_in_new),
        tooltip: 'Buka dengan aplikasi lain',
        onPressed: () => bukaBerkas(context, url, nama),
      ),
    ],
  );
}

// ---------- gambar ----------

class GaleriGambarPage extends StatefulWidget {
  final List<(String, String)> items; // (url, nama)
  final int awal;
  const GaleriGambarPage({super.key, required this.items, required this.awal});
  @override
  State<GaleriGambarPage> createState() => _GaleriGambarPageState();
}

class _GaleriGambarPageState extends State<GaleriGambarPage> {
  late final PageController _pc = PageController(initialPage: widget.awal);
  late int _i = widget.awal;
  bool _zoom = false;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (url, nama) = widget.items[_i];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _barGelap(context, '${_i + 1}/${widget.items.length} · $nama', url, nama),
      body: PageView.builder(
        controller: _pc,
        // Saat gambar diperbesar, geser dipakai untuk menggeser gambar, bukan pindah halaman.
        physics: _zoom ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
        itemCount: widget.items.length,
        onPageChanged: (i) => setState(() {
          _i = i;
          _zoom = false;
        }),
        itemBuilder: (context, i) {
          final it = widget.items[i];
          return MuatBerkas(
            key: ValueKey(it.$1),
            url: it.$1,
            nama: it.$2,
            builder: (context, path) => _HalamanGambar(
              path: path,
              onZoom: (z) {
                if (z != _zoom) setState(() => _zoom = z);
              },
            ),
          );
        },
      ),
    );
  }
}

class _HalamanGambar extends StatefulWidget {
  final String path;
  final ValueChanged<bool> onZoom;
  const _HalamanGambar({required this.path, required this.onZoom});
  @override
  State<_HalamanGambar> createState() => _HalamanGambarState();
}

class _HalamanGambarState extends State<_HalamanGambar> {
  final _ctl = TransformationController();
  Offset _tap = Offset.zero;

  @override
  void initState() {
    super.initState();
    _ctl.addListener(_ubah);
  }

  @override
  void dispose() {
    _ctl.removeListener(_ubah);
    _ctl.dispose();
    super.dispose();
  }

  bool get _diperbesar => _ctl.value.getMaxScaleOnAxis() > 1.02;

  void _ubah() => widget.onZoom(_diperbesar);

  // Ketuk dua kali: perbesar di titik yang diketuk, atau kembali ke ukuran awal.
  void _dobelKetuk() {
    final m = Matrix4.identity();
    if (!_diperbesar) {
      const s = 2.5;
      m.setEntry(0, 0, s);
      m.setEntry(1, 1, s);
      m.setEntry(0, 3, -_tap.dx * (s - 1));
      m.setEntry(1, 3, -_tap.dy * (s - 1));
    }
    _ctl.value = m;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: (d) => _tap = d.localPosition,
      onDoubleTap: _dobelKetuk,
      child: InteractiveViewer(
        transformationController: _ctl,
        minScale: 1,
        maxScale: 6,
        child: SizedBox.expand(
          child: Image.file(
            File(widget.path),
            fit: BoxFit.contain,
            cacheWidth: 3000,
            errorBuilder: (_, __, ___) => const Center(
              child: Text('Gambar tidak bisa ditampilkan.', style: TextStyle(color: Colors.white)),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- video ----------

class VideoPratinjauPage extends StatelessWidget {
  final String url;
  final String nama;
  const VideoPratinjauPage({super.key, required this.url, required this.nama});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _barGelap(context, nama, url, nama),
      body: MuatBerkas(
        url: url,
        nama: nama,
        builder: (context, path) => _VideoHalaman(path: path, url: url, nama: nama),
      ),
    );
  }
}

class _VideoHalaman extends StatefulWidget {
  final String path;
  final String url;
  final String nama;
  const _VideoHalaman({required this.path, required this.url, required this.nama});
  @override
  State<_VideoHalaman> createState() => _VideoHalamanState();
}

class _VideoHalamanState extends State<_VideoHalaman> {
  late final VideoPlayerController _c;
  bool _siap = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _c = VideoPlayerController.file(File(widget.path));
    _mulai();
  }

  Future<void> _mulai() async {
    try {
      await _c.initialize();
      if (!mounted) return;
      setState(() => _siap = true);
      await _c.play();
    } catch (_) {
      if (mounted) setState(() => _err = 'Video ini tidak bisa diputar di aplikasi.');
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  void _toggle() {
    if (_c.value.isPlaying) {
      _c.pause();
    } else {
      _c.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_err != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_err!, style: const TextStyle(color: Colors.white)),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => bukaBerkas(context, widget.url, widget.nama),
            child: const Text('Buka dengan aplikasi lain'),
          ),
        ]),
      );
    }
    if (!_siap) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    return Column(children: [
      Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggle,
          child: Center(
            child: AspectRatio(aspectRatio: _c.value.aspectRatio, child: VideoPlayer(_c)),
          ),
        ),
      ),
      SafeArea(
        top: false,
        child: ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: _c,
          builder: (context, v, _) {
            final dur = v.duration.inMilliseconds < 1 ? 1 : v.duration.inMilliseconds;
            final pos = v.position.inMilliseconds.clamp(0, dur);
            return Row(children: [
              IconButton(
                color: Colors.white,
                icon: Icon(v.isPlaying ? Icons.pause : Icons.play_arrow),
                onPressed: _toggle,
              ),
              Text(_fmt(v.position), style: const TextStyle(color: Colors.white, fontSize: 12)),
              Expanded(
                child: Slider(
                  value: pos.toDouble(),
                  max: dur.toDouble(),
                  onChanged: (x) => _c.seekTo(Duration(milliseconds: x.round())),
                ),
              ),
              Text(_fmt(v.duration), style: const TextStyle(color: Colors.white, fontSize: 12)),
              const SizedBox(width: 12),
            ]);
          },
        ),
      ),
    ]);
  }
}

// ---------- PDF ----------

class PdfPratinjauPage extends StatelessWidget {
  final String url;
  final String nama;
  const PdfPratinjauPage({super.key, required this.url, required this.nama});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade900,
      appBar: _barGelap(context, nama, url, nama),
      body: MuatBerkas(
        url: url,
        nama: nama,
        builder: (context, path) => PdfViewer.file(path),
      ),
    );
  }
}

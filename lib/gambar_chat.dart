import 'dart:io';
import 'package:flutter/material.dart';
import 'api.dart';
import 'lokal.dart';

class GambarChat extends StatefulWidget {
  final String url;
  final String nama;
  final String ukuranTeks;
  final String? lokal; // jalur file untuk foto yang sedang dikirim
  final bool pending;
  final double? progres;
  final VoidCallback onTap;
  const GambarChat({
    super.key,
    required this.url,
    required this.nama,
    required this.ukuranTeks,
    required this.onTap,
    this.lokal,
    this.pending = false,
    this.progres,
  });
  @override
  State<GambarChat> createState() => _GambarChatState();
}

class _GambarChatState extends State<GambarChat> {
  String? _path;
  bool _gagal = false;
  bool _manual = false;
  bool _mengunduh = false;
  double _prog = -1;
  final _batal = Pembatal();

  static double _mb(String teks) {
    final m = RegExp(r'([\d.,]+)\s*(KB|MB)').firstMatch(teks);
    if (m == null) return 0;
    final v = double.tryParse(m.group(1)!.replaceAll(',', '.')) ?? 0;
    return m.group(2) == 'MB' ? v : v / 1024;
  }

  @override
  void initState() {
    super.initState();
    if (widget.pending || widget.url.isEmpty) return;
    _path = Lokal.pathSync(widget.url);
    if (_path == null) {
      if (_mb(widget.ukuranTeks) > 8) {
        _manual = true;
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) => _unduh());
      }
    }
  }

  @override
  void dispose() {
    _batal.batal = true;
    super.dispose();
  }

  Future<void> _unduh() async {
    if (_mengunduh || !mounted) return;
    setState(() {
      _mengunduh = true;
      _gagal = false;
      _manual = false;
      _prog = -1;
    });
    try {
      final p = await Api.download(widget.url, widget.nama, pembatal: _batal, onProgress: (d, t) {
        final v = t > 0 ? d / t : -1.0;
        if (mounted && (v - _prog).abs() >= 0.02) setState(() => _prog = v);
      });
      if (mounted) setState(() => _path = p);
    } catch (_) {
      if (mounted) setState(() => _gagal = true);
    }
    if (mounted) setState(() => _mengunduh = false);
  }

  Widget _lapis(Widget isi) => Positioned.fill(
        child: Container(color: Colors.black38, child: Center(child: isi)),
      );

  @override
  Widget build(BuildContext context) {
    final p = widget.lokal ?? _path;
    final siap = p != null;
    const teksPutih = TextStyle(color: Colors.white, fontSize: 12);

    return GestureDetector(
      onTap: () {
        if (widget.pending) return;
        if (siap) {
          widget.onTap();
        } else if (_manual || _gagal) {
          _unduh();
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 240,
          height: 240,
          child: Stack(children: [
            Positioned.fill(
              child: siap
                  ? Image.file(
                      File(p),
                      fit: BoxFit.cover,
                      cacheWidth: 720,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.black12,
                        child: const Icon(Icons.broken_image, size: 40),
                      ),
                    )
                  : Container(color: Colors.black12, child: const Icon(Icons.image, size: 48, color: Colors.black26)),
            ),
            if (widget.pending)
              _lapis(SizedBox(
                width: 44,
                height: 44,
                child: CircularProgressIndicator(value: widget.progres, color: Colors.white),
              )),
            if (_mengunduh)
              _lapis(GestureDetector(
                onTap: () => _batal.batal = true,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: CircularProgressIndicator(value: _prog < 0 ? null : _prog, color: Colors.white),
                  ),
                  const SizedBox(height: 6),
                  Text(_prog < 0 ? 'Mengunduh...' : '${(_prog * 100).round()}%', style: teksPutih),
                ]),
              )),
            if (_manual)
              _lapis(Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.download, color: Colors.white, size: 36),
                const SizedBox(height: 4),
                Text(widget.ukuranTeks, style: teksPutih),
              ])),
            if (_gagal && !_mengunduh)
              _lapis(Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.refresh, color: Colors.white, size: 36),
                const SizedBox(height: 4),
                const Text('Gagal. Ketuk untuk ulangi', style: teksPutih),
              ])),
          ]),
        ),
      ),
    );
  }
}

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class TeksTautan extends StatefulWidget {
  final String teks;
  const TeksTautan(this.teks, {super.key});
  @override
  State<TeksTautan> createState() => _TeksTautanState();
}

class _TeksTautanState extends State<TeksTautan> {
  final _rec = <TapGestureRecognizer>[];
  static final _pola = RegExp(r'((https?:\/\/|www\.)[^\s]+)', caseSensitive: false);

  void _bersih() {
    for (final r in _rec) {
      r.dispose();
    }
    _rec.clear();
  }

  @override
  void dispose() {
    _bersih();
    super.dispose();
  }

  Future<void> _buka(String u) async {
    final uri = Uri.tryParse(u.toLowerCase().startsWith('www.') ? 'https://$u' : u);
    if (uri == null) return;
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak bisa membuka tautan ini.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    _bersih();
    final t = widget.teks;
    final spans = <InlineSpan>[];
    var akhir = 0;
    for (final m in _pola.allMatches(t)) {
      if (m.start > akhir) spans.add(TextSpan(text: t.substring(akhir, m.start)));
      final mentah = m.group(0)!;
      final url = mentah.replaceAll(RegExp(r'[.,;:!?)\]]+$'), '');
      final sisa = mentah.substring(url.length);
      final r = TapGestureRecognizer()..onTap = () => _buka(url);
      _rec.add(r);
      spans.add(TextSpan(
        text: url,
        style: const TextStyle(color: Color(0xFF0B6BCB), decoration: TextDecoration.underline),
        recognizer: r,
      ));
      if (sisa.isNotEmpty) spans.add(TextSpan(text: sisa));
      akhir = m.end;
    }
    if (akhir < t.length) spans.add(TextSpan(text: t.substring(akhir)));
    return Text.rich(TextSpan(children: spans));
  }
}

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'api.dart';
import 'lokal.dart';

String ukuranFile(int b) {
  if (b >= 1048576) return '${(b / 1048576).toStringAsFixed(1)} MB';
  final kb = (b / 1024).round();
  return '${kb < 1 ? 1 : kb} KB';
}

String kategoriFile(String nama) {
  final n = nama.toLowerCase();
  if (RegExp(r'\.(jpg|jpeg|png|gif|webp|heic)$').hasMatch(n)) return 'gambar';
  if (RegExp(r'\.(pdf|doc|docx|odt|txt|xls|xlsx|ods|csv|ppt|pptx|odp)$').hasMatch(n)) return 'dokumen';
  if (RegExp(r'\.(mp3|m4a|wav|ogg|aac|mp4|mkv|avi|mov|3gp)$').hasMatch(n)) return 'media';
  return 'lain';
}

IconData ikonFile(String nama) {
  final n = nama.toLowerCase();
  if (RegExp(r'\.(jpg|jpeg|png|gif|webp|heic)$').hasMatch(n)) return Icons.image;
  if (n.endsWith('.pdf')) return Icons.picture_as_pdf;
  if (RegExp(r'\.(doc|docx|odt|txt)$').hasMatch(n)) return Icons.description;
  if (RegExp(r'\.(xls|xlsx|ods|csv)$').hasMatch(n)) return Icons.table_chart;
  if (RegExp(r'\.(ppt|pptx|odp)$').hasMatch(n)) return Icons.slideshow;
  if (RegExp(r'\.(mp3|m4a|wav|ogg|aac)$').hasMatch(n)) return Icons.audiotrack;
  if (RegExp(r'\.(mp4|mkv|avi|mov|3gp)$').hasMatch(n)) return Icons.movie;
  if (RegExp(r'\.(zip|rar|7z)$').hasMatch(n)) return Icons.folder_zip;
  return Icons.insert_drive_file;
}

// Pengelola unduhan: progres per file (nilai -1 = belum diketahui) dan pembatalan.
class Unduhan {
  static final ValueNotifier<Map<String, double>> progres = ValueNotifier<Map<String, double>>({});
  static final Map<String, Pembatal> _batal = {};

  static void _set(String url, double v) {
    progres.value = {...progres.value, url: v};
  }

  static void _hapus(String url) {
    final n = {...progres.value};
    n.remove(url);
    progres.value = n;
  }

  static bool sedang(String url) => progres.value.containsKey(url);

  static void batal(String url) => _batal[url]?.batal = true;

  static Future<String?> mulai(BuildContext context, String url, String nama, {bool buka = true}) async {
    if (sedang(url)) return null;
    final m = ScaffoldMessenger.of(context);
    final p = Pembatal();
    _batal[url] = p;
    _set(url, -1);
    var terakhir = -2.0;
    try {
      final path = await Api.download(url, nama, pembatal: p, onProgress: (d, t) {
        final v = t > 0 ? d / t : -1.0;
        if ((v - terakhir).abs() >= 0.01 || v == 1) {
          terakhir = v;
          _set(url, v);
        }
      });
      if (buka) {
        final r = await OpenFilex.open(path);
        if (r.type != ResultType.done) {
          m.showSnackBar(const SnackBar(content: Text('Tidak ada aplikasi untuk membuka file ini.')));
        }
      } else {
        m.showSnackBar(SnackBar(content: Text('Tersimpan di HP: $nama')));
      }
      return path;
    } catch (e) {
      m.showSnackBar(SnackBar(content: Text(e.toString())));
      return null;
    } finally {
      _batal.remove(url);
      _hapus(url);
    }
  }
}

// Ikon status file: lingkaran progres (ketuk untuk batal), centang hijau (di HP), atau awan (cloud).
class StatusUnduh extends StatelessWidget {
  final String url;
  const StatusUnduh({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([Unduhan.progres, Lokal.berubah]),
      builder: (context, _) {
        final p = Unduhan.progres.value[url];
        if (p != null) {
          return InkWell(
            onTap: () => Unduhan.batal(url),
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 32,
              height: 32,
              child: Stack(alignment: Alignment.center, children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(value: p < 0 ? null : p, strokeWidth: 3),
                ),
                const Icon(Icons.close, size: 12),
              ]),
            ),
          );
        }
        if (Lokal.ada(url)) {
          return const Tooltip(
            message: 'Tersimpan di HP',
            child: Icon(Icons.offline_pin, size: 22, color: Color(0xFF2E7D32)),
          );
        }
        return const Tooltip(
          message: 'Hanya di cloud',
          child: Icon(Icons.cloud_outlined, size: 22, color: Colors.black38),
        );
      },
    );
  }
}

Future<void> bukaBerkas(BuildContext context, String url, String nama) async {
  await Unduhan.mulai(context, url, nama);
}

// Jalur file lokal bila ada; kalau tidak, salin dulu ke folder sementara.
Future<String?> lokalPath(PlatformFile f) async {
  final p = f.path;
  if (p != null && p.isNotEmpty && !p.startsWith('content:')) return p;
  try {
    final dir = await getTemporaryDirectory();
    final tmp = File('${dir.path}/up_${DateTime.now().millisecondsSinceEpoch}_${f.name}');
    await f.readAsByteStream().cast<List<int>>().pipe(tmp.openWrite());
    return tmp.path;
  } catch (_) {
    return null;
  }
}
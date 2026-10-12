import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'api.dart';

String ukuranFile(int b) {
  if (b >= 1048576) return '${(b / 1048576).toStringAsFixed(1)} MB';
  final kb = (b / 1024).round();
  return '${kb < 1 ? 1 : kb} KB';
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

bool _membuka = false;

// Unduh (atau pakai salinan yang sudah ada) lalu buka dengan aplikasi bawaan HP.
Future<void> bukaBerkas(BuildContext context, String url, String nama) async {
  if (_membuka) return;
  _membuka = true;
  final m = ScaffoldMessenger.of(context);
  try {
    m.showSnackBar(SnackBar(content: Text('Mengunduh $nama...')));
    final path = await Api.download(url, nama);
    final r = await OpenFilex.open(path);
    if (r.type != ResultType.done) {
      m.showSnackBar(const SnackBar(content: Text('Tidak ada aplikasi untuk membuka file ini.')));
    }
  } catch (e) {
    m.showSnackBar(SnackBar(content: Text(e.toString())));
  } finally {
    _membuka = false;
  }
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
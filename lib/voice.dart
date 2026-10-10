import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'api.dart';

class VoiceNote {
  static final _pola = RegExp(r'^suara_\d{8}_\d{6}_(\d+)s\.m4a$');

  // Mengembalikan durasi (detik) bila nama file adalah pesan suara, selain itu null.
  static int? detik(String nama) {
    final m = _pola.firstMatch(nama);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  static String format(int detik) {
    final m = detik ~/ 60;
    final s = detik % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

// Satu pemutar bersama: hanya satu pesan suara yang diputar pada satu waktu.
class VoiceHub {
  static final AudioPlayer player = AudioPlayer();
  static final ValueNotifier<String?> aktif = ValueNotifier(null);
  static final ValueNotifier<bool> memutar = ValueNotifier(false);
  static final ValueNotifier<Duration> posisi = ValueNotifier(Duration.zero);
  static final ValueNotifier<Duration> durasi = ValueNotifier(Duration.zero);
  static bool _siap = false;

  static void _init() {
    if (_siap) return;
    _siap = true;
    player.onPlayerStateChanged.listen((s) => memutar.value = s == PlayerState.playing);
    player.onPositionChanged.listen((p) => posisi.value = p);
    player.onDurationChanged.listen((d) => durasi.value = d);
    player.onPlayerComplete.listen((_) {
      memutar.value = false;
      posisi.value = Duration.zero;
      aktif.value = null;
    });
  }

  static Future<void> toggle(String url, String nama) async {
    _init();
    if (aktif.value == url) {
      if (memutar.value) {
        await player.pause();
      } else {
        await player.resume();
      }
      return;
    }
    await player.stop();
    aktif.value = url;
    posisi.value = Duration.zero;
    durasi.value = Duration.zero;
    try {
      final path = await Api.download(url, nama);
      if (aktif.value != url) return; // pengguna sudah pindah ke suara lain
      await player.play(DeviceFileSource(path));
    } catch (e) {
      if (aktif.value == url) aktif.value = null;
      rethrow;
    }
  }

  static Future<void> stop() async {
    if (!_siap) return;
    try {
      await player.stop();
    } catch (_) {}
    aktif.value = null;
    memutar.value = false;
    posisi.value = Duration.zero;
  }
}

class VoiceTile extends StatelessWidget {
  final String url; // kosong = masih dikirim
  final String nama;
  final int detik;
  const VoiceTile({super.key, required this.url, required this.nama, required this.detik});

  Future<void> _tekan(BuildContext context) async {
    try {
      await VoiceHub.toggle(url, nama);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 230,
      child: AnimatedBuilder(
        animation: Listenable.merge([
          VoiceHub.aktif,
          VoiceHub.memutar,
          VoiceHub.posisi,
          VoiceHub.durasi,
        ]),
        builder: (context, _) {
          final aktif = url.isNotEmpty && VoiceHub.aktif.value == url;
          final memutar = aktif && VoiceHub.memutar.value;
          final adaDurasi = VoiceHub.durasi.value.inMilliseconds > 0;
          final memuat = aktif && !memutar && !adaDurasi;
          final dur = aktif && adaDurasi ? VoiceHub.durasi.value : Duration(seconds: detik);
          final pos = aktif ? VoiceHub.posisi.value : Duration.zero;
          final maks = dur.inMilliseconds < 1 ? 1 : dur.inMilliseconds;
          final nilai = pos.inMilliseconds.clamp(0, maks).toDouble();

          Widget tombol;
          if (memuat) {
            tombol = const Padding(
              padding: EdgeInsets.all(10),
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          } else {
            tombol = IconButton(
              padding: EdgeInsets.zero,
              iconSize: 36,
              icon: Icon(url.isEmpty
                  ? Icons.access_time
                  : (memutar ? Icons.pause_circle_filled : Icons.play_circle_filled)),
              onPressed: url.isEmpty ? null : () => _tekan(context),
            );
          }

          return Row(children: [
            SizedBox(width: 40, height: 40, child: tombol),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 24,
                    child: Slider(
                      value: nilai,
                      max: maks.toDouble(),
                      onChanged: aktif
                          ? (v) => VoiceHub.player.seek(Duration(milliseconds: v.round()))
                          : null,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Text(
                      aktif
                          ? '${VoiceNote.format(pos.inSeconds)} / ${VoiceNote.format(dur.inSeconds)}'
                          : VoiceNote.format(detik),
                      style: const TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                  ),
                ],
              ),
            ),
          ]);
        },
      ),
    );
  }
}
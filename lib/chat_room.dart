import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'api.dart';
import 'voice.dart';
import 'util.dart';
import 'pratinjau.dart';

class ChatRoomPage extends StatefulWidget {
  final bool grup;
  final int id;
  final String nama;
  const ChatRoomPage({super.key, required this.grup, required this.id, required this.nama});
  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage> {
  final _input = TextEditingController();
  final AudioRecorder _rec = AudioRecorder();
  List<Map<String, dynamic>> _msgs = [];
  final List<Map<String, dynamic>> _pending = [];
  Map<String, dynamic>? _replyTo;
  bool _loading = true;
  String? _error;
  Timer? _timer;
  Timer? _rekamTimer;
  bool _polling = false;
  bool _membuka = false;
  bool _merekam = false;
  int _detikRekam = 0;
  int _tempId = 0;

  String get _base => widget.grup ? '/grup/${widget.id}' : '/obrolan/${widget.id}';
  String get _cacheKey => widget.grup ? 'room_g_${widget.id}' : 'room_p_${widget.id}';
  String get _sendPath => widget.grup ? '/grup/${widget.id}/kirim' : '/obrolan/${widget.id}';
  String get _deleteBase => widget.grup ? '/grup/pesan' : '/obrolan/pesan';

  int get _lastId {
    var last = 0;
    for (final m in _msgs) {
      final id = m['id'] as int;
      if (id > last) last = id;
    }
    return last;
  }

  List<Map<String, dynamic>> _toList(List raw) =>
      raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _rekamTimer?.cancel();
    _input.dispose();
    VoiceHub.stop();
    if (_merekam) {
      _rec.cancel().whenComplete(_rec.dispose);
    } else {
      _rec.dispose();
    }
    super.dispose();
  }

  Future<void> _init() async {
    final c = await Api.readCache(_cacheKey);
    if (c is List && mounted) {
      setState(() {
        _msgs = _toList(c);
        _loading = false;
      });
    }
    await _loadFull();
    if (!mounted) return;
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
  }

  void _simpanCache() {
    Api.writeCache(_cacheKey, _msgs.length > 50 ? _msgs.sublist(_msgs.length - 50) : _msgs);
  }

  // Tandai pesan saya dengan id <= upto sebagai sudah dibaca
  // (chat pribadi: oleh lawan bicara, grup: oleh semua anggota lain).
  void _tandaiDibaca(int upto) {
    if (upto <= 0) return;
    for (final m in _msgs) {
      if (m['mine'] == true && (m['id'] as int) <= upto) m['dibaca'] = true;
    }
  }

  Future<void> _loadFull() async {
    try {
      final data = await Api.getJson(_base);
      final list = _toList(data['messages'] as List);
      if (!mounted) return;
      setState(() {
        _msgs = list;
        _tandaiDibaca((data['read_upto'] ?? 0) as int);
        _loading = false;
        _error = null;
      });
      _simpanCache();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          if (_msgs.isEmpty) _error = e.toString();
        });
      }
    }
  }

  Future<void> _poll({bool tunggu = false}) async {
    if (!mounted) return;
    if (_polling) {
      if (!tunggu) return;
      for (var i = 0; i < 30 && _polling; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      if (_polling || !mounted) return;
    }
    _polling = true;
    try {
      final data = await Api.getJson('$_base/baru?after=$_lastId');
      if (!mounted) return;
      final baru = _toList(data['messages'] as List);
      final dihapus = ((data['deleted_ids'] ?? []) as List).map((e) => e as int).toSet();
      final dibacaSampai = (data['read_upto'] ?? 0) as int;
      setState(() {
        final ada = _msgs.map((m) => m['id'] as int).toSet();
        for (final m in baru) {
          if (!ada.contains(m['id'] as int)) _msgs.add(m);
        }
        for (final m in _msgs) {
          final id = m['id'] as int;
          if (dihapus.contains(id)) {
            m['dihapus'] = true;
            m['body'] = '';
            m['file'] = null;
          }
        }
        _tandaiDibaca(dibacaSampai);
      });
      _simpanCache();
    } catch (_) {
    } finally {
      _polling = false;
    }
  }

  String _cuplikan(Map<String, dynamic> m) {
    if (m['dihapus'] == true) return 'Pesan dihapus';
    final f = m['file'];
    if (f is Map) {
      final nama = f['name'].toString();
      if (VoiceNote.detik(nama) != null) return '\u{1F3A4} Pesan suara';
      return '\u{1F4CE} $nama';
    }
    final b = (m['body'] ?? '').toString().replaceAll('\n', ' ');
    return b.length > 60 ? '${b.substring(0, 60)}...' : b;
  }

  String _namaPengirim(Map<String, dynamic> m) {
    if (m['mine'] == true) return 'Anda';
    if (widget.grup) return (m['sender'] ?? 'Pengguna').toString();
    return widget.nama;
  }

  String _jamSekarang() {
    final n = TimeOfDay.now();
    final j = n.hour.toString().padLeft(2, '0');
    final mnt = n.minute.toString().padLeft(2, '0');
    return '$j:$mnt';
  }

  String _stamp() {
    final n = DateTime.now();
    String d2(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${d2(n.month)}${d2(n.day)}_${d2(n.hour)}${d2(n.minute)}${d2(n.second)}';
  }

  String _ukuran(int b) {
    if (b >= 1048576) return '${(b / 1048576).toStringAsFixed(1)} MB';
    final kb = (b / 1024).round();
    return '${kb < 1 ? 1 : kb} KB';
  }

  void _snack(String teks) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(teks)));
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final reply = _replyTo;
    final temp = <String, dynamic>{
      'id': --_tempId,
      'mine': true,
      'sender': 'Anda',
      'body': text,
      'time': _jamSekarang(),
      'balas': reply == null
          ? null
          : {'id': reply['id'], 'nama': _namaPengirim(reply), 'cuplikan': _cuplikan(reply)},
      'dihapus': false,
      'hari': 'Hari ini',
      'file': null,
      'pending': true,
    };
    setState(() {
      _pending.add(temp);
      _replyTo = null;
      _input.clear();
    });
    try {
      await Api.postJson(_sendPath, {'body': text, if (reply != null) 'reply_to': reply['id']});
      await _poll(tunggu: true);
      if (mounted) setState(() => _pending.remove(temp));
    } catch (e) {
      if (mounted) {
        setState(() {
          _pending.remove(temp);
          _input.text = text;
          _replyTo = reply;
        });
      }
      _snack('Gagal mengirim: $e');
    }
  }

  // Pakai jalur file lokal bila ada; kalau tidak, salin dulu ke folder sementara.
  Future<String?> _lokalPath(PlatformFile f) async {
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

  Future<void> _kirimFile() async {
    PlatformFile? f;
    try {
      f = await FilePicker.pickFile();
    } catch (e) {
      _snack('Tidak bisa membuka pemilih file.');
      return;
    }
    if (f == null) return;
    final bytes = await f.length() ?? 0;
    if (bytes > 100 * 1024 * 1024) {
      _snack('Ukuran file maksimal 100 MB.');
      return;
    }
    final path = await _lokalPath(f);
    if (path == null) {
      _snack('File tidak bisa dibaca.');
      return;
    }
    await _kirimBerkas(path, f.name, bytes, hapusSetelah: path != f.path);
  }

  // Kirim satu file (dari pemilih file atau rekaman suara) dengan gelembung "mengirim".
  Future<void> _kirimBerkas(String path, String nama, int bytes, {bool hapusSetelah = false}) async {
    final caption = _input.text.trim();
    final reply = _replyTo;
    final temp = <String, dynamic>{
      'id': --_tempId,
      'mine': true,
      'sender': 'Anda',
      'body': caption,
      'time': _jamSekarang(),
      'balas': reply == null
          ? null
          : {'id': reply['id'], 'nama': _namaPengirim(reply), 'cuplikan': _cuplikan(reply)},
      'dihapus': false,
      'hari': 'Hari ini',
      'file': {'name': nama, 'size': _ukuran(bytes), 'url': ''},
      'pending': true,
    };
    setState(() {
      _pending.add(temp);
      _replyTo = null;
      _input.clear();
    });
    try {
      var terakhir = 0.0;
      await Api.uploadFile(_sendPath, path, nama,
          caption: caption,
          replyTo: reply == null ? null : reply['id'] as int,
          onProgress: (s, t) {
            if (t <= 0) return;
            final p = s / t;
            if (p - terakhir < 0.02 && p < 1) return;
            terakhir = p;
            if (mounted) setState(() => temp['progres'] = p);
          });
    } catch (e) {
      if (mounted) {
        setState(() {
          _pending.remove(temp);
          _input.text = caption;
          _replyTo = reply;
        });
      }
      _snack('Gagal mengirim: $e');
    } finally {
      if (hapusSetelah) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _mulaiRekam() async {
    if (_merekam) return;
    try {
      if (!await _rec.hasPermission()) {
        _snack('Izin mikrofon ditolak. Aktifkan di pengaturan HP.');
        return;
      }
      await VoiceHub.stop();
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _rec.start(const RecordConfig(), path: path);
      _detikRekam = 0;
      _rekamTimer?.cancel();
      _rekamTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _detikRekam++);
        if (_detikRekam >= 300) _selesaiRekam();
      });
      if (mounted) setState(() => _merekam = true);
    } catch (e) {
      _snack('Tidak bisa mulai merekam.');
    }
  }

  Future<void> _selesaiRekam() async {
    if (!_merekam) return;
    _rekamTimer?.cancel();
    final detik = _detikRekam;
    setState(() => _merekam = false);
    String? path;
    try {
      path = await _rec.stop();
    } catch (_) {}
    if (path == null) {
      _snack('Rekaman gagal.');
      return;
    }
    if (detik < 1) {
      try {
        await File(path).delete();
      } catch (_) {}
      _snack('Rekaman terlalu pendek.');
      return;
    }
    final bytes = await File(path).length();
    await _kirimBerkas(path, 'suara_${_stamp()}_${detik}s.m4a', bytes, hapusSetelah: true);
  }

  Future<void> _batalRekam() async {
    _rekamTimer?.cancel();
    if (mounted) setState(() => _merekam = false);
    try {
      await _rec.cancel();
    } catch (_) {}
  }

  

  Future<void> _hapus(Map<String, dynamic> m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus pesan?'),
        content: const Text('Pesan akan dihapus untuk semua orang.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Hapus')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.deleteJson('$_deleteBase/${m['id']}');
      if (mounted) {
        setState(() {
          m['dihapus'] = true;
          m['body'] = '';
          m['file'] = null;
        });
        _simpanCache();
      }
    } catch (e) {
      _snack('Gagal menghapus: $e');
    }
  }

  void _menu(Map<String, dynamic> m) {
    if (m['pending'] == true || m['dihapus'] == true) return;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.reply),
            title: const Text('Balas'),
            onTap: () {
              Navigator.pop(ctx);
              setState(() => _replyTo = m);
            },
          ),
          if (m['mine'] == true)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Hapus'),
              onTap: () {
                Navigator.pop(ctx);
                _hapus(m);
              },
            ),
        ]),
      ),
    );
  }

  List<Object> _rows() {
    final semua = [..._msgs, ..._pending];
    final rows = <Object>[];
    String? terakhir;
    for (final m in semua) {
      final h = (m['hari'] ?? '').toString();
      if (h != terakhir) {
        rows.add(h);
        terakhir = h;
      }
      rows.add(m);
    }
    return rows.reversed.toList();
  }

    Widget _lampiran(Map file, Map<String, dynamic> m) {
    final nama = file['name'].toString();
    final url = (file['url'] ?? '').toString();
    final detik = VoiceNote.detik(nama);
    if (detik != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: VoiceTile(url: url, nama: nama, detik: detik),
      );
    }
    final pending = m['pending'] == true;
    final prog = m['progres'];
    return GestureDetector(
            onTap: pending
          ? null
          : () => bukaPintar(
                context,
                <Map<String, dynamic>>[{'name': nama, 'url': url}],
                <String, dynamic>{'name': nama, 'url': url},
              ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0x0F000000),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              IkonFile(nama: nama, url: url, ukuran: 36),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nama, maxLines: 2, overflow: TextOverflow.ellipsis),
                    Text(file['size'].toString(), style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              if (!pending) ...[const SizedBox(width: 8), StatusUnduh(url: url)],
            ]),
            if (pending)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: SizedBox(
                  width: 180,
                  child: LinearProgressIndicator(value: prog is double ? prog : null),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _bubble(Map<String, dynamic> m) {
    final mine = m['mine'] == true;
    final dihapus = m['dihapus'] == true;
    final balas = m['balas'];
    final file = m['file'];
    final body = (m['body'] ?? '').toString();

    Widget? centang;
    if (m['pending'] == true) {
      centang = const Icon(Icons.access_time, size: 14, color: Colors.black45);
    } else if (mine) {
      centang = m['dibaca'] == true
          ? const Icon(Icons.done_all, size: 14, color: Color(0xFF0B7A9E))
          : const Icon(Icons.done, size: 14, color: Colors.black45);
    }

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _menu(m),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
          decoration: BoxDecoration(
            color: mine ? const Color(0xFFD7EEF7) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 2, offset: Offset(0, 1))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.grup && !mine)
                Text(
                  (m['sender'] ?? 'Pengguna').toString(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              if (balas is Map)
                Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                  decoration: const BoxDecoration(
                    color: Color(0x14000000),
                    border: Border(left: BorderSide(color: Color(0xFF0B7A9E), width: 3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(balas['nama'].toString(),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      Text(balas['cuplikan'].toString(),
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              if (dihapus)
                const Text('Pesan dihapus',
                    style: TextStyle(fontStyle: FontStyle.italic, color: Colors.black54))
              else ...[
                if (file is Map) _lampiran(file, m),
                if (body.isNotEmpty) Text(body),
              ],
              Align(
                alignment: Alignment.bottomRight,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text((m['time'] ?? '').toString(),
                      style: const TextStyle(fontSize: 11, color: Colors.black54)),
                  if (centang != null) ...[const SizedBox(width: 4), centang],
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _list() {
    if (_loading && _msgs.isEmpty && _pending.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _msgs.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              setState(() {
                _loading = true;
                _error = null;
              });
              _loadFull();
            },
            child: const Text('Coba lagi'),
          ),
        ]),
      );
    }
    final rows = _rows();
    if (rows.isEmpty) return const Center(child: Text('Belum ada pesan.'));
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final r = rows[i];
        if (r is String) {
          return Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0x14000000),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(r, style: const TextStyle(fontSize: 12)),
            ),
          );
        }
        return _bubble(r as Map<String, dynamic>);
      },
    );
  }

  Widget _barRekam() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 8, 8),
      child: Row(children: [
        IconButton(
          onPressed: _batalRekam,
          icon: const Icon(Icons.delete_outline, color: Colors.red),
        ),
        const Icon(Icons.fiber_manual_record, color: Colors.red, size: 14),
        const SizedBox(width: 6),
        Text(VoiceNote.format(_detikRekam), style: const TextStyle(fontSize: 16)),
        const Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: 12),
            child: Text('Merekam...', style: TextStyle(color: Colors.black54)),
          ),
        ),
        IconButton.filled(onPressed: _selesaiRekam, icon: const Icon(Icons.send)),
      ]),
    );
  }

  Widget _inputBar() {
    final reply = _replyTo;
    return SafeArea(
      top: false,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (reply != null)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Membalas ${_namaPengirim(reply)}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    Text(_cuplikan(reply),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _replyTo = null),
              ),
            ]),
          ),
        if (_merekam)
          _barRekam()
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 8, 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              IconButton(onPressed: _kirimFile, icon: const Icon(Icons.attach_file)),
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Tulis pesan',
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _input,
                builder: (context, v, _) => v.text.trim().isEmpty
                    ? IconButton.filled(onPressed: _mulaiRekam, icon: const Icon(Icons.mic))
                    : IconButton.filled(onPressed: _send, icon: const Icon(Icons.send)),
              ),
            ]),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEEF4F8),
      appBar: AppBar(title: Text(widget.nama)),
      body: Column(children: [
        Expanded(child: _list()),
        _inputBar(),
      ]),
    );
  }
}
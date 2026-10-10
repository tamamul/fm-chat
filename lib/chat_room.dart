import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'api.dart';

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
  List<Map<String, dynamic>> _msgs = [];
  final List<Map<String, dynamic>> _pending = [];
  Map<String, dynamic>? _replyTo;
  bool _loading = true;
  String? _error;
  Timer? _timer;
  bool _polling = false;
  bool _membuka = false;
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
    _input.dispose();
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

  Future<void> _loadFull() async {
    try {
      final data = await Api.getJson(_base);
      final list = _toList(data['messages'] as List);
      if (!mounted) return;
      setState(() {
        _msgs = list;
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
          if (!widget.grup && m['mine'] == true && id <= dibacaSampai) {
            m['dibaca'] = true;
          }
        }
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

  Future<void> _kirimFile() async {
    final res = await FilePicker.platform.pickFiles(allowMultiple: false);
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    final path = f.path;
    if (path == null) {
      _snack('File tidak bisa dibaca.');
      return;
    }
    if (f.size > 100 * 1024 * 1024) {
      _snack('Ukuran file maksimal 100 MB.');
      return;
    }
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
      'file': {'name': f.name, 'size': _ukuran(f.size), 'url': ''},
      'pending': true,
    };
    setState(() {
      _pending.add(temp);
      _replyTo = null;
      _input.clear();
    });
    try {
      await Api.uploadFile(_sendPath, path, f.name,
          caption: caption, replyTo: reply == null ? null : reply['id'] as int);
      await _poll(tunggu: true);
      if (mounted) setState(() => _pending.remove(temp));
    } catch (e) {
      if (mounted) {
        setState(() {
          _pending.remove(temp);
          _input.text = caption;
          _replyTo = reply;
        });
      }
      _snack('Gagal mengirim file: $e');
    }
  }

  Future<void> _bukaFile(Map file) async {
    final url = (file['url'] ?? '').toString();
    if (url.isEmpty || _membuka) return;
    _membuka = true;
    try {
      _snack('Mengunduh ${file['name']}...');
      final path = await Api.download(url, file['name'].toString());
      final r = await OpenFilex.open(path);
      if (r.type != ResultType.done) {
        _snack('Tidak ada aplikasi untuk membuka file ini.');
      }
    } catch (e) {
      _snack(e.toString());
    } finally {
      _membuka = false;
    }
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

  Widget _bubble(Map<String, dynamic> m) {
    final mine = m['mine'] == true;
    final dihapus = m['dihapus'] == true;
    final balas = m['balas'];
    final file = m['file'];
    final body = (m['body'] ?? '').toString();

    Widget? centang;
    if (m['pending'] == true) {
      centang = const Icon(Icons.access_time, size: 14, color: Colors.black45);
    } else if (mine && !widget.grup) {
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
                if (file is Map)
                  GestureDetector(
                    onTap: () => _bukaFile(file),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0x0F000000),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.insert_drive_file, size: 28),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(file['name'].toString(),
                                  maxLines: 2, overflow: TextOverflow.ellipsis),
                              Text(file['size'].toString(), style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                      ]),
                    ),
                  ),
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
            IconButton.filled(onPressed: _send, icon: const Icon(Icons.send)),
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
import 'package:flutter/material.dart';
import 'api.dart';
import 'util.dart';

class DibagiPage extends StatefulWidget {
  const DibagiPage({super.key});
  @override
  State<DibagiPage> createState() => _DibagiPageState();
}

class _DibagiPageState extends State<DibagiPage> {
  List<Map<String, dynamic>> _files = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  List<Map<String, dynamic>> _toList(List raw) =>
      raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();

  Future<void> _muat({bool diam = false}) async {
    if (!diam) {
      final c = await Api.readCache('dibagi');
      if (c is List && mounted) {
        setState(() {
          _files = _toList(c);
          _loading = false;
        });
      }
    }
    try {
      final d = await Api.getJson('/dibagi') as List;
      Api.writeCache('dibagi', d);
      if (mounted) {
        setState(() {
          _files = _toList(d);
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          if (_files.isEmpty) _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!),
          const SizedBox(height: 12),
          FilledButton(onPressed: _muat, child: const Text('Coba lagi')),
        ]),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: () => _muat(diam: true),
        child: _files.isEmpty
            ? ListView(children: const [
                SizedBox(height: 120),
                Center(child: Text('Belum ada file yang dibagikan kepada Anda.')),
              ])
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: _files.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final f = _files[i];
                  final nama = f['name'].toString();
                  return ListTile(
                    leading: Icon(ikonFile(nama), size: 32),
                    title: Text(nama, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${f['pemilik']} · ${ukuranFile((f['size'] as num).toInt())}'),
                    trailing: StatusUnduh(url: f['url'].toString()),
                    onTap: () => bukaBerkas(context, f['url'].toString(), nama),
                  );
                },
              ),
      );
    }
    return Scaffold(appBar: AppBar(title: const Text('Dibagikan kepada saya')), body: body);
  }
}
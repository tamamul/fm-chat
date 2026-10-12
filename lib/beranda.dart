import 'package:flutter/material.dart';
import 'berkas_page.dart';
import 'chat_list.dart';
import 'dibagi_page.dart';
import 'lokal.dart';

class Beranda extends StatefulWidget {
  final Map<String, dynamic> user;
  final VoidCallback onLogout;
  const Beranda({super.key, required this.user, required this.onLogout});
  @override
  State<Beranda> createState() => _BerandaState();
}

class _BerandaState extends State<Beranda> {
  int _tab = 0;
  final _dibuka = <int>{0}; // tab dimuat saat pertama kali dibuka

  @override
  void initState() {
    super.initState();
    Lokal.muat();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _tab, children: [
        ChatListPage(user: widget.user, onLogout: widget.onLogout),
        _dibuka.contains(1) ? const BerkasPage() : const SizedBox.shrink(),
        _dibuka.contains(2) ? const DibagiPage() : const SizedBox.shrink(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() {
          _tab = i;
          _dibuka.add(i);
        }),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Chat'),
          NavigationDestination(
              icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder), label: 'Berkas'),
          NavigationDestination(
              icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Dibagi'),
        ],
      ),
    );
  }
}
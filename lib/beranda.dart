import 'package:flutter/material.dart';
import 'berkas_page.dart';
import 'chat_list.dart';
import 'dibagi_page.dart';
import 'lokal.dart';
import 'tugas_page.dart';
import 'lencana.dart';

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
  void dispose() {
    Lencana.chat.value = 0;
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _tab, children: [
        ChatListPage(user: widget.user, onLogout: widget.onLogout),
        _dibuka.contains(1) ? BerkasPage(aktif: _tab == 1) : const SizedBox.shrink(),
        _dibuka.contains(2) ? DibagiPage(aktif: _tab == 2) : const SizedBox.shrink(),
        _dibuka.contains(3) ? const TugasPage() : const SizedBox.shrink(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() {
          _tab = i;
          _dibuka.add(i);
        }),
        destinations: [
          NavigationDestination(
            icon: ValueListenableBuilder<int>(
              valueListenable: Lencana.chat,
              builder: (_, n, __) => Badge(
                isLabelVisible: n > 0,
                label: Text(n > 99 ? '99+' : '$n'),
                child: const Icon(Icons.chat_bubble_outline),
              ),
            ),
            selectedIcon: const Icon(Icons.chat_bubble),
            label: 'Chat',
          ),
          NavigationDestination(
              icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder), label: 'Berkas'),
          NavigationDestination(
              icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Dibagi'),
          NavigationDestination(
              icon: Icon(Icons.assignment_outlined), selectedIcon: Icon(Icons.assignment), label: 'Tugas'),
        ],
      ),
    );
  }
}

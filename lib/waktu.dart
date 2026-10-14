const _bulan = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];

String fmtWaktu(DateTime d) {
  final l = d.toLocal();
  String d2(int v) => v.toString().padLeft(2, '0');
  return '${l.day} ${_bulan[l.month - 1]} ${l.year}, ${d2(l.hour)}:${d2(l.minute)}';
}

// Teks status tenggat dan apakah sudah lewat.
(String, bool) infoTenggat(String? iso) {
  final t = iso == null ? null : DateTime.tryParse(iso);
  if (t == null) return ('Tanpa tenggat', false);
  final selisih = t.difference(DateTime.now());
  final lewat = selisih.isNegative;
  final a = selisih.abs();
  final sisa = a.inDays >= 1
      ? '${a.inDays} hari'
      : (a.inHours >= 1 ? '${a.inHours} jam' : '${a.inMinutes < 1 ? 1 : a.inMinutes} menit');
  return (lewat ? 'Lewat $sisa (${fmtWaktu(t)})' : 'Sisa $sisa · ${fmtWaktu(t)}', lewat);
}
import 'app_database.dart';

/// Nama akun yang DITAMPILKAN untuk sebuah catatan.
///
/// Setiap shift, transaksi, dan pengeluaran menyimpan salinan nama saat
/// dibuat (v35), supaya riwayat lama tidak ikut berubah ketika akunnya
/// diganti nama atau dihapus — username bekasnya boleh dipakai karyawan baru
/// (keputusan owner 2026-10-07).
///
/// Catatan buatan HP yang belum diperbarui tidak punya salinan; untuk itu
/// nama diambil dari akunnya lewat [akun] (id → username), seperti dulu.
///
/// Akun yang DIHAPUS (keputusan owner 2026-10-07) ditampilkan dengan
/// akhiran " (dihapus)" di semua riwayat: username bekasnya boleh dipakai
/// karyawan baru, dan tanpa penanda dua orang itu tampil sama persis.
///
/// Satu-satunya tempat aturan ini — semua tampilan memanggil pembantu di
/// sini, bukan menulis `cashierName ?? akun[...]` sendiri-sendiri.
String? _nama(String? salinan, String? id, Map<String, String> akun) {
  final milikAkun = id == null ? null : akun[id];
  final asli = milikAkun == null ? null : usernameSebelumDihapus(milikAkun);
  if (asli == null) return salinan ?? milikAkun;
  return '${salinan ?? asli} (dihapus)';
}

/// Penanda di username akun yang dihapus. Username baru DILARANG memuatnya
/// (lihat `CashierRepository`), jadi tidak mungkin tertukar dengan akun hidup.
const penandaDihapus = '~';

/// Username pengganti saat akun dihapus: `sari` → `sari~1a2b3c4d`.
///
/// Username asli harus dilepas supaya bisa dipakai akun baru (username unik
/// di HP maupun server). Potongan id membuatnya tetap unik walau dua akun
/// bernama sama dihapus bergantian.
String usernameTerhapus(String username, String id) {
  final potongan = id.replaceAll('-', '');
  return '$username$penandaDihapus'
      '${potongan.length > 8 ? potongan.substring(0, 8) : potongan}';
}

/// Kebalikan [usernameTerhapus]; null kalau akunnya tidak dihapus.
String? usernameSebelumDihapus(String username) {
  final i = username.indexOf(penandaDihapus);
  return i < 0 ? null : username.substring(0, i);
}

extension NamaTercatatShift on Shift {
  String? namaKasir(Map<String, String> akun) => _nama(userName, userId, akun);
}

extension NamaTercatatTransaksi on Transaction {
  String? namaKasir(Map<String, String> akun) =>
      _nama(cashierName, cashierUserId, akun);

  String? namaPembatal(Map<String, String> akun) =>
      _nama(cancelledByName, cancelledByUserId, akun);
}

extension NamaTercatatPengeluaran on Expense {
  String? namaPencatat(Map<String, String> akun) =>
      _nama(userName, userId, akun);

  String? namaPembatal(Map<String, String> akun) =>
      _nama(cancelledByName, cancelledByUserId, akun);
}

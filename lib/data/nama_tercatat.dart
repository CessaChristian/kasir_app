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
/// Satu-satunya tempat aturan ini — semua tampilan memanggil pembantu di
/// sini, bukan menulis `cashierName ?? akun[...]` sendiri-sendiri.
String? _nama(String? salinan, String? id, Map<String, String> akun) =>
    salinan ?? (id == null ? null : akun[id]);

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

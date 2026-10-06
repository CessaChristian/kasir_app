part of '../app_database.dart';

// ============================================================
// Models laporan — dipindah dari app_database.dart agar file
// tidak melebihi 1000 baris. Menggunakan `part of` supaya
// tetap bisa akses tipe Drift (Transaction, Expense, dll.)
// tanpa circular import.
// ============================================================

/// Satu shift beserta nama kasir yang menjalankannya.
///
/// Owner melihat riwayat pengeluaran SELURUH kasir, jadi tiap barisnya harus
/// bisa menyebut ini shift siapa — nama itu ada di tabel `users`, bukan di
/// `shifts`, maka digabungkan di sini sekali saja alih-alih dicari ulang
/// per kartu.
class ShiftEntry {
  final Shift shift;
  final String username;

  ShiftEntry({required this.shift, required this.username});
}

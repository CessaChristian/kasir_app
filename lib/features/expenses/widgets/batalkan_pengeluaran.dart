import 'package:flutter/material.dart';

import '../../../data/app_database.dart';
import '../../../shared/widgets/dialog_pembatalan.dart';
import '../repositories/expense_repository.dart';

/// Alasan pembatalan pengeluaran (desain).
const daftarAlasanBatalPengeluaran = [
  'Salah input nominal',
  'Pengeluaran batal',
  alasanLainnya,
];

/// Buka dialog pembatalan untuk [e]. Dipakai halaman Pengeluaran owner dan
/// kasir. Mengembalikan true kalau berhasil dibatalkan.
Future<bool> batalkanPengeluaranLewatDialog(
  BuildContext context,
  ExpenseRepository repo,
  Expense e,
) {
  return tampilkanDialogPembatalan(
    context,
    pertanyaan: 'Kenapa pengeluaran ${e.description} dibatalkan?',
    keteranganPin:
        'Masukkan PIN untuk membatalkan pengeluaran '
        '${e.description}.',
    judulBerhasil: 'Pengeluaran berhasil dibatalkan',
    keteranganBerhasil:
        '${e.description} ditandai dibatalkan dan tidak '
        'dihitung dalam total pengeluaran.',
    daftarAlasan: daftarAlasanBatalPengeluaran,
    perluPin: repo.perluPinOwner,
    kirim: (alasan, pin) =>
        repo.batalkanPengeluaran(e, alasan: alasan, pinOwner: pin),
  );
}

import 'package:flutter/material.dart';

import '../../../data/app_database.dart';
import '../../../shared/widgets/dialog_pembatalan.dart';
import '../../../shared/widgets/transaction_detail_sheet.dart';
import '../../sales/repositories/sales_repository.dart';

/// Alasan pembatalan transaksi (desain).
const daftarAlasanBatalTransaksi = [
  'Salah input pesanan',
  'Pelanggan batal',
  'Transaksi ganda',
  alasanLainnya,
];

/// Buka dialog pembatalan untuk [tx]. Dipakai Riwayat owner dan kasir.
/// Mengembalikan true kalau berhasil dibatalkan.
Future<bool> batalkanTransaksiLewatDialog(
  BuildContext context,
  SalesRepository repo,
  Transaction tx,
) {
  return tampilkanDialogPembatalan(
    context,
    pertanyaan: 'Kenapa transaksi ${tx.invoiceNo} dibatalkan?',
    judulBerhasil: 'Transaksi berhasil dibatalkan',
    keteranganBerhasil:
        '${tx.invoiceNo} ditandai dibatalkan dan tidak '
        'dihitung dalam total penjualan.',
    daftarAlasan: daftarAlasanBatalTransaksi,
    kirim: (alasan) => repo.batalkanTransaksi(tx, alasan: alasan),
  );
}

/// Buka struk [tx], dengan tombol batalkan kalau akun ini berhak. Dipakai
/// Riwayat owner dan Detail Shift.
void bukaDetailTransaksi(
  BuildContext context,
  SalesRepository repo,
  Transaction tx,
) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (lembar) => TransactionDetailSheet(
      transaction: tx,
      repo: repo,
      onBatalkan: repo.bolehDibatalkan(tx)
          ? () async {
              final ok = await batalkanTransaksiLewatDialog(lembar, repo, tx);
              // Desain: setelah dibatalkan, detailnya ikut tertutup.
              if (ok && lembar.mounted) Navigator.pop(lembar);
            }
          : null,
    ),
  );
}

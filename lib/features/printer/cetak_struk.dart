import 'package:flutter/material.dart';

import '../../data/app_database.dart';
import '../../shared/ui/dialog_memuat.dart';
import '../../shared/widgets/app_toast.dart';
import 'data/layanan_printer.dart';
import 'data/logo_cetak.dart';
import 'data/struk_cetak.dart';

/// Cetak struk [tx] ke printer HP ini sambil menahan layar ("Mencetak
/// struk…"), lalu beri tahu hasilnya. True kalau tercetak.
///
/// Dipakai struk sesudah bayar dan Cetak ulang di Riwayat. Gagal cetak
/// tidak mengubah apa pun pada transaksinya.
Future<bool> cetakStrukTransaksi(
  BuildContext context, {
  required Transaction tx,
  required List<TransactionItem> items,
  required String? namaKasir,
  LayananPrinter? layanan,
}) async {
  final printer = layanan ?? LayananPrinter.instance;
  final hasil = await jalankanDenganMemuat(context, () async {
    final baris = susunStruk(
      tx: tx,
      items: items,
      namaKasir: namaKasir,
    );
    return printer.cetak(keEscPos(baris, logo: await logoEscPos()));
  }, pesan: 'Mencetak struk…');
  if (!context.mounted) return hasil == HasilCetak.berhasil;
  final pesan = pesanCetak(hasil);
  if (pesan == null) {
    AppToast.success(context, 'Struk dicetak');
  } else {
    AppToast.error(context, pesan);
  }
  return hasil == HasilCetak.berhasil;
}

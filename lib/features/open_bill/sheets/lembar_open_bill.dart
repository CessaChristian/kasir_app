import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/app_database.dart';
import '../../../data/db.dart';
import '../../../shared/auth/session_manager.dart';
import '../../../shared/ui/dialog_tengah.dart';
import '../../../shared/ui/pegang_lembar.dart';
import '../../../shared/ui/warna_teras.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../utils/currency_formatter.dart';
import '../../products/repositories/product_repository.dart';
import '../../sales/models/keranjang.dart';
import '../../sales/repositories/sales_repository.dart';
import '../../sales/sheets/lembar_keranjang.dart';
import '../models/isi_bill.dart';
import '../repositories/open_bill_repository.dart';

/// Lembar "Tagihan Nota" (desain): daftar open bill di shift berjalan.
/// Bill yang diketuk dimuat ke [keranjang] lalu Keranjang dibuka; ikon
/// tempat sampah menghapusnya.
Future<void> bukaDaftarOpenBill(
  BuildContext context,
  Keranjang keranjang, {
  OpenBillRepository? repo,
  ProductRepository? repoProduk,
  SalesRepository? repoJual,
}) async {
  final r = repo ?? OpenBillRepository(db);
  final dimuat = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: WarnaTeras.kartu,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _LembarOpenBill(
      keranjang: keranjang,
      repo: r,
      repoProduk: repoProduk ?? ProductRepository(db),
    ),
  );
  if (dimuat == true && context.mounted) {
    await bukaKeranjang(context, keranjang, repo: repoJual, repoBill: r);
  }
}

/// "Kam, 1 Okt 2026 · 13:48".
String labelWaktuBill(DateTime t) =>
    '${DateFormat('EEE, d MMM y', 'id_ID').format(t)} · '
    '${DateFormat('HH:mm').format(t)}';

class _LembarOpenBill extends StatefulWidget {
  final Keranjang keranjang;
  final OpenBillRepository repo;
  final ProductRepository repoProduk;

  const _LembarOpenBill({
    required this.keranjang,
    required this.repo,
    required this.repoProduk,
  });

  @override
  State<_LembarOpenBill> createState() => _LembarOpenBillState();
}

class _LembarOpenBillState extends State<_LembarOpenBill> {
  late final _aliranBill = widget.repo.watchTerbuka(
    SessionManager.instance.currentSession?.shiftId,
  );
  late final _aliranProduk = widget.repoProduk.watchProducts();

  Keranjang get _k => widget.keranjang;

  /// Bill yang sedang menunggu jawaban server untuk dihapus — tombol
  /// hapusnya dimatikan supaya tidak terketuk dua kali.
  String? _sedangDihapus;

  void _buka(OpenBill b, BillTermuat isi) {
    final aktif = _k.bill;
    if (aktif?.id == b.id) {
      Navigator.pop(context, true);
      return;
    }
    if (!_k.isEmpty && aktif == null) {
      AppToast.success(
        context,
        'Simpan atau kosongkan keranjang terlebih dahulu',
      );
      return;
    }
    if (isi.baris.isEmpty) {
      AppToast.warning(
        context,
        'Semua produk di bill ini sudah tidak dijual. Hapus bill ini.',
      );
      return;
    }
    _k.muatBill((id: b.id, nama: b.name, isiAwal: b.items), isi.baris);
    if (isi.produkHilang > 0) {
      AppToast.warning(
        context,
        '${isi.produkHilang} produk sudah tidak dijual dan dihapus dari bill',
      );
    } else if (aktif != null) {
      AppToast.success(context, 'Keranjang diganti dengan bill ${b.name}');
    }
    Navigator.pop(context, true);
  }

  Future<void> _hapus(OpenBill b) async {
    final diKeranjang = _k.bill?.id == b.id;
    final ya = await tampilkanDialogTengah(
      context,
      ikon: Icons.delete_rounded,
      judul: 'Hapus bill ${b.name}?',
      catatan: diKeranjang
          ? 'Bill ini sedang ada di keranjang. Pesanan di bill dan keranjang '
                'akan dihapus.'
          : 'Pesanan di bill ini akan dihapus dan tidak bisa dikembalikan.',
      labelAksi: 'Hapus',
    );
    if (!ya || !mounted) return;
    setState(() => _sedangDihapus = b.id);
    try {
      // Server dulu: bill yang sudah dibayar (atau sedang dibayar) HP lain
      // tidak boleh terhapus. Tak terjawab (offline/lambat): hapus di HP
      // saja seperti biasa.
      final keputusan = await widget.repo.hapusDiServer(b.id);
      if (keputusan == KeputusanServer.sudahDibayar) {
        // Jawaban server sudah pasti: sembunyikan sekarang (sebelum toast),
        // rapikan datanya di belakang layar.
        await widget.repo.tandaiTertutup(b.id);
        unawaited(widget.repo.segarkanDariServer());
        // Pesanan itu sudah tidak bisa dibayar lagi — jangan dibiarkan
        // tertinggal di keranjang.
        final diKeranjang = _k.bill?.id == b.id;
        if (diKeranjang) _k.kosongkan();
        if (mounted) {
          AppToast.error(
            context,
            'Bill ${b.name} sudah dibayar di perangkat lain'
            '${diKeranjang ? '. Keranjang dikosongkan.' : ''}',
          );
        }
        return;
      }
      await widget.repo.hapus(b.id);
      if (_k.bill?.id == b.id) _k.kosongkan();
      if (mounted) AppToast.success(context, 'Bill ${b.name} dihapus');
    } catch (e) {
      if (mounted) AppToast.error(context, 'Gagal: $e');
    } finally {
      if (mounted) setState(() => _sedangDihapus = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.82,
      child: StreamBuilder<List<Product>>(
        stream: _aliranProduk,
        builder: (context, snapProduk) => StreamBuilder<List<OpenBill>>(
          stream: _aliranBill,
          builder: (context, snapBill) {
            final produk = snapProduk.data;
            final bill = snapBill.data;
            final siap = produk != null && bill != null;
            final isi = siap
                ? [for (final b in bill) (b, muatBill(b, produk))]
                : const <(OpenBill, BillTermuat)>[];
            final total = isi.fold<int>(0, (s, e) => s + e.$2.total);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 6),
                  child: PegangLembar(onTap: () => Navigator.pop(context)),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: WarnaTeras.garis)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Tagihan Nota',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: WarnaTeras.teks,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${isi.length} bill terbuka · ${formatRp(total)}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: WarnaTeras.teksPudar,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: !siap
                      ? const Center(child: CircularProgressIndicator())
                      : isi.isEmpty
                      ? const _Kosong()
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: isi.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) => _kartu(isi[i].$1, isi[i].$2),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _kartu(OpenBill b, BillTermuat isi) {
    final aktif = _k.bill?.id == b.id;
    return Material(
      color: aktif ? const Color(0xFFFBF6F1) : WarnaTeras.kartu,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: aktif ? WarnaTeras.oranye : WarnaTeras.garis),
      ),
      shadowColor: const Color(0x0F3C230A),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _buka(b, isi),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 4, 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: WarnaTeras.oranyeMuda,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.receipt_long_rounded,
                  size: 23,
                  color: WarnaTeras.oranye,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            b.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: WarnaTeras.teks,
                            ),
                          ),
                        ),
                        if (aktif) ...[
                          const SizedBox(width: 6),
                          // Ikut menyusut di layar sempit, tidak meluap.
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: WarnaTeras.oranyeMuda,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                'Di keranjang',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFC46A12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      labelWaktuBill(b.createdAt),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: WarnaTeras.teksPudar,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${isi.jumlahItem} item',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF5A5048),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Text(
                      formatRp(isi.total),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: WarnaTeras.oranye,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: _sedangDihapus == b.id
                            ? null
                            : () => _hapus(b),
                        tooltip: 'Hapus bill',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 22,
                          color: WarnaTeras.merah,
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 22,
                        color: WarnaTeras.titikPasif,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Kosong extends StatelessWidget {
  const _Kosong();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFFF1ECE7),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              size: 26,
              color: WarnaTeras.teksPudar,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Belum ada open bill',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: WarnaTeras.teks,
            ),
          ),
          const SizedBox(height: 6),
          const SizedBox(
            width: 260,
            child: Text(
              'Simpan pesanan dari keranjang dengan tombol Simpan Bill.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: WarnaTeras.teksPudar,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

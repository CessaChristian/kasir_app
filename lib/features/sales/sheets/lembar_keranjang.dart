import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/app_database.dart' show BillTidakTerbuka;
import '../../../data/db.dart';
import '../../../data/models/sale_line.dart';
import '../../../data/uuid_helper.dart';
import '../../../shared/auth/session_manager.dart';
import '../../../shared/ui/lembar_konfirmasi.dart';
import '../../../shared/ui/pegang_lembar.dart';
import '../../../shared/ui/tombol_lembar.dart';
import '../../../shared/ui/warna_teras.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../utils/currency_formatter.dart';
import '../../open_bill/models/isi_bill.dart';
import '../../open_bill/repositories/open_bill_repository.dart';
import '../../open_bill/widgets/dialog_simpan_bill.dart';
import '../models/keranjang.dart';
import '../models/pesanan.dart';
import '../repositories/sales_repository.dart';
import '../widgets/dialog_struk.dart';
import 'lembar_pembayaran.dart';

/// Buka Keranjang (desain). Sesudah dibayar, struknya ditampilkan.
/// "Simpan Bill" menyimpan isinya sebagai open bill lalu menutup keranjang.
Future<void> bukaKeranjang(
  BuildContext context,
  Keranjang keranjang, {
  SalesRepository? repo,
  OpenBillRepository? repoBill,
}) async {
  final r = repo ?? SalesRepository(db);
  final transaksiId = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: WarnaTeras.kartu,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _LembarKeranjang(
      keranjang: keranjang,
      repo: r,
      repoBill: repoBill ?? OpenBillRepository(db),
    ),
  );
  if (transaksiId == null || !context.mounted) return;
  await tampilkanStrukSesudahBayar(context, transaksiId: transaksiId, repo: r);
}

class _LembarKeranjang extends StatefulWidget {
  final Keranjang keranjang;
  final SalesRepository repo;
  final OpenBillRepository repoBill;

  const _LembarKeranjang({
    required this.keranjang,
    required this.repo,
    required this.repoBill,
  });

  @override
  State<_LembarKeranjang> createState() => _LembarKeranjangState();
}

class _LembarKeranjangState extends State<_LembarKeranjang> {
  var _tipe = TipePesanan.dineIn;
  var _metode = MetodeBayar.tunai;

  Keranjang get _k => widget.keranjang;

  @override
  void initState() {
    super.initState();
    _k.addListener(_segarkan);
  }

  @override
  void dispose() {
    _k.removeListener(_segarkan);
    super.dispose();
  }

  void _segarkan() {
    if (mounted) setState(() {});
  }

  Future<void> _kosongkan() async {
    final ya = await tampilkanLembarKonfirmasi(
      context,
      ikon: Icons.delete_rounded,
      judul: 'Kosongkan keranjang?',
      catatan: 'Semua item akan dihapus dari keranjang.',
      labelAksi: 'Kosongkan',
    );
    if (ya) _k.kosongkan();
  }

  /// True kalau shift berjalan; kalau tidak, kasir diberi tahu.
  bool _adaShift() {
    if (SessionManager.instance.currentSession?.shiftId != null) return true;
    AppToast.warning(
      context,
      'Shift sedang ditutup. Buka shift dulu sebelum membuat transaksi.',
    );
    return false;
  }

  Future<void> _simpanBill() async {
    if (_k.isEmpty || !_adaShift()) return;
    final aktif = _k.bill;
    final baris = List<SaleLine>.of(_k.baris);
    // Diisi kalau bill yang diperbarui ternyata sudah dibayar/dihapus HP
    // lain: dialog ditutup lalu keranjang dikosongkan, seperti saat Bayar.
    String? ditolak;
    // True kalau isi bill di server sudah diubah HP lain sejak dimuat —
    // perubahan HP ini digabungkan ke situ, dan kasir perlu tahu.
    var digabung = false;
    final nama = await tanyaSimpanBill(
      context,
      perbarui: aktif != null,
      jumlahItem: baris.fold(0, (s, b) => s + b.qty),
      total: _k.total,
      namaAwal: aktif?.nama ?? '',
      simpan: (nama) async {
        String? isiServer;
        if (aktif != null) {
          // Sinkron otomatis ditahan selama keranjang berisi — HP ini belum
          // tentu tahu kabar terbaru bill-nya. Tak terjawab: tetap jalan.
          final cek = await widget.repoBill.cekDiServer(aktif.id);
          final keputusan = cek.keputusan;
          if (keputusan == KeputusanServer.sudahDibayar ||
              keputusan == KeputusanServer.sudahDihapus) {
            await widget.repoBill.tandaiTertutup(aktif.id);
            unawaited(widget.repoBill.segarkanDariServer());
            ditolak = keputusan == KeputusanServer.sudahDibayar
                ? 'dibayar'
                : 'dihapus';
            return null;
          }
          isiServer = cek.isi;
        }
        try {
          await widget.repoBill.simpan(
            id: aktif?.id,
            nama: nama,
            baris: baris,
            isiAwal: aktif?.isiAwal,
            isiServer: isiServer,
          );
          digabung =
              isiServer != null && !isiBillSama(isiServer, aktif!.isiAwal);
          return null;
        } on BillTidakTerbuka {
          ditolak = 'dibayar atau dihapus';
          return null;
        } catch (e) {
          return e is StateError ? e.message : 'Gagal: $e';
        }
      },
    );
    if (nama == null || !mounted) return;
    _k.kosongkan();
    if (ditolak != null) {
      AppToast.error(
        context,
        'Bill ${aktif!.nama} sudah $ditolak di perangkat lain. '
        'Keranjang dikosongkan.',
      );
    } else {
      AppToast.success(
        context,
        '${aktif != null ? 'Bill diperbarui' : 'Bill disimpan'} · $nama'
        '${digabung ? ' (digabung dengan perubahan perangkat lain)' : ''}',
      );
    }
    Navigator.pop(context);
  }

  Future<void> _bayar() async {
    if (_k.isEmpty || !_adaShift()) return;
    final sesi = SessionManager.instance.currentSession;
    // Total diambil SEKALI sebagai acuan: yang tampil di pembayaran dan
    // yang disimpan memakai angka yang sama.
    final total = _k.total;
    final baris = List<SaleLine>.of(_k.baris);
    final id = newUuid();
    var billDitolak = false;

    // Bill sudah dibayar/dihapus HP lain: keranjang langsung dikosongkan
    // dan kedua lembar ditutup — tidak ada yang bisa dilakukan kasir
    // dengan pesanan itu selain memulai lagi.
    Never tolakBill(String nama, String apa) {
      billDitolak = true;
      _k.kosongkan();
      AppToast.error(
        context,
        'Bill $nama sudah $apa di perangkat lain. Keranjang dikosongkan.',
      );
      throw const PembayaranDitolak();
    }

    final dibayar = await tampilkanPembayaran(
      context,
      total: total,
      metode: _metode,
      bayar: (uang) async {
        final bill = _k.bill;
        // Klaim di server dulu. Selama keranjang berisi, sinkron otomatis
        // ditahan, jadi HP ini tidak tahu kalau bill-nya sudah dibayar atau
        // dihapus HP lain — dan dua HP yang membayar bersamaan baru bisa
        // dipisahkan oleh server. Tak terjawab (offline/lambat): tetap jalan.
        if (bill != null) {
          final keputusan = await widget.repoBill.klaimDiServer(bill.id, id);
          if (keputusan == KeputusanServer.sudahDibayar ||
              keputusan == KeputusanServer.sudahDihapus) {
            // Jawaban server sudah pasti: sembunyikan sekarang, rapikan
            // datanya (transaksi pelunas) di belakang layar.
            await widget.repoBill.tandaiTertutup(bill.id);
            unawaited(widget.repoBill.segarkanDariServer());
            tolakBill(
              bill.nama,
              keputusan == KeputusanServer.sudahDibayar ? 'dibayar' : 'dihapus',
            );
          }
        }
        try {
          await widget.repo.createSale(
            transactionId: id,
            lines: baris,
            paymentMethod: _metode.kode,
            orderType: _tipe.kode,
            cashReceived: _metode == MetodeBayar.tunai ? uang : null,
            cashierUserId: sesi!.userId,
            shiftId: sesi.shiftId,
            billId: bill?.id,
          );
        } catch (e) {
          // Klaimnya dilepas supaya bill tidak terkunci tanpa transaksi.
          if (bill != null) unawaited(widget.repoBill.lepasKlaim(bill.id, id));
          // HP ini sendiri sudah tahu bill-nya tidak terbuka (mis. offline,
          // tapi sudah menarik kabarnya lebih dulu).
          if (bill != null && e is BillTidakTerbuka) {
            tolakBill(bill.nama, 'dibayar atau dihapus');
          }
          rethrow;
        }
        _k.kosongkan();
      },
    );
    if (!mounted) return;
    if (dibayar) {
      Navigator.pop(context, id);
    } else if (billDitolak) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.9,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 6),
            child: PegangLembar(onTap: () => Navigator.pop(context)),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: WarnaTeras.garis)),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Keranjang',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: WarnaTeras.teks,
                    ),
                  ),
                ),
                if (!_k.isEmpty)
                  InkWell(
                    onTap: _kosongkan,
                    child: const Row(
                      children: [
                        Icon(
                          Icons.delete_rounded,
                          size: 19,
                          color: WarnaTeras.merah,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Kosongkan',
                          style: TextStyle(
                            fontSize: 14,
                            color: WarnaTeras.merah,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (_k.isEmpty)
            const Expanded(child: _Kosong())
          else ...[
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: _k.jumlahBaris,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _baris(i, _k.baris[i]),
              ),
            ),
            _bawah(),
          ],
        ],
      ),
    );
  }

  Widget _baris(int i, SaleLine l) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: WarnaTeras.kartu,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WarnaTeras.garis),
        boxShadow: const [
          BoxShadow(
            color: Color(0x143C230A),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.productName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: WarnaTeras.teks,
                  ),
                ),
                if (l.notes != null && l.notes!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.tune_rounded,
                          size: 15,
                          color: WarnaTeras.merah,
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            l.notes!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: WarnaTeras.merah,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  formatRp(l.priceAtSale),
                  style: const TextStyle(
                    fontSize: 13,
                    color: WarnaTeras.teksSamar,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatRp(l.subtotal),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: WarnaTeras.oranye,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2F0EE),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        _tombolJumlah(
                          Icons.remove_rounded,
                          const Color(0xFF5A5048),
                          'Kurangi ${l.productName}',
                          () => _k.kurangiSatu(i),
                        ),
                        SizedBox(
                          width: 24,
                          child: Text(
                            '${l.qty}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        _tombolJumlah(
                          Icons.add_rounded,
                          WarnaTeras.oranye,
                          'Tambah ${l.productName}',
                          () => _k.tambahSatu(i),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    onPressed: () => _k.hapus(i),
                    tooltip: 'Hapus ${l.productName}',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(
                      Icons.delete_rounded,
                      size: 22,
                      color: WarnaTeras.merah,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tombolJumlah(
    IconData ikon,
    Color warna,
    String tooltip,
    VoidCallback onTap,
  ) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(ikon, size: 19, color: warna),
        ),
      ),
    );
  }

  Widget _bawah() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 24),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: WarnaTeras.garis)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _pilihan<TipePesanan>(
              'Tipe Pesanan',
              TipePesanan.values,
              _tipe,
              (t) => (t.label, t.ikon),
              (t) => setState(() => _tipe = t),
            ),
            const SizedBox(height: 10),
            _pilihan<MetodeBayar>(
              'Pembayaran',
              MetodeBayar.values,
              _metode,
              (m) => (m.label, m.ikon),
              (m) => setState(() => _metode = m),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: WarnaTeras.latar,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Total Belanja',
                      style: TextStyle(fontSize: 14, color: WarnaTeras.teks),
                    ),
                  ),
                  Text(
                    formatRp(_k.total),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: WarnaTeras.oranye,
                    ),
                  ),
                ],
              ),
            ),
            if (_k.bill case final bill?)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 2),
                child: Row(
                  children: [
                    const Icon(
                      Icons.receipt_long_rounded,
                      size: 18,
                      color: WarnaTeras.oranye,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Open bill: ${bill.nama}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: WarnaTeras.teksPudar,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                SizedBox(
                  height: 46,
                  child: OutlinedButton.icon(
                    onPressed: _simpanBill,
                    icon: const Icon(Icons.bookmark_add_outlined, size: 20),
                    label: Text(
                      _k.bill == null ? 'Simpan Bill' : 'Perbarui Bill',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: WarnaTeras.oranye,
                      side: const BorderSide(color: WarnaTeras.oranye),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      textStyle: const TextStyle(fontSize: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TombolLembar(
                    label: 'Bayar ${formatRp(_k.total)}',
                    ikon: Icons.add_shopping_cart_rounded,
                    latar: WarnaTeras.oranye,
                    warna: Colors.white,
                    tinggi: 46,
                    sudut: 8,
                    ukuranTeks: 15,
                    onPressed: _bayar,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pilihan<T>(
    String judul,
    List<T> semua,
    T terpilih,
    (String, IconData) Function(T) isi,
    ValueChanged<T> onPilih,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 92,
          child: Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              judul,
              style: const TextStyle(fontSize: 13, color: WarnaTeras.teks),
            ),
          ),
        ),
        for (final t in semua) ...[
          const SizedBox(width: 6),
          Expanded(child: _opsi(isi(t), t == terpilih, () => onPilih(t))),
        ],
      ],
    );
  }

  Widget _opsi((String, IconData) isi, bool dipilih, VoidCallback onTap) {
    final (label, ikon) = isi;
    return Material(
      color: dipilih ? WarnaTeras.oranye : WarnaTeras.kartu,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(
          color: dipilih ? WarnaTeras.oranye : const Color(0xFFDDD6CF),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: SizedBox(
          height: 38,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                ikon,
                size: 18,
                color: dipilih ? Colors.white : WarnaTeras.teksSedang,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: dipilih ? Colors.white : WarnaTeras.teksSedang,
                  ),
                ),
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
    return const Padding(
      padding: EdgeInsets.only(bottom: 60),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 38,
            backgroundColor: Color(0xFFA3A3A3),
            child: Icon(
              Icons.shopping_cart_rounded,
              size: 40,
              color: Colors.white,
            ),
          ),
          SizedBox(height: 16),
          Text(
            'Keranjang Kosong',
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              color: WarnaTeras.teks,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Tambahkan produk dari halaman kasir',
            style: TextStyle(fontSize: 14, color: WarnaTeras.teksSedang),
          ),
        ],
      ),
    );
  }
}

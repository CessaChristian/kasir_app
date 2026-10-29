import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/app_database.dart';
import '../../../data/models/sale_line.dart';
import '../../../data/supabase/supabase_service.dart';
import '../../../data/sync/sync_engine.dart';
import '../../../shared/auth/session_manager.dart';
import '../models/isi_bill.dart';

/// Panjang maksimal nama bill (desain).
const panjangMaksNamaBill = 40;

/// Galat nama bill, atau null kalau boleh dipakai. Nama yang sama dengan
/// bill terbuka lain di [terbuka] ditolak tanpa membedakan huruf besar/kecil;
/// bill [kecualiId] (yang sedang diperbarui) tidak dihitung.
String? periksaNamaBill(
  String nama,
  Iterable<OpenBill> terbuka, {
  String? kecualiId,
}) {
  final rapi = nama.trim().toLowerCase();
  if (rapi.isEmpty) return 'Nama bill wajib diisi';
  if (rapi.length > panjangMaksNamaBill) {
    return 'Nama bill maksimal $panjangMaksNamaBill huruf';
  }
  final bentrok = terbuka.any(
    (b) => b.id != kecualiId && b.name.trim().toLowerCase() == rapi,
  );
  return bentrok ? 'Nama sudah dipakai bill lain' : null;
}

/// Jawaban server saat bill hendak dibayar atau dihapus
/// (`supabase/open_bill_kunci.sql`).
enum KeputusanServer {
  /// Boleh lanjut: klaim/hapus berhasil, atau bill belum pernah sampai ke
  /// server (dibuat offline — HP lain belum mungkin tahu).
  boleh,
  sudahDibayar,
  sudahDihapus,

  /// Offline, galat, fungsi belum dipasang di server, atau lebih dari
  /// [OpenBillRepository.batasTungguServer]. Pekerjaan tetap jalan: kasir
  /// tidak boleh macet menunggu sinyal (risiko offline yang sudah diterima).
  takTerjawab,
}

/// Jawaban fungsi server → keputusan. Jawaban asing (mis. server memakai
/// versi fungsi lain) dianggap tak terjawab, bukan ditolak.
KeputusanServer keputusanDariJawaban(Object? jawaban) => switch (jawaban) {
  'ok' || 'belum_ada' => KeputusanServer.boleh,
  'dibayar' => KeputusanServer.sudahDibayar,
  'dihapus' => KeputusanServer.sudahDihapus,
  _ => KeputusanServer.takTerjawab,
};

/// Baris `open_bills` di server → keputusan memperbarui bill. Tidak ada
/// baris = bill belum pernah terkirim (dibuat offline), jadi boleh. Bill
/// yang sedang diklaim pembayaran (`klaim_tx`) dihitung sudah dibayar.
KeputusanServer keputusanDariBaris(Map<String, dynamic>? baris) {
  if (baris == null) return KeputusanServer.boleh;
  if (baris['deleted_at'] != null) return KeputusanServer.sudahDihapus;
  if (baris['transaction_id'] != null || baris['klaim_tx'] != null) {
    return KeputusanServer.sudahDibayar;
  }
  return KeputusanServer.boleh;
}

/// Jawaban [OpenBillRepository.cekDiServer]: boleh/tidaknya, dan isi bill
/// di server (JSON seperti `open_bills.items`) kalau terbaca.
typedef CekBill = ({KeputusanServer keputusan, String? isi});

/// Hasil [OpenBillRepository.perbarui].
enum HasilPerbarui {
  tersimpan,

  /// Tersimpan, digabung dengan perubahan HP lain di server.
  digabung,

  /// Sudah dibayar / dihapus HP lain — tidak tersimpan.
  sudahDibayar,
  sudahDihapus,

  /// HP ini sudah tahu bill-nya tidak terbuka, tapi tidak tahu sebabnya.
  tidakTerbuka,
}

/// "dibayar" / "dihapus" / "dibayar atau dihapus" untuk pesan penolakan.
String? kataPenolakan(HasilPerbarui h) => switch (h) {
  HasilPerbarui.sudahDibayar => 'dibayar',
  HasilPerbarui.sudahDihapus => 'dihapus',
  HasilPerbarui.tidakTerbuka => 'dibayar atau dihapus',
  _ => null,
};

/// Satu-satunya pintu data Open Bill. Bill milik shift yang sedang berjalan;
/// membayarnya lewat `SalesRepository.createSale(billId: ...)`.
class OpenBillRepository {
  final AppDatabase _db;

  OpenBillRepository(this._db);

  SimpleSelectStatement<$OpenBillsTable, OpenBill> _kueriTerbuka(
    String shiftId,
  ) => _db.select(_db.openBills)
    ..where(
      (b) =>
          b.shiftId.equals(shiftId) &
          b.transactionId.isNull() &
          b.deletedAt.isNull(),
    )
    ..orderBy([(b) => OrderingTerm.desc(b.createdAt)]);

  /// Bill terbuka di [shiftId], terbaru dulu. Tanpa shift = kosong.
  Stream<List<OpenBill>> watchTerbuka(String? shiftId) =>
      shiftId == null ? Stream.value(const []) : _kueriTerbuka(shiftId).watch();

  Future<List<OpenBill>> _terbuka(String shiftId) =>
      _kueriTerbuka(shiftId).get();

  /// Jumlah bill terbuka di [shiftId] — penghalang tutup shift.
  Future<int> jumlahTerbuka(String shiftId) async =>
      (await _terbuka(shiftId)).length;

  /// Tarik bill terbaru dari server, sebisanya, supaya bill dari HP lain di
  /// shift yang sama ikut terhitung. Dipakai sebelum tutup shift, dan
  /// sesudah server menolak bayar/hapus supaya bill itu hilang dari daftar.
  /// Gagal atau lebih dari 4 detik diabaikan: data lokal tetap dipakai.
  Future<void> segarkanDariServer() async {
    try {
      if (!SupabaseService.instance.online) return;
      // Semua tabel, bukan open_bills saja — lihat SyncEngine.tarikSemua.
      await SyncEngine(
        _db,
      ).tarikSemua().timeout(const Duration(seconds: 4));
    } catch (_) {
      // Sengaja dibisukan — lihat catatan di atas.
    }
  }

  /// Lama menunggu jawaban server sebelum bayar/hapus jalan tanpa kunci
  /// (keputusan owner 2026-10-15).
  static const batasTungguServer = Duration(seconds: 5);

  /// Tandai bill [billId] di server sebagai sedang dibayar [transaksiId],
  /// SEBELUM transaksinya disimpan. Server mengerjakan "cek lalu tandai"
  /// dalam satu langkah, jadi dari dua HP yang membayar bersamaan hanya satu
  /// yang mendapat [KeputusanServer.boleh] — selambat apa pun internetnya.
  Future<KeputusanServer> klaimDiServer(String billId, String transaksiId) =>
      _tanyaServer('klaim_bill', {'p_bill': billId, 'p_tx': transaksiId});

  /// Lepas klaim [transaksiId] kalau penyimpanan di HP gagal sesudah klaim
  /// berhasil, supaya bill tidak terkunci tanpa transaksi. Sebisanya.
  Future<void> lepasKlaim(String billId, String transaksiId) async {
    try {
      final k = SupabaseService.instance;
      if (!k.online) return;
      await k.client!
          .rpc(
            'lepas_klaim_bill',
            params: {'p_bill': billId, 'p_tx': transaksiId},
          )
          .timeout(batasTungguServer);
    } catch (_) {
      // Sengaja dibisukan: paling buruk bill tetap terkunci di server dan
      // tidak bisa dibayar HP lain — tidak ada uang yang tercatat salah.
    }
  }

  /// Hapus bill [billId] di server, hanya kalau masih terbuka dan belum
  /// diklaim pembayaran. [KeputusanServer.sudahDihapus] berarti memang sudah
  /// terhapus sebelumnya.
  Future<KeputusanServer> hapusDiServer(String billId) =>
      _tanyaServer('hapus_bill', {'p_bill': billId});

  /// Tanya server apakah bill [billId] masih terbuka, sebelum diperbarui,
  /// sekaligus ambil isinya — mungkin sudah ditambah HP lain, dan perubahan
  /// HP ini digabungkan ke situ (lihat [simpan]). Hanya membaca: penjaga
  /// status di server (`jaga_status_bill`) yang menolak kiriman ke bill yang
  /// sudah lunas/terhapus; ini supaya kasir langsung tahu.
  Future<CekBill> cekDiServer(String billId) async {
    try {
      final k = SupabaseService.instance;
      if (!k.online) return (keputusan: KeputusanServer.takTerjawab, isi: null);
      final baris = await k.client!
          .from('open_bills')
          .select('transaction_id, deleted_at, klaim_tx, items')
          .eq('id', billId)
          .maybeSingle()
          .timeout(batasTungguServer);
      final items = baris?['items'];
      return (
        keputusan: keputusanDariBaris(baris),
        isi: items == null ? null : jsonEncode(items),
      );
    } catch (_) {
      return (keputusan: KeputusanServer.takTerjawab, isi: null);
    }
  }

  /// Isi keranjang [milikku] — bill yang dimuat dengan isi [isiAwal] lalu
  /// mungkin diubah kasir — digabungkan ke [isiServer], isi bill yang sudah
  /// diubah HP lain (lihat [gabungIsiBill]). Hasilnya siap menggantikan isi
  /// keranjang, dengan nama dan harga produk terbaru.
  Future<BillTermuat> gabungDenganServer({
    required String isiAwal,
    required List<SaleLine> milikku,
    required String isiServer,
  }) async {
    final produk = await (_db.select(
      _db.products,
    )..where((p) => p.deletedAt.isNull())).get();
    final isi = kodekanBarisBill(
      gabungIsiBill(
        awal: bacaIsiBill(isiAwal),
        milikku: bacaIsiBill(kodekanIsiBill(milikku)),
        terkini: bacaIsiBill(isiServer),
      ),
    );
    return muatIsiBill(isi, produk);
  }

  Future<KeputusanServer> _tanyaServer(
    String fungsi,
    Map<String, dynamic> param,
  ) async {
    try {
      final k = SupabaseService.instance;
      if (!k.online) return KeputusanServer.takTerjawab;
      final jawaban = await k.client!
          .rpc(fungsi, params: param)
          .timeout(batasTungguServer);
      return keputusanDariJawaban(jawaban);
    } catch (_) {
      return KeputusanServer.takTerjawab;
    }
  }

  /// Perbarui bill [id] yang dimuat ke keranjang dengan isi [isiAwal].
  ///
  /// Sinkron otomatis ditahan selama keranjang berisi — HP ini belum tentu
  /// tahu kabar terbaru bill-nya, jadi server ditanya dulu. Tak terjawab:
  /// tetap disimpan. Dipakai "Perbarui Bill" di keranjang dan pindah bill
  /// di daftar Open Bill.
  Future<HasilPerbarui> perbarui({
    required String id,
    required String nama,
    required String isiAwal,
    required List<SaleLine> baris,
  }) async {
    final cek = await cekDiServer(id);
    if (cek.keputusan == KeputusanServer.sudahDibayar ||
        cek.keputusan == KeputusanServer.sudahDihapus) {
      await tandaiTertutup(id);
      unawaited(segarkanDariServer());
      return cek.keputusan == KeputusanServer.sudahDibayar
          ? HasilPerbarui.sudahDibayar
          : HasilPerbarui.sudahDihapus;
    }
    try {
      await simpan(
        id: id,
        nama: nama,
        baris: baris,
        isiAwal: isiAwal,
        isiServer: cek.isi,
      );
    } on BillTidakTerbuka {
      return HasilPerbarui.tidakTerbuka;
    }
    final isi = cek.isi;
    return isi != null && !isiBillSama(isi, isiAwal)
        ? HasilPerbarui.digabung
        : HasilPerbarui.tersimpan;
  }

  /// Simpan isi keranjang sebagai bill baru, atau perbarui bill [id].
  /// Mengembalikan id bill-nya.
  ///
  /// Memperbarui dengan [isiAwal] (isi bill saat dimuat ke keranjang) tidak
  /// menimpa, tapi MENGGABUNGKAN: yang diubah di HP ini ditempelkan ke isi
  /// terbaru — [isiServer] kalau ada, kalau tidak isi bill di HP ini — jadi
  /// tambahan dari HP lain tidak hilang (keputusan owner 2026-10-16).
  Future<String> simpan({
    String? id,
    required String nama,
    required List<SaleLine> baris,
    String? isiAwal,
    String? isiServer,
  }) async {
    final sm = SessionManager.instance;
    sm.requirePermission('create_transaction');
    final sesi = sm.currentSession!;
    final shiftId = sesi.shiftId;
    if (shiftId == null) {
      throw StateError('Buka shift dulu untuk mulai berjualan');
    }
    if (baris.isEmpty) throw StateError('Keranjang masih kosong');
    final rapi = nama.trim();
    final sekarang = DateTime.now();

    return _db.transaction(() async {
      final galat = periksaNamaBill(
        rapi,
        await _terbuka(shiftId),
        kecualiId: id,
      );
      if (galat != null) throw StateError(galat);

      if (id == null) {
        final baru = await _db
            .into(_db.openBills)
            .insertReturning(
              OpenBillsCompanion.insert(
                name: rapi,
                shiftId: shiftId,
                userId: sesi.userId,
                items: kodekanIsiBill(baris),
                createdAt: Value(sekarang),
                updatedAt: Value(sekarang),
              ),
            );
        return baru.id;
      }

      var isi = kodekanIsiBill(baris);
      if (isiAwal != null) {
        final lokal = await (_db.select(
          _db.openBills,
        )..where((b) => b.id.equals(id))).getSingleOrNull();
        final terkini = isiServer ?? lokal?.items;
        if (terkini != null) {
          isi = kodekanBarisBill(
            gabungIsiBill(
              awal: bacaIsiBill(isiAwal),
              milikku: bacaIsiBill(isi),
              terkini: bacaIsiBill(terkini),
            ),
          );
        }
      }
      final diubah =
          await (_db.update(_db.openBills)..where(
                (b) =>
                    b.id.equals(id) &
                    b.transactionId.isNull() &
                    b.deletedAt.isNull(),
              ))
              .write(
                OpenBillsCompanion(
                  name: Value(rapi),
                  items: Value(isi),
                  updatedAt: Value(sekarang),
                  syncStatus: const Value('pending'),
                ),
              );
      if (diubah == 0) {
        throw BillTidakTerbuka('Bill ini sudah dibayar atau dihapus.');
      }
      return id;
    });
  }

  /// Server sudah memastikan bill [id] tidak terbuka lagi (dibayar atau
  /// dihapus HP lain): sembunyikan SEKARANG, tanpa menunggu tarikan data
  /// yang bisa beberapa detik — kalau tidak, toast "sudah dibayar" muncul
  /// sementara bill-nya masih terlihat.
  ///
  /// Ditandai lewat `deleted_at` karena transaksi pelunasnya belum ada di HP
  /// ini (foreign key). `updated_at` dan `sync_status` SENGAJA tidak diubah:
  /// tanda ini tidak ikut terkirim, dan tarikan berikutnya — versi server
  /// selalu lebih baru — menimpanya dengan status sebenarnya.
  Future<void> tandaiTertutup(String id) =>
      (_db.update(_db.openBills)..where(
            (b) =>
                b.id.equals(id) &
                b.transactionId.isNull() &
                b.deletedAt.isNull(),
          ))
          .write(OpenBillsCompanion(deletedAt: Value(DateTime.now())));

  /// Hapus bill [id] (desain: cukup konfirmasi, tanpa alasan).
  Future<void> hapus(String id) async {
    SessionManager.instance.requirePermission('create_transaction');
    final sekarang = DateTime.now();
    await (_db.update(_db.openBills)..where(
          (b) =>
              b.id.equals(id) & b.transactionId.isNull() & b.deletedAt.isNull(),
        ))
        .write(
          OpenBillsCompanion(
            deletedAt: Value(sekarang),
            updatedAt: Value(sekarang),
            syncStatus: const Value('pending'),
          ),
        );
  }
}

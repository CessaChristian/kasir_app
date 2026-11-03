import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/app_database.dart';
import '../../../data/models/sale_line.dart';
import '../../../data/perangkat/perangkat_repository.dart';
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

  /// Sedang dibayar HP lain (klaimnya masih berlaku): belum tentu lunas.
  /// Bill-nya TIDAK disembunyikan — kalau pembayaran itu gagal atau HP-nya
  /// mati, klaimnya hangus dan bill ini terbuka lagi (review R5).
  sedangDibayar,

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
/// yang sedang diklaim pembayaran (`klaim_tx`) sedang dibayar — kecuali
/// klaimnya sudah lewat [batasKlaim] (`klaim_pada`): HP yang mengklaim
/// dianggap mati (supabase/open_bill_aman.sql, QA kedua S8).
KeputusanServer keputusanDariBaris(
  Map<String, dynamic>? baris, {
  DateTime? sekarang,
}) {
  if (baris == null) return KeputusanServer.boleh;
  if (baris['deleted_at'] != null) return KeputusanServer.sudahDihapus;
  if (baris['transaction_id'] != null) return KeputusanServer.sudahDibayar;
  if (sisaKlaimDariBaris(baris, sekarang: sekarang) != null) {
    return KeputusanServer.sedangDibayar;
  }
  return KeputusanServer.boleh;
}

/// Sisa waktu klaim pembayaran yang masih berlaku di [baris], atau null
/// kalau tidak diklaim / klaimnya sudah lewat [batasKlaim]. Klaim tanpa
/// `klaim_pada` (dipasang sebelum open_bill_aman.sql) dianggap sudah hangus
/// — dulu berlaku selamanya dan bill-nya terkunci (review R7,
/// supabase/klaim_tanpa_waktu.sql).
Duration? sisaKlaimDariBaris(Map<String, dynamic> baris, {DateTime? sekarang}) {
  if (baris['klaim_tx'] == null) return null;
  final pada = DateTime.tryParse('${baris['klaim_pada']}');
  if (pada == null) return null;
  final sisa = batasKlaim - (sekarang ?? DateTime.now()).difference(pada);
  return sisa > Duration.zero ? sisa : null;
}

/// Klaim pembayaran bill kedaluwarsa — HARUS sama dengan `klaim_berlaku`
/// di supabase/klaim_lima_menit.sql (keputusan owner 2026-11-01).
const batasKlaim = Duration(minutes: 5);

/// Jawaban server tentang satu bill: boleh/tidaknya, isi bill di server
/// (JSON seperti `open_bills.items`) kalau terbaca, dan sisa waktu klaim
/// kalau [KeputusanServer.sedangDibayar].
typedef CekBill = ({
  KeputusanServer keputusan,
  String? isi,
  Duration? sisaKlaim,
});

/// Jawaban `status_bill` (supabase/status_bill.sql) → keputusan, isi, dan
/// sisa klaim. Berlaku-tidaknya klaim diputuskan SERVER dengan jamnya
/// sendiri, dan sisa waktunya dihitung dengan jam server — HP yang jamnya
/// kecepatan dulu menganggap klaim yang masih berlaku sudah hangus, lalu
/// perubahannya dibuang server diam-diam (review C5/R6).
CekBill cekDariStatus(Map<String, dynamic> jawaban) {
  final baris = (jawaban['baris'] as Map?)?.cast<String, dynamic>();
  final items = baris?['items'];
  final isi = items == null ? null : jsonEncode(items);
  final jamServer = DateTime.tryParse('${jawaban['sekarang']}');
  final keputusan = keputusanDariBaris(baris, sekarang: jamServer);
  if (keputusan != KeputusanServer.boleh &&
      keputusan != KeputusanServer.sedangDibayar) {
    return (keputusan: keputusan, isi: isi, sisaKlaim: null);
  }
  if (jawaban['klaim_berlaku'] != true) {
    return (keputusan: KeputusanServer.boleh, isi: isi, sisaKlaim: null);
  }
  return (
    keputusan: KeputusanServer.sedangDibayar,
    isi: isi,
    // Server bilang masih berlaku: paling sedikit "±1 menit lagi".
    sisaKlaim:
        sisaKlaimDariBaris(baris!, sekarang: jamServer) ??
        const Duration(minutes: 1),
  );
}

/// Pesan untuk bill yang sedang dibayar HP lain. [sisa] hanya perkiraan.
String pesanSedangDibayar(String nama, Duration? sisa) {
  final awal = 'Bill $nama lagi dibayar di perangkat lain.';
  if (sisa == null) return '$awal Tunggu sebentar lalu coba lagi.';
  final menit = (sisa.inSeconds / 60).ceil().clamp(1, batasKlaim.inMinutes);
  return '$awal Kalau perangkat itu bermasalah, bill ini bisa dipakai lagi '
      '±$menit menit lagi.';
}

/// Jawaban fungsi server ([keputusan]) digabung dengan pembacaan ulang
/// barisnya ([cek]) — lihat `OpenBillRepository._tanyaServer`.
CekBill keputusanSesudahCek(KeputusanServer keputusan, CekBill? cek) {
  if (keputusan == KeputusanServer.sudahDibayar &&
      (cek?.keputusan == KeputusanServer.sedangDibayar ||
          cek?.keputusan == KeputusanServer.boleh)) {
    return (
      keputusan: KeputusanServer.sedangDibayar,
      isi: null,
      sisaKlaim: cek!.sisaKlaim,
    );
  }
  return (keputusan: keputusan, isi: null, sisaKlaim: null);
}

/// Hasil [OpenBillRepository.perbarui].
enum HasilPerbarui {
  tersimpan,

  /// Sedang dibayar HP lain — tidak tersimpan, tapi isi keranjang tetap.
  sedangDibayar,

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
      await SyncEngine(_db).tarikSemua().timeout(const Duration(seconds: 4));
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
  Future<CekBill> klaimDiServer(String billId, String transaksiId) =>
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
  Future<CekBill> hapusDiServer(String billId) =>
      _tanyaServer('hapus_bill', {'p_bill': billId});

  /// Tanya server apakah bill [billId] masih terbuka, sebelum diperbarui,
  /// sekaligus ambil isinya — mungkin sudah ditambah HP lain, dan perubahan
  /// HP ini digabungkan ke situ (lihat [simpan]). Hanya membaca: penjaga
  /// status di server (`jaga_status_bill`) yang menolak kiriman ke bill yang
  /// sudah lunas/terhapus; ini supaya kasir langsung tahu.
  ///
  /// Ditanyakan ke `status_bill` supaya klaim dinilai dengan jam server
  /// (review C5/R6). Server yang belum memasang fungsi itu: barisnya dibaca
  /// langsung dan klaimnya dinilai dengan jam HP, seperti dulu.
  Future<CekBill> cekDiServer(String billId) async {
    try {
      final k = SupabaseService.instance;
      if (!k.online) return _takTerjawab;
      final jawaban = await k.client!
          .rpc('status_bill', params: {'p_bill': billId})
          .timeout(batasTungguServer);
      if (jawaban is! Map) return _takTerjawab;
      return cekDariStatus(jawaban.cast<String, dynamic>());
    } catch (e) {
      if (!PerangkatRepository.belumDisiapkan(e)) return _takTerjawab;
    }
    return _cekDariBarisLangsung(billId);
  }

  Future<CekBill> _cekDariBarisLangsung(String billId) async {
    try {
      final k = SupabaseService.instance;
      if (!k.online) return _takTerjawab;
      final baris = await k.client!
          .from('open_bills')
          // Semua kolom: `klaim_pada` belum ada di server sebelum
          // open_bill_aman.sql, dan memintanya by name akan gagal.
          .select()
          .eq('id', billId)
          .maybeSingle()
          .timeout(batasTungguServer);
      final items = baris?['items'];
      return (
        keputusan: keputusanDariBaris(baris),
        isi: items == null ? null : jsonEncode(items),
        sisaKlaim: baris == null ? null : sisaKlaimDariBaris(baris),
      );
    } catch (_) {
      return _takTerjawab;
    }
  }

  static const CekBill _takTerjawab = (
    keputusan: KeputusanServer.takTerjawab,
    isi: null,
    sisaKlaim: null,
  );

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

  /// Panggil fungsi server [fungsi]. Jawaban "dibayar" juga berarti
  /// SEDANG dibayar HP lain, jadi barisnya dibaca sekali lagi untuk
  /// membedakan keduanya — bill yang baru diklaim tidak boleh disembunyikan
  /// seolah lunas (review R5). Barisnya belum lunas tapi menurut jam HP ini
  /// klaimnya sudah hangus (jam HP kecepatan): server yang benar, jadi
  /// tetap "sedang dibayar". Pembacaan itu gagal: tetap "dibayar".
  Future<CekBill> _tanyaServer(
    String fungsi,
    Map<String, dynamic> param,
  ) async {
    final KeputusanServer keputusan;
    try {
      final k = SupabaseService.instance;
      if (!k.online) return _takTerjawab;
      final jawaban = await k.client!
          .rpc(fungsi, params: param)
          .timeout(batasTungguServer);
      keputusan = keputusanDariJawaban(jawaban);
    } catch (_) {
      return _takTerjawab;
    }
    return keputusanSesudahCek(
      keputusan,
      keputusan == KeputusanServer.sudahDibayar
          ? await cekDiServer(param['p_bill'] as String)
          : null,
    );
  }

  /// Perbarui bill [id] yang dimuat ke keranjang dengan isi [isiAwal].
  ///
  /// Sinkron otomatis ditahan selama keranjang berisi — HP ini belum tentu
  /// tahu kabar terbaru bill-nya, jadi server ditanya dulu. Tak terjawab:
  /// tetap disimpan. Dipakai "Perbarui Bill" di keranjang dan pindah bill
  /// di daftar Open Bill.
  ///
  /// [sisaKlaim] diisi kalau bill-nya [HasilPerbarui.sedangDibayar]: bill
  /// itu TIDAK ditandai tertutup, karena pembayarannya bisa gagal dan
  /// klaimnya lalu dilepas tanpa kabar apa pun ke HP ini (review R5).
  Future<({HasilPerbarui hasil, Duration? sisaKlaim})> perbarui({
    required String id,
    required String nama,
    required String isiAwal,
    required List<SaleLine> baris,
  }) async {
    final cek = await cekDiServer(id);
    if (cek.keputusan == KeputusanServer.sedangDibayar) {
      return (hasil: HasilPerbarui.sedangDibayar, sisaKlaim: cek.sisaKlaim);
    }
    if (cek.keputusan == KeputusanServer.sudahDibayar ||
        cek.keputusan == KeputusanServer.sudahDihapus) {
      await tandaiTertutup(id);
      unawaited(segarkanDariServer());
      return (
        hasil: cek.keputusan == KeputusanServer.sudahDibayar
            ? HasilPerbarui.sudahDibayar
            : HasilPerbarui.sudahDihapus,
        sisaKlaim: null,
      );
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
      return (hasil: HasilPerbarui.tidakTerbuka, sisaKlaim: null);
    }
    final isi = cek.isi;
    return (
      hasil: isi != null && !isiBillSama(isi, isiAwal)
          ? HasilPerbarui.digabung
          : HasilPerbarui.tersimpan,
      sisaKlaim: null,
    );
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

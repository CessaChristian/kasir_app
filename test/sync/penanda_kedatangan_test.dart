import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/data/sync/sync_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// Mengunci kebocoran sinkron yang paling mahal di project ini.
///
/// ── APA YANG BOCOR ──
///
/// Perangkat menarik dengan bertanya "beri aku yang lebih baru dari
/// penandaku", lalu memajukan penandanya ke nilai tertinggi yang diterima.
/// Selama penandanya `updated_at` — JAM PERANGKAT saat baris diubah — baris
/// bisa tiba di server SESUDAH penanda melewatinya, dan sejak itu tidak akan
/// pernah tertarik lagi.
///
///   09:00  HP kasir offline, tetap melayani
///   09:00–12:00  transaksinya tercatat dengan cap waktu jam-jam itu
///   11:30  HP owner menerima baris bercap 11:30, penandanya maju ke sana
///   12:05  HP kasir online, mendorong transaksinya (cap TETAP 09:00–12:00)
///   12:06  HP owner menarik "yang > 11:30"  →  transaksi itu TIDAK IKUT
///
/// Gagalnya diam-diam: sinkron melapor berhasil, tidak ada galat, dan data
/// aman di server — hanya tidak pernah sampai. Ketahuannya saat pemilik
/// membandingkan uang di laci dengan laporan, dan saat itu tidak ada cara
/// memulihkannya selain memasang ulang aplikasi.
///
/// Perbaikannya memisahkan dua tugas yang dulu ditumpuk di satu kolom:
/// `updated_at` tetap menentukan siapa menang saat bentrok, `server_urut`
/// — diisi trigger di server — menentukan sampai mana kita sudah menarik.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SyncEngine mesin;

  /// Server tiruan: menyimpan baris beserta urutan kedatangannya, dan
  /// menjawab persis seperti PostgREST menjawab kueri yang dibangun engine.
  late List<Map<String, dynamic>> server;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    server = [];

    mesin = SyncEngine(db);
    mesin.penarikUntukTest = (tabel, kolom, sejak, dari, sampai) async {
      // Penyaringnya memakai KOLOM YANG DIMINTA ENGINE. Kalau engine masih
      // menyaring pada `updated_at`, test ini akan gagal — itulah gunanya.
      final cocok = server.where((r) {
        if (sejak == null) return true;
        final nilai = r[kolom] as String?;
        if (nilai == null) return true;
        return !DateTime.parse(nilai).isBefore(DateTime.parse(sejak));
      }).toList()
        ..sort((a, b) =>
            (a[kolom] as String).compareTo(b[kolom] as String));

      if (dari >= cocok.length) return [];
      return cocok.sublist(dari, (sampai + 1).clamp(0, cocok.length));
    };

    await db.into(db.users).insert(UsersCompanion.insert(
          id: const Value('kasir-1'),
          username: 'budi',
          pinHash: 'h',
          salt: 's',
          role: 'cashier',
        ));
    await db.into(db.shifts).insert(ShiftsCompanion.insert(
          id: const Value('shift-1'),
          userId: 'kasir-1',
        ));
  });

  tearDown(() async => db.close());

  String iso(DateTime t) => t.toUtc().toIso8601String();

  /// Satu baris transaksi seperti yang dikirim server.
  Map<String, dynamic> trx(
    String id, {
    required DateTime diubah,
    required DateTime tiba,
  }) =>
      {
        'id': id,
        'invoice_no': 'TRX/$id',
        'total': 10000,
        'payment_method': 'cash',
        'cash_received': 10000,
        'change': 0,
        'cashier_user_id': 'kasir-1',
        'shift_id': 'shift-1',
        'order_type': 'dine_in',
        'created_at': iso(diubah),
        'updated_at': iso(diubah),
        'deleted_at': null,
        'server_urut': iso(tiba),
      };

  Future<int> tarikTransaksi() async {
    final hasil = await mesin.tarikUntukTest('transactions');
    return hasil;
  }

  test('transaksi kasir yang offline berjam-jam TETAP tertarik', () async {
    final pagi = DateTime.utc(2026, 9, 28, 9);
    final siang = DateTime.utc(2026, 9, 28, 11, 30);

    // 11:30 — HP owner menerima transaksi yang dibuat dan tiba tepat waktu.
    // Penandanya maju ke sini.
    server.add(trx('tepat-waktu', diubah: siang, tiba: siang));
    await tarikTransaksi();
    expect(await db.select(db.transactions).get(), hasLength(1));

    // 12:05 — HP kasir online, mendorong transaksi pagi tadi. Cap `updated_at`
    // -nya TETAP jam 9 karena itu memang kapan transaksinya terjadi; yang
    // baru hanyalah kapan ia tiba di server.
    server.add(trx('dari-offline',
        diubah: pagi, tiba: DateTime.utc(2026, 9, 28, 12, 5)));

    await tarikTransaksi();

    final tersimpan =
        (await db.select(db.transactions).get()).map((t) => t.id).toSet();
    expect(
      tersimpan,
      {'tepat-waktu', 'dari-offline'},
      reason: 'transaksi yang dibuat saat offline tidak boleh hilang hanya '
          'karena cap waktunya lebih tua dari penanda',
    );
  });

  test('60 transaksi satu shift offline tertarik utuh', () async {
    final siang = DateTime.utc(2026, 9, 28, 11, 30);
    server.add(trx('punya-owner', diubah: siang, tiba: siang));
    await tarikTransaksi();

    // Satu shift penuh: 09:00–11:59, semuanya tiba belakangan.
    for (var i = 0; i < 60; i++) {
      server.add(trx('offline-$i',
          diubah: DateTime.utc(2026, 9, 28, 9).add(Duration(minutes: i)),
          tiba: DateTime.utc(2026, 9, 28, 12, 5, i)));
    }

    await tarikTransaksi();
    expect(await db.select(db.transactions).get(), hasLength(61));
  });

  test('jam perangkat yang meleset ke masa lalu tidak menghilangkan data',
      () async {
    final sekarang = DateTime.utc(2026, 9, 28, 12);
    server.add(trx('normal', diubah: sekarang, tiba: sekarang));
    await tarikTransaksi();

    // HP kasir jamnya mundur 3 jam. Barisnya tiba sekarang, tapi bercap lama.
    server.add(trx('jam-mundur',
        diubah: DateTime.utc(2026, 9, 28, 9),
        tiba: DateTime.utc(2026, 9, 28, 12, 0, 30)));

    await tarikTransaksi();
    expect((await db.select(db.transactions).get()).length, 2);
  });

  test('lebih dari satu halaman ikut tertarik semua', () async {
    // PostgREST memotong hasil di batas barisnya TANPA memberi tahu. Tanpa
    // paginasi, sisanya hilang diam-diam.
    final dasar = DateTime.utc(2026, 9, 28, 8);
    for (var i = 0; i < SyncEngine.ukuranHalaman + 137; i++) {
      server.add(trx('t-$i',
          diubah: dasar.add(Duration(seconds: i)),
          tiba: dasar.add(Duration(seconds: i))));
    }

    await tarikTransaksi();
    expect(await db.select(db.transactions).get(),
        hasLength(SyncEngine.ukuranHalaman + 137));
  });

  test('menarik ulang baris yang sama tidak menggandakan apa pun', () async {
    final t = DateTime.utc(2026, 9, 28, 10);
    server.add(trx('sama', diubah: t, tiba: t));

    await tarikTransaksi();
    await tarikTransaksi();
    await tarikTransaksi();

    expect(await db.select(db.transactions).get(), hasLength(1));
  });

  test('server yang BELUM dimigrasi tidak membuat penanda salah arti',
      () async {
    // Selama `sync_urutan.sql` belum dijalankan, kolomnya tidak ada. Dalam
    // keadaan itu penanda sengaja tidak dimajukan — menarik ulang tiap kali
    // jauh lebih baik daripada memajukannya dengan nilai yang salah arti.
    final t = DateTime.utc(2026, 9, 28, 10);
    server.add(trx('lama', diubah: t, tiba: t)..remove('server_urut'));

    await tarikTransaksi();
    expect(await db.select(db.transactions).get(), hasLength(1));

    final penanda = await (db.select(db.syncState)
          ..where((s) => s.entity.equals('transactions')))
        .getSingleOrNull();
    expect(penanda?.lastPulledCursor, isNull,
        reason: 'penanda tidak boleh maju kalau kolom urutannya belum ada');
  });

  test('baris yang commit terlambat tetap tertarik — gunanya jeda aman', () async {
    // Stempel `server_urut` diberikan saat baris DITULIS, tapi barisnya baru
    // terlihat pembaca lain saat transaksinya COMMIT. Dua pengiriman yang
    // bersamaan bisa commit tidak sesuai urutan stempelnya.
    //
    //   HP A mendorong  → stempel 12:00:00, commit 12:00:05 (lambat)
    //   HP B mendorong  → stempel 12:00:02, commit 12:00:02
    //   HP C menarik jam 12:00:03 → hanya melihat punya B, penanda → 12:00:02
    //   12:00:05 punya A akhirnya terlihat, stempelnya 12:00:00 — LEBIH TUA
    //
    // Tanpa jeda aman, baris A tidak akan pernah tertarik lagi.
    final b = DateTime.utc(2026, 9, 28, 12, 0, 2);
    server.add(trx('commit-cepat', diubah: b, tiba: b));
    await tarikTransaksi();

    // Baru sekarang terlihat, padahal stempelnya lebih tua dari penanda.
    server.add(trx('commit-lambat',
        diubah: DateTime.utc(2026, 9, 28, 12, 0, 0),
        tiba: DateTime.utc(2026, 9, 28, 12, 0, 0)));

    await tarikTransaksi();

    expect(
      (await db.select(db.transactions).get()).map((t) => t.id).toSet(),
      {'commit-cepat', 'commit-lambat'},
      reason: 'jeda aman harus menarik ulang sedikit ke belakang supaya baris '
          'yang commit terlambat tidak terlewat permanen',
    );
  });

  test('server belum dimigrasi: sinkron TIDAK ikut mati', () async {
    // Pembaruan aplikasi bisa sampai ke HP sebelum SQL-nya dijalankan.
    // Warung yang berhenti bisa menerima uang jauh lebih mahal daripada
    // sinkron yang boros, jadi enginenya harus mundur dengan selamat.
    mesin.penarikUntukTest = (tabel, kolom, sejak, dari, sampai) async {
      if (kolom == 'server_urut') {
        throw PostgrestException(
          message: 'column $tabel.server_urut does not exist',
          code: '42703',
        );
      }
      final cocok = server.toList()
        ..sort((a, b) =>
            (a['updated_at'] as String).compareTo(b['updated_at'] as String));
      if (dari >= cocok.length) return [];
      return cocok.sublist(dari, (sampai + 1).clamp(0, cocok.length));
    };

    final t = DateTime.utc(2026, 9, 28, 10);
    server.add(trx('tetap-masuk', diubah: t, tiba: t)..remove('server_urut'));

    await tarikTransaksi();
    expect(await db.select(db.transactions).get(), hasLength(1),
        reason: 'datanya harus tetap masuk walau kolom urutannya belum ada');

    final penanda = await (db.select(db.syncState)
          ..where((s) => s.entity.equals('transactions')))
        .getSingleOrNull();
    expect(penanda?.lastPulledCursor, isNull,
        reason: 'penanda tidak boleh diisi dengan nilai yang salah arti');
  });
}

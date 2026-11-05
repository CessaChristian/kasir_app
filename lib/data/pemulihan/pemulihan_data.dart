import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

import '../app_database.dart';

/// Tabel yang disinkron, INDUK SEBELUM ANAK — foreign key menolak sebaliknya.
const tabelCadangan = [
  'users',
  'user_permissions',
  'categories',
  'products',
  'shifts',
  'transactions',
  'transaction_items',
  'expenses',
  'open_bills',
];

/// Tabel yang ada sejak versi skema awal. Tabel yang lebih muda tidak ikut:
/// HP yang baru diperbarui belum tentu sudah menjalankan migrasinya, dan itu
/// bukan kerusakan.
const _tabelInti = [
  'users',
  'categories',
  'products',
  'shifts',
  'transactions',
  'transaction_items',
  'expenses',
];

enum KeadaanDatabase {
  sehat,

  /// Berkasnya belum ada atau belum punya tabel: pemasangan baru.
  kosong,
  rusak,
}

/// Diperiksa lewat koneksi terpisah, SEBELUM database utama dibuka.
///
/// Hanya kerusakan berkas yang disebut rusak. Galat lain, mis. memori penuh,
/// bisa hilang sendiri dan tidak boleh berujung pada penggantian database.
KeadaanDatabase periksaBerkasDatabase(String jalur) {
  if (!File(jalur).existsSync()) return KeadaanDatabase.kosong;
  sql.Database? d;
  try {
    d = sql.sqlite3.open(jalur);
    final tabel = {
      for (final r
          in d.select("SELECT name FROM sqlite_master WHERE type = 'table'"))
        r['name'] as String,
    };
    if (tabel.isEmpty) return KeadaanDatabase.kosong;
    if (!_tabelInti.every(tabel.contains)) return KeadaanDatabase.rusak;
    final hasil = d.select('PRAGMA integrity_check(1)');
    return hasil.first.values.first == 'ok'
        ? KeadaanDatabase.sehat
        : KeadaanDatabase.rusak;
  } on sql.SqliteException catch (e) {
    const sqliteCorrupt = 11, sqliteNotADb = 26;
    final kode = e.resultCode;
    if (kode == sqliteCorrupt || kode == sqliteNotADb) {
      return KeadaanDatabase.rusak;
    }
    debugPrint('[pemulihan] pemeriksaan tidak selesai: $e');
    return KeadaanDatabase.sehat;
  } finally {
    d?.close();
  }
}

/// Isi salinan data yang belum terkirim, untuk layar Data Rusak.
class RingkasanCadangan {
  final int transaksi;
  final int semua;
  const RingkasanCadangan({required this.transaksi, required this.semua});
}

/// Hasil memasukkan kembali salinan ke database baru.
class HasilPemulihan {
  final int masuk;
  final int gagal;
  const HasilPemulihan({required this.masuk, required this.gagal});
}

/// "Buku nota kedua": salinan baris `pending` di berkas terpisah.
///
/// Salinannya dibuat SEBELUM ada kerusakan. Membaca data baru sesudah rusak
/// sering terlambat: berkas yang kepotong kehilangan baris terbarunya, dan
/// baris terbaru itulah yang belum terkirim.
class BukuCadangan {
  final AppDatabase _db;
  final File berkas;
  final Duration jeda;

  BukuCadangan(
    this._db,
    this.berkas, {
    this.jeda = const Duration(milliseconds: 500),
  });

  static BukuCadangan? instance;

  StreamSubscription<void>? _langganan;
  Timer? _tunda;
  String? _terakhir;
  Future<void> _antrean = Future.value();

  /// Mulai mengikuti perubahan database. Langsung menyalin sekali supaya
  /// baris yang sudah tertunda sejak sebelum dipasang ikut terlindungi.
  void ikuti() {
    _langganan ??= _db
        .tableUpdates(
          TableUpdateQuery.onAllTables([
            _db.users,
            _db.userPermissions,
            _db.categories,
            _db.products,
            _db.shifts,
            _db.transactions,
            _db.transactionItems,
            _db.expenses,
            _db.openBills,
          ]),
        )
        .listen((_) => jadwalkan());
    unawaited(simpan());
  }

  /// Satu jualan menulis beberapa tabel, jadi disalin sekali sesudah reda.
  void jadwalkan() {
    _tunda?.cancel();
    _tunda = Timer(jeda, () => unawaited(simpan()));
  }

  /// Berurutan: salinan yang lebih lama tidak boleh menimpa yang lebih baru.
  Future<void> simpan() => _antrean = _antrean.then((_) => _simpan());

  Future<void> _simpan() async {
    try {
      final isi = <String, List<Map<String, Object?>>>{};
      for (final t in tabelCadangan) {
        final baris = await _db
            .customSelect("SELECT * FROM $t WHERE sync_status = 'pending'")
            .get();
        isi[t] = [for (final b in baris) Map.of(b.data)];
      }
      final jalur = berkas.path;
      final terakhir = _terakhir;
      // Di isolate lain: HP yang lama offline bisa punya ribuan baris, dan
      // mengubahnya jadi teks tidak boleh membuat layar tersendat.
      _terakhir = await Isolate.run(() {
        final teks = jsonEncode(isi);
        if (teks == terakhir) return teks;
        final baru = File('$jalur.baru');
        baru.writeAsStringSync(teks, flush: true);
        // Ganti nama itu sekali jadi: salinan lama tetap utuh sampai yang
        // baru selesai ditulis.
        baru.renameSync(jalur);
        return teks;
      });
    } catch (e) {
      // Salinan lama dibiarkan: lebih baik sedikit tertinggal daripada hilang.
      debugPrint('[pemulihan] salinan gagal diperbarui: $e');
    }
  }

  Future<void> berhenti() async {
    _tunda?.cancel();
    await _langganan?.cancel();
    _langganan = null;
    await _antrean;
  }
}

/// Mengganti database yang rusak dan mengembalikan data yang belum terkirim.
class PemulihanData {
  final String folder;

  PemulihanData(this.folder);

  static const kunciMenunggu = 'pemulihan_menunggu';

  File get berkasDatabase => File(p.join(folder, namaBerkasDatabase));
  File get berkasCadangan => File(p.join(folder, 'belum_terkirim.json'));
  File get berkasRusak => File(p.join(folder, 'kasir_app.rusak.sqlite'));
  File get berkasSisa => File(p.join(folder, 'belum_terkirim.sisa.json'));

  /// Keadaan database untuk menentukan layar pertama.
  Future<KeadaanDatabase> periksa() async {
    final jalur = berkasDatabase.path;
    final jam = Stopwatch()..start();
    final keadaan = await Isolate.run(() => periksaBerkasDatabase(jalur));
    debugPrint('[pemulihan] ${keadaan.name}, ${jam.elapsedMilliseconds} ms');
    if (keadaan != KeadaanDatabase.kosong || await menunggu()) return keadaan;
    // Database lenyap padahal masih ada data yang belum terkirim.
    final r = await ringkasan();
    return (r?.semua ?? 0) > 0 ? KeadaanDatabase.rusak : keadaan;
  }

  /// Null kalau salinannya tidak ada atau tidak bisa dibaca.
  Future<RingkasanCadangan?> ringkasan() async {
    final isi = await _baca();
    if (isi == null) return null;
    return RingkasanCadangan(
      transaksi: isi['transactions']?.length ?? 0,
      semua: isi.values.fold(0, (n, b) => n + b.length),
    );
  }

  Future<Map<String, List<Map<String, Object?>>>?> _baca() async {
    try {
      final data = jsonDecode(await berkasCadangan.readAsString())
          as Map<String, dynamic>;
      return {
        for (final e in data.entries)
          e.key: [
            for (final b in e.value as List) (b as Map).cast<String, Object?>(),
          ],
      };
    } catch (e) {
      debugPrint('[pemulihan] salinan tidak terbaca: $e');
      return null;
    }
  }

  /// Sudah ditekan Perbaiki data, tapi data belum selesai dikembalikan.
  Future<bool> menunggu() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(kunciMenunggu) ?? false;
  }

  /// Singkirkan database rusak. Berkasnya disimpan untuk ditelusuri, dan
  /// hanya yang terakhir supaya memori HP tidak habis.
  Future<void> karantina() async {
    final prefs = await SharedPreferences.getInstance();
    // Ditandai dulu. Kalau mati sesudah ini, pemeriksaan berikutnya tetap
    // menemukan berkas rusak dan menampilkan layarnya lagi.
    await prefs.setBool(kunciMenunggu, true);
    final db = berkasDatabase;
    if (await db.exists()) await db.rename(berkasRusak.path);
    for (final akhiran in const ['-journal', '-wal', '-shm']) {
      final sisa = File('${db.path}$akhiran');
      if (await sisa.exists()) await sisa.delete();
    }
  }

  /// Masukkan salinan ke database baru yang SUDAH ditarik dari server.
  ///
  /// Boleh diulang: tiap baris punya id tetap, jadi tidak ada yang dobel.
  /// Baris yang di database sudah sama baru atau lebih baru dilewati, artinya
  /// ia sudah sampai di server sebelum rusak atau sudah diubah HP lain.
  Future<HasilPemulihan> masukkan(AppDatabase db) async {
    final isi = await _baca() ?? const {};
    var masuk = 0;
    final sisa = <String, List<Map<String, Object?>>>{};
    await db.transaction(() async {
      for (final tabel in tabelCadangan) {
        final baris = isi[tabel];
        if (baris == null || baris.isEmpty) continue;
        final kolomAda = {
          for (final k in await db
              .customSelect('SELECT name FROM pragma_table_info(?)',
                  variables: [Variable.withString(tabel)])
              .get())
            k.read<String>('name'),
        };
        for (final b in baris) {
          try {
            if (await _tulisBaris(db, tabel, b, kolomAda)) masuk++;
          } catch (e) {
            debugPrint('[pemulihan] $tabel/${b['id']} gagal: $e');
            (sisa[tabel] ??= []).add(b);
          }
        }
      }
    });
    final gagal = sisa.values.fold(0, (n, b) => n + b.length);
    if (gagal > 0) await berkasSisa.writeAsString(jsonEncode(sisa), flush: true);
    return HasilPemulihan(masuk: masuk, gagal: gagal);
  }

  Future<bool> _tulisBaris(
    AppDatabase db,
    String tabel,
    Map<String, Object?> baris,
    Set<String> kolomAda,
  ) async {
    final isi = {
      for (final e in baris.entries)
        if (kolomAda.contains(e.key)) e.key: e.value,
    };
    final id = isi['id'] as String;
    final ada = await db
        .customSelect('SELECT updated_at FROM $tabel WHERE id = ?',
            variables: [Variable.withString(id)])
        .getSingleOrNull();
    final kolom = isi.keys.toList();
    final nilai = [for (final k in kolom) Variable<Object>(isi[k])];
    if (ada == null) {
      await db.customInsert(
        'INSERT INTO $tabel (${kolom.join(', ')}) '
        "VALUES (${List.filled(kolom.length, '?').join(', ')})",
        variables: nilai,
      );
      return true;
    }
    if (ada.read<int>('updated_at') >= (isi['updated_at'] as int)) return false;
    // BUKAN INSERT OR REPLACE: itu menghapus barisnya dulu, dan ON DELETE
    // CASCADE ikut menghapus anak-anaknya.
    await db.customUpdate(
      "UPDATE $tabel SET ${kolom.map((k) => '$k = ?').join(', ')} WHERE id = ?",
      variables: [...nilai, Variable.withString(id)],
    );
    return true;
  }

  Future<void> selesai() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kunciMenunggu);
  }
}

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/services/image_storage_service.dart';
import '../app_database.dart';
import 'kemajuan_sync.dart';

/// Hasil satu putaran sinkronisasi gambar.
class HasilSyncGambar {
  final int diunggah;
  final int diunduh;

  /// Berkas yatim yang dibuang dari server.
  final int dihapus;

  /// Berkas yatim yang dibuang dari penyimpanan perangkat ini.
  ///
  /// Dihitung terpisah karena angkanya memang berbeda: perangkat yang MENGGANTI
  /// foto sudah membuang berkas lamanya saat penyimpanan, sedangkan perangkat
  /// lain baru membuangnya di sini.
  final int dihapusLokal;

  final String? error;

  const HasilSyncGambar({
    this.diunggah = 0,
    this.diunduh = 0,
    this.dihapus = 0,
    this.dihapusLokal = 0,
    this.error,
  });

  bool get berhasil => error == null;
  bool get adaPerubahan =>
      diunggah > 0 || diunduh > 0 || dihapus > 0 || dihapusLokal > 0;

  @override
  String toString() => berhasil
      ? 'unggah $diunggah, unduh $diunduh, hapus $dihapus/$dihapusLokal'
      : 'GAGAL: $error';
}

/// Memindahkan BERKAS gambar produk antara perangkat dan Supabase Storage.
///
/// ── MASALAH YANG DIPECAHKAN ──
///
/// Sinkronisasi tabel hanya memindahkan `products.image_path` — sebuah TEKS.
/// Berkasnya tidak ikut ke mana-mana. Akibatnya perangkat kedua menerima baris
/// yang menunjuk `products/abc.webp`, lalu mencari berkas itu di disknya
/// sendiri dan tidak menemukannya. Produknya tampil tanpa gambar, tanpa
/// penjelasan apa pun.
///
/// ── KENAPA TIDAK ADA KOLOM PENANDA ──
///
/// Pilihan yang lebih lazim adalah menambah kolom seperti `image_synced` untuk
/// mengingat berkas mana yang sudah naik. Itu tidak dipakai di sini karena
/// penanda semacam itu bisa MELENCENG dari kenyataan: unggahan yang gagal di
/// tengah jalan meninggalkan penanda yang berbohong, dan tidak ada yang
/// memeriksanya lagi.
///
/// Sebagai gantinya, keadaan sebenarnya ditanyakan langsung: SATU panggilan
/// `list()` memberi tahu berkas apa saja yang benar-benar ada di server, lalu
/// dibandingkan dengan berkas yang benar-benar ada di disk. Tidak ada yang
/// perlu diingat, jadi tidak ada yang bisa salah ingat — dan unggahan yang
/// gagal otomatis diulang di putaran berikutnya karena berkasnya memang masih
/// belum ada di sana.
///
/// Biayanya satu permintaan `list()` per putaran. Untuk warung dengan puluhan
/// produk itu sepele.
///
/// ── KENAPA TERPISAH DARI SyncEngine ──
///
/// Kegagalan memindahkan gambar TIDAK BOLEH menghambat sinkronisasi baris.
/// Kalau digabung, satu gambar yang gagal naik bisa menahan perubahan harga
/// atau transaksi yang jauh lebih mendesak. Di sini gambar dikerjakan setelah
/// baris selesai, dan kegagalannya dilaporkan tanpa membatalkan apa pun.
class SyncGambar {
  /// Nama bucket di Supabase Storage. Lihat `supabase/storage.sql`.
  static const bucket = 'product-images';

  /// Satu halaman `list()`. Supabase membatasi 100 per permintaan.
  static const _ukuranHalaman = 100;

  final AppDatabase _db;
  final SupabaseClient _client;
  final ImageStorageService _berkas;
  final void Function(KemajuanSync)? onKemajuan;

  SyncGambar(
    this._db,
    this._client, {
    ImageStorageService? berkas,
    this.onKemajuan,
  }) : _berkas = berkas ?? ImageStorageService();

  Future<HasilSyncGambar> jalankan() async {
    try {
      final diServer = await _daftarServer();
      final dirujuk = await _pathDirujuk();

      // Yang perlu NAIK: berkasnya ada di sini, tapi belum ada di server.
      final naik = <String>[];
      for (final p in dirujuk) {
        if (diServer.contains(p)) continue;
        if (await _berkas.ada(p)) naik.add(p);
      }

      // Yang perlu TURUN: barisnya menunjuk berkas yang ada di server, tapi
      // berkasnya belum ada di sini.
      final turun = <String>[];
      for (final p in dirujuk) {
        if (!diServer.contains(p)) continue;
        if (!await _berkas.ada(p)) turun.add(p);
      }

      // Yang perlu DIBUANG: ada di server, tapi tidak ada satu pun baris yang
      // menunjuknya — sisa dari produk yang fotonya sudah diganti.
      //
      // Aman dilakukan dari sini karena pembersihan berjalan SETELAH tarikan
      // selesai, jadi daftar produk lokal sudah memuat perubahan dari
      // perangkat lain.
      final boleh = await _bolehMembuangImpl(dirujuk);

      // Yang perlu DIBUANG DI SERVER: ada di sana, tapi tidak ada satu pun
      // baris yang menunjuknya — sisa dari produk yang fotonya sudah diganti.
      //
      // Aman dilakukan dari sini karena pembersihan berjalan SETELAH tarikan
      // selesai, jadi daftar produk lokal sudah memuat perubahan dari
      // perangkat lain.
      final buang = boleh ? diServer.difference(dirujuk).toList() : <String>[];

      // Yang perlu DIBUANG DI SINI. Perangkat yang mengganti foto sudah
      // membuang berkas lamanya saat menyimpan, tapi perangkat LAIN tidak —
      // mereka mengunduh yang baru dan menyimpan yang lama selamanya. Tanpa
      // pembersihan ini, penyimpanan HP kasir terus membengkak oleh foto yang
      // tidak akan pernah ditampilkan lagi.
      final buangLokal = boleh
          ? (await _berkas.daftarBerkas()).difference(dirujuk).toList()
          : <String>[];

      final total =
          naik.length + turun.length + buang.length + buangLokal.length;
      if (total == 0) return const HasilSyncGambar();

      var selesai = 0;
      var diunggah = 0;
      var diunduh = 0;
      _lapor(0, total);

      for (final p in naik) {
        final f = await _berkas.fileDari(p);
        // `upsert` supaya percobaan ulang setelah unggahan yang terputus tidak
        // ditolak sebagai duplikat dan macet selamanya.
        await _client.storage.from(bucket).upload(
              p,
              f,
              fileOptions: const FileOptions(upsert: true),
            );
        diunggah++;
        _lapor(++selesai, total);
      }

      for (final p in turun) {
        final data = await _client.storage.from(bucket).download(p);
        await _berkas.simpanBytes(p, data);
        diunduh++;
        _lapor(++selesai, total);
      }

      var dihapus = 0;
      if (buang.isNotEmpty) {
        await _client.storage.from(bucket).remove(buang);
        dihapus = buang.length;
        selesai += buang.length;
        _lapor(selesai, total);
      }

      for (final p in buangLokal) {
        await _berkas.hapus(p);
        _lapor(++selesai, total);
      }

      return HasilSyncGambar(
        diunggah: diunggah,
        diunduh: diunduh,
        dihapus: dihapus,
        dihapusLokal: buangLokal.length,
      );
    } catch (e) {
      return HasilSyncGambar(error: e.toString());
    }
  }

  void _lapor(int baris, int total) {
    onKemajuan?.call(KemajuanSync(
      tahap: 'gambar',
      entitas: 'gambar',
      entitasKe: KemajuanSync.totalTahap,
      totalEntitas: KemajuanSync.totalTahap,
      baris: baris,
      totalBaris: total,
      perubahan: baris,
    ));
  }

  /// Bolehkah membuang berkas yang tidak dirujuk siapa pun?
  ///
  /// ── KENAPA PENJAGA INI ADA ──
  ///
  /// Penghapusan diputuskan dengan membandingkan isi bucket terhadap daftar
  /// produk LOKAL. Kalau daftar itu kosong, kesimpulannya jadi "tidak ada satu
  /// pun berkas yang dirujuk" — dan seluruh isi bucket akan dibuang.
  ///
  /// Database lokal bisa kosong bukan hanya karena memang tidak ada produk:
  /// pemasangan baru sebelum tarikan pertama, atau database yang gagal dibuka
  /// dan dibuat ulang, sama-sama menghasilkan tabel kosong. Membedakan "tidak
  /// ada produk" dari "produknya belum termuat" tidak mungkin dari sini.
  ///
  /// Maka kalau tabel produknya kosong, TIDAK ADA yang dibuang. Harganya cuma
  /// beberapa berkas yatim yang tertinggal lebih lama; taruhannya seluruh foto
  /// produk milik pengguna.
  @visibleForTesting
  Future<bool> bolehMembuang(Set<String> dirujuk) => _bolehMembuangImpl(dirujuk);

  Future<bool> _bolehMembuangImpl(Set<String> dirujuk) async {
    if (dirujuk.isNotEmpty) return true;
    final jumlah = await _db.customSelect(
      'SELECT COUNT(*) c FROM products',
    ).getSingle();
    return jumlah.read<int>('c') > 0;
  }

  /// Semua `image_path` yang masih dirujuk baris produk.
  ///
  /// Produk yang sudah dihapus lunak SENGAJA ikut: riwayat transaksi lama
  /// masih menampilkan produknya, dan pemilik bisa memulihkan penghapusan.
  /// Berkasnya baru boleh dianggap tidak terpakai kalau tidak ada baris sama
  /// sekali yang menunjuknya.
  @visibleForTesting
  Future<Set<String>> pathDirujuk() => _pathDirujuk();

  Future<Set<String>> _pathDirujuk() async {
    final baris = await (_db.select(_db.products)
          ..where((p) => p.imagePath.isNotNull()))
        .get();
    return {
      for (final p in baris)
        if ((p.imagePath ?? '').isNotEmpty) p.imagePath!,
    };
  }

  /// Berkas yang benar-benar ada di bucket, sebagai path relatif lengkap.
  ///
  /// `list()` mengembalikan nama berkas saja tanpa foldernya, jadi prefiksnya
  /// dipasang kembali supaya sebanding dengan isi `products.image_path`.
  Future<Set<String>> _daftarServer() async {
    final hasil = <String>{};
    var offset = 0;
    while (true) {
      final halaman = await _client.storage.from(bucket).list(
            path: ImageStorageService.folderProduk,
            searchOptions: SearchOptions(
              limit: _ukuranHalaman,
              offset: offset,
            ),
          );
      for (final f in halaman) {
        hasil.add('${ImageStorageService.folderProduk}/${f.name}');
      }
      if (halaman.length < _ukuranHalaman) break;
      offset += halaman.length;
    }
    return hasil;
  }
}

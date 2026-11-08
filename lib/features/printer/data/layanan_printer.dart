import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pengaturan printer HP INI — tidak ikut sinkron: tiap HP memegang
/// printernya sendiri (riset Moka & Kasir Pintar, 2026-11-01).
class PengaturanPrinter {
  final String? mac;
  final String? nama;

  const PengaturanPrinter({this.mac, this.nama});

  bool get dipilih => mac != null && mac!.isNotEmpty;
}

/// Printer Bluetooth yang sudah dipasangkan di HP.
typedef PrinterTerpasang = ({String nama, String mac});

enum HasilCetak {
  berhasil,
  belumDipilih,
  bluetoothMati,
  tanpaIzin,
  takTersambung,
  gagalKirim,

  /// Batas waktu habis saat struk SEDANG dikirim: sebagian atau seluruhnya
  /// bisa sudah keluar — byte yang sudah sampai di printer tidak bisa
  /// ditarik lagi.
  mungkinTercetak,
}

/// Pesan untuk kasir, atau null kalau berhasil.
String? pesanCetak(HasilCetak h) => switch (h) {
  HasilCetak.berhasil => null,
  HasilCetak.belumDipilih =>
    'Printer belum dipilih. Atur di Profil → Printer Struk.',
  HasilCetak.bluetoothMati =>
    'Bluetooth HP mati. Nyalakan Bluetooth lalu coba lagi.',
  HasilCetak.tanpaIzin =>
    'Izin Bluetooth belum diberikan. Buka Profil → Printer Struk, lalu '
        'ketuk Beri izin.',
  HasilCetak.takTersambung =>
    'Printer tidak tersambung. Nyalakan printer, dekatkan ke HP, lalu '
        'coba lagi.',
  HasilCetak.gagalKirim =>
    'Struk gagal terkirim ke printer. Periksa kertas & printer, lalu '
        'coba lagi.',
  HasilCetak.mungkinTercetak =>
    'Struk mungkin sudah tercetak. Cek printer sebelum cetak ulang.',
};

/// Satu cetakan yang sedang berjalan. [ditinggal]: batas waktunya sudah
/// habis dan kasir sudah diberi tahu — cetakan ini tidak boleh lagi
/// mengirim apa pun ke printer.
class _Cetakan {
  var ditinggal = false;
  var mengirim = false;
}

/// Jembatan ke plugin Bluetooth — diganti tiruan di test.
abstract class SaluranPrinter {
  Future<bool> bluetoothNyala();
  Future<bool> izinAda();
  /// Hanya PRINTER yang sudah dipasangkan — bukan headset, speaker, dll.
  Future<List<PrinterTerpasang>> terpasang();
  Future<void> bukaPengaturanBluetooth();
  Future<void> bukaPengaturanIzin();
  Future<bool> tersambung();
  Future<bool> sambung(String mac);
  Future<bool> kirim(List<int> bytes);
  Future<void> putus();
}

class _SaluranPlugin implements SaluranPrinter {
  @override
  Future<bool> bluetoothNyala() => PrintBluetoothThermal.bluetoothEnabled;

  /// Juga meminta izin "Perangkat di sekitar" (Android 12+) kalau belum.
  @override
  Future<bool> izinAda() => PrintBluetoothThermal.isPermissionBluetoothGranted;

  /// Lewat MainActivity.kt, bukan plugin: plugin tidak tahu jenis
  /// perangkat, jadi semua yang pernah dipasangkan ikut tampil.
  static const _android = MethodChannel('kasir_app/printer');

  @override
  Future<List<PrinterTerpasang>> terpasang() async => [
    for (final p in await _android.invokeListMethod<Map>('printerTerpasang') ??
        const <Map>[])
      (nama: '${p['nama']}', mac: '${p['mac']}'),
  ];

  @override
  Future<void> bukaPengaturanBluetooth() =>
      _android.invokeMethod('bukaPengaturanBluetooth');

  @override
  Future<void> bukaPengaturanIzin() =>
      _android.invokeMethod('bukaPengaturanIzin');

  @override
  Future<bool> tersambung() => PrintBluetoothThermal.connectionStatus;

  @override
  Future<bool> sambung(String mac) =>
      PrintBluetoothThermal.connect(macPrinterAddress: mac);

  @override
  Future<bool> kirim(List<int> bytes) =>
      PrintBluetoothThermal.writeBytes(bytes);

  @override
  Future<void> putus() => PrintBluetoothThermal.disconnect;
}

/// Satu-satunya pintu ke printer struk.
///
/// Gagal cetak TIDAK PERNAH menggagalkan penjualan: transaksinya sudah
/// tersimpan sebelum dicetak, dan struknya bisa dicetak ulang dari Riwayat.
class LayananPrinter {
  LayananPrinter._(this._saluran)
    : jedaSesudahSambung = _jedaSesudahSambung,
      batasCetak = batasWaktu;

  static LayananPrinter _instance = LayananPrinter._(_SaluranPlugin());
  static LayananPrinter get instance => _instance;

  /// Ganti layanan bawaan (test halaman yang membuka PrinterPage).
  @visibleForTesting
  static set instance(LayananPrinter l) => _instance = l;

  @visibleForTesting
  LayananPrinter.untukTest(
    this._saluran, {
    this.jedaSesudahSambung = Duration.zero,
    this.batasCetak = batasWaktu,
  });

  final SaluranPrinter _saluran;

  /// Jeda antara tersambung dan kiriman pertama. Kiriman yang langsung
  /// menyusul sambungan baru kehilangan beberapa byte awal di RPP02N —
  /// logo cetakan pertama miring dan bergeser, cetakan berikutnya normal
  /// (tes owner 2026-11-01).
  final Duration jedaSesudahSambung;
  static const _jedaSesudahSambung = Duration(milliseconds: 600);

  /// Batas satu cetakan dari giliran dimulai sampai selesai. Printer yang
  /// mati atau terlalu jauh membuat sambungan Bluetooth menunggu lama; kasir
  /// tidak boleh ikut menunggu (review R1, keputusan owner 2026-11-01).
  ///
  /// Cukup untuk sambung ulang sekali ketika sambungan lama ternyata putus
  /// (review 3 Nov: dulu 10 detik, lebih pendek dari langkah-langkahnya,
  /// jadi sambung ulang hampir tidak pernah sempat). Printer yang mati
  /// tetap cepat ketahuan: sambungan baru yang gagal tidak diulang.
  static const batasWaktu = Duration(seconds: 20);

  /// [batasWaktu]; dipendekkan di test.
  final Duration batasCetak;

  /// Batas tiap langkah (sambung, kirim, ...) di dalam [batasWaktu].
  static const batasLangkah = Duration(seconds: 7);

  static const _kMac = 'printer_mac';
  static const _kNama = 'printer_nama';

  Future<PengaturanPrinter> muat() async {
    final p = await SharedPreferences.getInstance();
    return PengaturanPrinter(
      mac: p.getString(_kMac),
      nama: p.getString(_kNama),
    );
  }

  Future<void> simpan(PengaturanPrinter x) async {
    final p = await SharedPreferences.getInstance();
    if (x.mac case final mac?) await p.setString(_kMac, mac);
    if (x.nama case final nama?) await p.setString(_kNama, nama);
  }

  /// Tanya [izinAda] DULU: tanpa izin, plugin menolak semua pertanyaan
  /// lain dan Bluetooth yang menyala pun terbaca mati.
  Future<bool> bluetoothNyala() => _aman(_saluran.bluetoothNyala);

  /// Izin "Perangkat di sekitar" (Android 12+). Kalau belum ada, popup izin
  /// muncul dan jawabannya ditunggu — tanpa batas waktu, karena yang
  /// ditunggu adalah orangnya.
  Future<bool> izinAda() async {
    try {
      return await _saluran.izinAda();
    } catch (e) {
      debugPrint('[printer] izin: $e');
      return false;
    }
  }

  Future<void> bukaPengaturanBluetooth() async {
    try {
      await _saluran.bukaPengaturanBluetooth();
    } catch (e) {
      debugPrint('[printer] buka pengaturan Bluetooth: $e');
    }
  }

  Future<void> bukaPengaturanIzin() async {
    try {
      await _saluran.bukaPengaturanIzin();
    } catch (e) {
      debugPrint('[printer] buka pengaturan izin: $e');
    }
  }

  Future<List<PrinterTerpasang>> terpasang() async {
    try {
      return await _saluran.terpasang().timeout(batasLangkah);
    } catch (e) {
      debugPrint('[printer] daftar printer gagal: $e');
      return const [];
    }
  }

  /// Hanya satu urusan dengan printer berjalan (cetak atau periksa);
  /// ketukan kedua menunggu giliran, tidak mencampur dua struk di kertas
  /// yang sama.
  Future<Object?>? _antrean;

  Future<T> _giliran<T>(Future<T> Function() kerja) {
    final sebelum = _antrean;
    final hasil = () async {
      // Galat pekerjaan sebelumnya urusan pemanggilnya sendiri. Dulu ikut
      // dilempar ke sini: setiap pekerjaan sesudahnya gagal sebelum mulai,
      // dan kartu "Mencetak struk…" berputar sampai aplikasi ditutup paksa
      // (audit 6 Nov nomor 36).
      if (sebelum != null) {
        try {
          await sebelum;
        } catch (_) {}
      }
      return kerja();
    }();
    _antrean = hasil;
    return hasil;
  }

  /// Kirim [bytes] ke printer yang dipilih di HP ini.
  ///
  /// Lewat [batasWaktu], kasir langsung diberi jawaban, tapi pekerjaannya
  /// sendiri baru berhenti di langkah berikutnya — dan sampai berhenti, ia
  /// tetap memegang giliran. Dulu giliran dilepas begitu batas waktu habis:
  /// cetakan lama yang akhirnya tersambung tetap mencetak, berbarengan
  /// dengan cetakan baru dari ketukan berikutnya — struk dobel atau
  /// bercampur (review 3 Nov).
  Future<HasilCetak> cetak(List<int> bytes) {
    final jawaban = Completer<HasilCetak>();
    _giliran(() async {
      final c = _Cetakan();
      final kerja = _cetak(bytes, c);
      try {
        jawaban.complete(
          await kerja.timeout(
            batasCetak,
            onTimeout: () {
              c.ditinggal = true;
              if (c.mengirim) return HasilCetak.mungkinTercetak;
              // Masih menyambung: sambungannya diputus SEKARANG supaya
              // langkah yang menggantung ikut berhenti. Dulu langkahnya
              // ditunggu sampai batasnya sendiri, dan cetak ulang kasir
              // menunggu sampai ±35 detik (audit 6 Nov nomor 52). Yang
              // sedang MENGIRIM tidak diputus: struknya bisa terpotong.
              unawaited(_diam(_saluran.putus));
              return HasilCetak.takTersambung;
            },
          ),
        );
        await kerja;
      } catch (e) {
        // Galat tak terduga (mis. pengaturan gagal dibaca): kasir tetap
        // mendapat jawaban, dan antrean tidak ikut macet.
        debugPrint('[printer] cetak: $e');
        if (!jawaban.isCompleted) jawaban.complete(HasilCetak.gagalKirim);
      }
    });
    return jawaban.future;
  }

  /// Apakah printer yang dipilih benar-benar menyala dan terjangkau —
  /// dicoba disambungkan, bukan hanya dilihat dari daftar "pernah
  /// dipasangkan" (printer yang mati tetap ada di daftar itu; tes owner
  /// 2026-11-01). Sambungan yang berhasil dibiarkan terbuka untuk cetakan
  /// berikutnya.
  Future<bool> periksa() => _giliran(() async {
    final atur = await muat();
    if (!atur.dipilih || !await izinAda() || !await bluetoothNyala()) {
      return false;
    }
    if (_macTersambung == atur.mac && await _aman(_saluran.tersambung)) {
      return true;
    }
    await _diam(_saluran.putus);
    _macTersambung = null;
    if (!await _aman(() => _saluran.sambung(atur.mac!))) return false;
    _tersambungBaru(atur.mac!);
    return true;
  });

  /// Kiriman pertama sesudah tersambung paling cepat pada saat ini — lihat
  /// [jedaSesudahSambung].
  DateTime? _bolehKirimPada;

  void _tersambungBaru(String mac) {
    _macTersambung = mac;
    _bolehKirimPada = DateTime.now().add(jedaSesudahSambung);
  }

  Future<void> _tungguSiap() async {
    final sisa = _bolehKirimPada?.difference(DateTime.now());
    if (sisa != null && sisa > Duration.zero) {
      await Future<void>.delayed(sisa);
    }
  }

  Future<HasilCetak> _cetak(List<int> bytes, _Cetakan c) async {
    final atur = await muat();
    if (!atur.dipilih) return HasilCetak.belumDipilih;
    if (!await izinAda()) return HasilCetak.tanpaIzin;
    if (!await bluetoothNyala()) return HasilCetak.bluetoothMati;

    // Sambungan lama dipakai lagi; kalau ternyata sudah mati (printer
    // dimatikan sejak cetakan terakhir), sambung ulang sekali. Sambungan
    // BARU yang gagal tidak diulang: printernya memang mati atau terlalu
    // jauh, dan kasir perlu tahu secepatnya.
    //
    // "Tersambung" dari plugin tidak menyebut KE MANA: dulu printer yang
    // baru dipilih diabaikan dan struk tetap keluar di printer lama (tes
    // owner 2026-11-01). Printer berganti = sambung ulang.
    for (var coba = 0; coba < 2; coba++) {
      final pakaiLama = coba == 0 &&
          _macTersambung == atur.mac &&
          await _aman(_saluran.tersambung);
      if (c.ditinggal) return _tinggalkan();
      if (!pakaiLama) {
        await _diam(_saluran.putus);
        _macTersambung = null;
        if (!await _aman(() => _saluran.sambung(atur.mac!))) {
          return HasilCetak.takTersambung;
        }
        _tersambungBaru(atur.mac!);
      }
      await _tungguSiap();
      if (c.ditinggal) return _tinggalkan();
      c.mengirim = true;
      if (await _aman(() => _saluran.kirim(bytes))) return HasilCetak.berhasil;
      c.mengirim = false;
      if (!pakaiLama || c.ditinggal) break;
    }
    return _tinggalkan(HasilCetak.gagalKirim);
  }

  /// Putuskan sambungan dan berhenti — sambungan yang keadaannya tidak
  /// pasti tidak dipakai cetakan berikutnya.
  Future<HasilCetak> _tinggalkan([
    HasilCetak hasil = HasilCetak.takTersambung,
  ]) async {
    await _diam(_saluran.putus);
    _macTersambung = null;
    return hasil;
  }

  /// Printer yang sedang tersambung lewat layanan ini.
  String? _macTersambung;

  /// Panggilan ke plugin: galat atau lewat [batasLangkah] = false.
  Future<bool> _aman(Future<bool> Function() f) async {
    try {
      return await f().timeout(batasLangkah);
    } catch (e) {
      debugPrint('[printer] $e');
      return false;
    }
  }

  Future<void> _diam(Future<void> Function() f) async {
    try {
      await f().timeout(batasLangkah);
    } catch (_) {}
  }
}

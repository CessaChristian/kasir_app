import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/pesan_galat.dart';
import 'pemulihan_data.dart';

/// Menangkap database yang rusak DI TENGAH pemakaian, dari halaman mana pun.
///
/// Pemeriksaan saat aplikasi dibuka (`PemulihanData.periksa`) tidak melihat
/// kerusakan yang terjadi sesudahnya. Di sini setiap galat database yang
/// tercatat memicu pemeriksaan berkas yang sama; kalau TERBUKTI rusak,
/// [rusak] menyala dan aplikasi menampilkan layar Data Rusak.
///
/// Perbaikannya tetap saat aplikasi dibuka lagi: database sudah terbuka di
/// isolate lain, dan berkasnya tidak bisa diganti selagi dipakai.
class PenjagaDatabase {
  PenjagaDatabase._();
  static final instance = PenjagaDatabase._();

  @visibleForTesting
  PenjagaDatabase.untukTest();

  /// Berkas database terbukti rusak selagi aplikasi berjalan.
  final rusak = ValueNotifier<bool>(false);

  PemulihanData? _pemulihan;
  bool _memeriksa = false;
  DateTime? _terakhir;

  /// Pengganti pemeriksaan berkas, untuk test.
  @visibleForTesting
  Future<KeadaanDatabase> Function()? pemeriksaUntukTest;

  void siapkan(PemulihanData pemulihan) => _pemulihan = pemulihan;

  /// Salinan data yang belum terkirim, untuk layar Data Rusak.
  Future<RingkasanCadangan?> ringkasan() async => _pemulihan?.ringkasan();

  /// [galat] baru saja terjadi. Bukan galat database = diabaikan.
  void laporkan(Object galat) {
    if (rusak.value || !galatDatabase(galat)) return;
    unawaited(periksa());
  }

  /// Periksa berkasnya sekarang. Paling sering sekali semenit: galat yang
  /// sama bisa datang beruntun, dan pemeriksaan penuh tidak murah.
  Future<void> periksa() async {
    final kini = DateTime.now();
    final terakhir = _terakhir;
    if (_memeriksa ||
        (terakhir != null &&
            kini.difference(terakhir) < const Duration(minutes: 1))) {
      return;
    }
    _memeriksa = true;
    _terakhir = kini;
    try {
      final pengganti = pemeriksaUntukTest;
      final KeadaanDatabase keadaan;
      if (pengganti != null) {
        keadaan = await pengganti();
      } else {
        final jalur = _pemulihan?.berkasDatabase.path;
        if (jalur == null) return;
        // Pemeriksaan PENUH: layar ini menutup seluruh aplikasi, jadi hanya
        // muncul kalau berkasnya benar-benar rusak — bukan karena memori
        // penuh atau galat sesaat lain.
        keadaan = await Isolate.run(
          () => periksaBerkasDatabase(jalur, penuh: true),
        );
      }
      debugPrint('[penjaga database] ${keadaan.name}');
      if (keadaan != KeadaanDatabase.rusak) return;
      // Saat dibuka lagi pemeriksaannya juga harus penuh, supaya layar
      // Perbaiki data pasti muncul.
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(PemulihanData.kunciCekPenuh);
      rusak.value = true;
    } catch (e) {
      debugPrint('[penjaga database] pemeriksaan gagal: $e');
    } finally {
      _memeriksa = false;
    }
  }
}

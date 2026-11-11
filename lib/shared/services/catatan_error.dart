import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../data/pemulihan/penjaga_database.dart';
import '../../data/supabase/supabase_service.dart';
import '../../data/uuid_helper.dart';
import '../../utils/pesan_galat.dart';
import '../auth/session_manager.dart';
import '../constants/app_constants.dart';

/// Catatan error tak terduga di HP ini, dikirim ke server saat sinkron
/// (`supabase/catatan_error.sql`) supaya selama uji coba kita tahu ada yang
/// salah tanpa menunggu kasir bercerita (audit 6 Nov nomor 62).
///
/// Ditulis ke BERKAS, bukan database: harus tetap bisa mencatat justru saat
/// databasenya yang bermasalah. Berkas itu antrean — error saat offline
/// menunggu di sana sampai terkirim.
///
/// Tidak pernah melempar: pencatat yang ikut gagal hanya menambah masalah.
class CatatanError {
  CatatanError._();
  static final instance = CatatanError._();

  @visibleForTesting
  CatatanError.untukTest();

  /// Paling banyak sebanyak ini yang menunggu di HP; yang terlama dibuang.
  static const batasSimpan = 200;

  /// Sekali kirim (sama dengan batas di `catat_error`).
  static const batasKirim = 50;

  static const _panjangPesan = 500;
  static const _barisJejak = 20;

  File? _berkas;
  final List<Map<String, dynamic>> _isi = [];
  Timer? _tunda;
  bool _mengirim = false;

  /// Error yang sudah dicatat — objek yang sama tidak dihitung dua kali
  /// walau pesannya dibangun ulang tiap layar digambar.
  final _sudah = Expando<bool>();

  /// Pengganti kiriman ke server, untuk test.
  @visibleForTesting
  Future<void> Function(List<Map<String, dynamic>> baris)? pengirimUntukTest;

  @visibleForTesting
  List<Map<String, dynamic>> get isi => List.unmodifiable(_isi);

  /// Muat catatan yang belum terkirim dari [folder]. Berkas rusak = mulai
  /// dari kosong.
  Future<void> siapkan(String folder) async {
    try {
      final berkas = File(p.join(folder, 'catatan_error.json'));
      _berkas = berkas;
      // Yang tercatat sebelum siap ikut disimpan.
      if (_isi.isNotEmpty) _jadwalkanSimpan();
      if (!await berkas.exists()) return;
      final lama = [
        for (final b in jsonDecode(await berkas.readAsString()) as List)
          (b as Map).cast<String, dynamic>(),
      ];
      // Yang tercatat sebelum berkasnya selesai dibaca tetap di belakang.
      _isi.insertAll(0, lama);
      _pangkas();
    } catch (e) {
      debugPrint('[catatan error] berkas tidak terbaca: $e');
    }
  }

  /// Catat [galat]. [sumber]: 'tampilan' (gagal menggambar layar), 'latar'
  /// (tidak ditangkap siapa pun), atau 'tertangkap' (ditangkap, tapi bukan
  /// galat yang dikenali).
  void catat(Object galat, StackTrace? jejak, {required String sumber}) {
    try {
      // Tidak ada internet bukan kesalahan aplikasi.
      if (galatTakTersambung(galat)) return;
      if (galat is! String && galat is! num && galat is! bool) {
        if (_sudah[galat] == true) return;
        _sudah[galat] = true;
      }
      PenjagaDatabase.instance.laporkan(galat);

      final pesan = _potong('$galat', _panjangPesan);
      final teksJejak = (jejak ?? StackTrace.empty)
          .toString()
          .split('\n')
          .take(_barisJejak)
          .join('\n');
      final kunci = '$sumber|$pesan|${teksJejak.split('\n').take(3).join()}';
      final sama = _isi.where((b) => b['_kunci'] == kunci).firstOrNull;
      if (sama != null) {
        sama['jumlah'] = (sama['jumlah'] as int) + 1;
      } else {
        final sesi = SessionManager.instance.currentSession;
        _isi.add({
          'id': newUuid(),
          'waktu': DateTime.now().toUtc().toIso8601String(),
          'akun': sesi?.username,
          'peran': sesi?.role,
          'versi': AppConstants.versiAplikasi,
          'sumber': sumber,
          'pesan': pesan,
          'jejak': teksJejak,
          'jumlah': 1,
          '_kunci': kunci,
        });
        _pangkas();
        debugPrint('[catatan error] $sumber: $pesan');
      }
      _jadwalkanSimpan();
    } catch (e) {
      debugPrint('[catatan error] gagal mencatat: $e');
    }
  }

  static String _potong(String s, int n) =>
      s.length <= n ? s : '${s.substring(0, n)}…';

  void _pangkas() {
    if (_isi.length > batasSimpan) {
      _isi.removeRange(0, _isi.length - batasSimpan);
    }
  }

  // Error tampilan bisa berulang puluhan kali per detik: ditulis sekali
  // sesudah reda.
  void _jadwalkanSimpan() {
    // Belum disiapkan (awal aplikasi, test): [siapkan] yang menyimpannya.
    if (_berkas == null) return;
    _tunda?.cancel();
    _tunda = Timer(const Duration(seconds: 2), () => unawaited(simpan()));
  }

  @visibleForTesting
  Future<void> simpan() async {
    _tunda?.cancel();
    final berkas = _berkas;
    if (berkas == null) return;
    try {
      final baru = File('${berkas.path}.baru');
      await baru.writeAsString(jsonEncode(_isi), flush: true);
      await baru.rename(berkas.path);
    } catch (e) {
      debugPrint('[catatan error] gagal disimpan: $e');
    }
  }

  /// Kirim yang menunggu ke server; yang sampai dihapus dari HP. Dipanggil
  /// sesudah tiap sinkron. Gagal = tetap menunggu, tanpa pesan ke pengguna.
  Future<void> kirim() async {
    if (_mengirim || _isi.isEmpty) return;
    final pengirim = pengirimUntukTest;
    if (pengirim == null && !SupabaseService.instance.online) return;
    _mengirim = true;
    try {
      final kiriman = _isi.take(batasKirim).toList();
      final jumlah = {for (final b in kiriman) b['id']: b['jumlah'] as int};
      final baris = [
        for (final b in kiriman)
          {
            for (final e in b.entries)
              if (!e.key.startsWith('_')) e.key: e.value,
          },
      ];
      if (pengirim != null) {
        await pengirim(baris);
      } else {
        await SupabaseService.instance.client!.rpc(
          'catat_error',
          params: {'p_baris': baris},
        );
      }
      for (final b in kiriman) {
        // Terulang lagi selagi dikirim: sisanya jadi catatan baru.
        final lebih = (b['jumlah'] as int) - jumlah[b['id']]!;
        if (lebih > 0) {
          b
            ..['id'] = newUuid()
            ..['jumlah'] = lebih;
        } else {
          _isi.remove(b);
        }
      }
      await simpan();
    } catch (e) {
      // Fungsinya belum ada di server (SQL belum dijalankan) atau server
      // sedang tidak bisa: dicoba lagi di sinkron berikutnya.
      final belumAda =
          e is PostgrestException &&
          const {'PGRST202', '42883'}.contains(e.code);
      if (belumAda) {
        debugPrint('[catatan error] catat_error belum ada di server.');
      } else {
        debugPrint('[catatan error] belum terkirim: $e');
      }
    } finally {
      _mengirim = false;
    }
  }
}

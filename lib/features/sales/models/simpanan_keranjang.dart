import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'keranjang.dart';

/// Keranjang yang disimpan di HP, supaya pesanan yang sedang disusun tidak
/// hilang kalau aplikasinya dimatikan — Android bisa menutup aplikasi di
/// belakang saat kasir membuka kamera atau WhatsApp (tes alur 10 Nov).
///
/// Ditandai kasir dan shift-nya: hanya dipulihkan untuk kasir yang sama di
/// shift yang sama. Keluar akun — termasuk otomatis sesudah 15 menit diam
/// dan akun dinonaktifkan — menghapusnya (`SessionManager.clearSession`).
class SimpananKeranjang {
  SimpananKeranjang._();

  static const kunci = 'keranjang_tersimpan';

  /// Simpan [k] milik [userId] di [shiftId]. Keranjang kosong = hapus.
  static Future<void> simpan(
    Keranjang k, {
    required String userId,
    required String? shiftId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (k.isEmpty || shiftId == null) {
        await prefs.remove(kunci);
        return;
      }
      await prefs.setString(
        kunci,
        jsonEncode({'user': userId, 'shift': shiftId, 'isi': k.keJson()}),
      );
    } catch (e) {
      debugPrint('[keranjang] gagal disimpan: $e');
    }
  }

  /// Isi [k] dengan simpanan [userId] di [shiftId], kalau ada. Simpanan milik
  /// kasir atau shift lain dibuang. True kalau ada yang dipulihkan.
  static Future<bool> pulihkan(
    Keranjang k, {
    required String userId,
    required String? shiftId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final teks = prefs.getString(kunci);
      if (teks == null) return false;
      final data = jsonDecode(teks) as Map<String, dynamic>;
      if (shiftId == null ||
          data['user'] != userId ||
          data['shift'] != shiftId) {
        await prefs.remove(kunci);
        return false;
      }
      return k.pulihkanDari((data['isi'] as Map).cast<String, Object?>());
    } catch (e) {
      debugPrint('[keranjang] simpanan tidak terbaca: $e');
      return false;
    }
  }
}

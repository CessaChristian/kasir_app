import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/app_database.dart';
import 'app_constants.dart';

/// Info outlet yang tercetak di nota: alamat, nomor HP, WiFi.
///
/// Diubah owner dari Profil → Info Outlet dan ikut sinkron (tabel
/// `info_toko`). Nama toko sengaja tidak ada di sini (keputusan owner
/// 11 Nov 2026: tetap).
@immutable
class InfoNota {
  final String alamat;
  final String noHp;

  /// Kosong = baris WiFi tidak dicetak.
  final String wifiNama;
  final String wifiSandi;

  const InfoNota({
    required this.alamat,
    required this.noHp,
    required this.wifiNama,
    required this.wifiSandi,
  });

  /// Yang dipakai selama HP ini belum punya info outlet dari server —
  /// nilai yang tercetak sebelum fitur ini ada.
  static const bawaan = InfoNota(
    alamat: AppConstants.alamatNota,
    noHp: AppConstants.storePhone,
    wifiNama: AppConstants.wifiNama,
    wifiSandi: AppConstants.wifiSandi,
  );

  static const panjangAlamat = 64;
  static const panjangNoHp = 20;
  static const panjangWifi = 32;

  /// Info yang berlaku SEKARANG di HP ini. Struk di layar dan struk cetak
  /// membaca dari sini; isinya mengikuti database lewat [pantau].
  static final kini = ValueNotifier<InfoNota>(bawaan);

  static StreamSubscription<InfoTokoBaris?>? _langganan;

  /// Ikuti tabel `info_toko`: simpanan owner di HP ini maupun kiriman HP
  /// lain lewat sinkron langsung berlaku di [kini].
  static void pantau(AppDatabase db) {
    _langganan?.cancel();
    _langganan = db.pantauInfoToko().listen(
      (b) => kini.value = b == null ? bawaan : InfoNota.dariBaris(b),
      onError: (Object e) => debugPrint('[info nota] gagal dibaca: $e'),
    );
  }

  factory InfoNota.dariBaris(InfoTokoBaris b) => InfoNota(
    alamat: b.alamat,
    noHp: b.noHp,
    wifiNama: b.wifiNama,
    wifiSandi: b.wifiSandi,
  );

  /// Isian yang dirapikan: spasi tepi dibuang, spasi beruntun jadi satu.
  /// Sandi WiFi hanya dibuang spasi tepinya — spasi di tengah bisa disengaja.
  factory InfoNota.rapikan({
    required String alamat,
    required String noHp,
    required String wifiNama,
    required String wifiSandi,
  }) {
    String rapi(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');
    return InfoNota(
      alamat: rapi(alamat),
      noHp: rapi(noHp),
      wifiNama: rapi(wifiNama),
      wifiSandi: wifiSandi.trim(),
    );
  }

  static final _cetakable = RegExp(r'^[ -~]*$');
  static final _polaNoHp = RegExp(r'^[0-9+\- ]+$');

  /// Printer struk hanya mengenal huruf, angka, dan tanda baca dasar;
  /// selain itu tercetak "?".
  static String? _hurufAsing(String s) => _cetakable.hasMatch(s)
      ? null
      : 'Hanya huruf, angka, dan tanda baca biasa';

  String? get galatAlamat {
    if (alamat.isEmpty) return 'Alamat wajib diisi';
    if (alamat.length > panjangAlamat) return 'Maksimal $panjangAlamat huruf';
    return _hurufAsing(alamat);
  }

  String? get galatNoHp {
    if (noHp.isEmpty) return 'Nomor HP wajib diisi';
    if (noHp.length > panjangNoHp) return 'Maksimal $panjangNoHp angka';
    if (!_polaNoHp.hasMatch(noHp)) return 'Hanya angka, spasi, + dan -';
    return null;
  }

  String? get galatWifiNama {
    if (wifiNama.isEmpty && wifiSandi.isNotEmpty) {
      return 'Isi nama WiFi, atau kosongkan sandinya';
    }
    if (wifiNama.length > panjangWifi) return 'Maksimal $panjangWifi huruf';
    return _hurufAsing(wifiNama);
  }

  String? get galatWifiSandi {
    if (wifiSandi.length > panjangWifi) return 'Maksimal $panjangWifi huruf';
    return _hurufAsing(wifiSandi);
  }

  bool get sah =>
      galatAlamat == null &&
      galatNoHp == null &&
      galatWifiNama == null &&
      galatWifiSandi == null;

  @override
  bool operator ==(Object other) =>
      other is InfoNota &&
      other.alamat == alamat &&
      other.noHp == noHp &&
      other.wifiNama == wifiNama &&
      other.wifiSandi == wifiSandi;

  @override
  int get hashCode => Object.hash(alamat, noHp, wifiNama, wifiSandi);
}

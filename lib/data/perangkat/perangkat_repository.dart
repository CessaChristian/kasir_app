import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_service.dart';

/// "2 menit lalu", "3 hari lalu" — sejak [waktu] sampai [sekarang].
///
/// Dipakai pemilik untuk menilai mana HP yang masih dipakai dan mana yang
/// sudah lama diam. Angka pastinya tidak penting; yang penting bisa dibaca
/// sekilas sambil memutuskan HP mana yang dicabut.
String waktuRelatif(DateTime waktu, {DateTime? sekarang}) {
  final jarak = (sekarang ?? DateTime.now()).difference(waktu);

  if (jarak.isNegative || jarak.inSeconds < 60) return 'baru saja';
  if (jarak.inMinutes < 60) return '${jarak.inMinutes} menit lalu';
  if (jarak.inHours < 24) return '${jarak.inHours} jam lalu';
  if (jarak.inDays < 30) return '${jarak.inDays} hari lalu';
  final bulan = jarak.inDays ~/ 30;
  if (bulan < 12) return '$bulan bulan lalu';
  return '${jarak.inDays ~/ 365} tahun lalu';
}

/// Satu perangkat yang terdaftar boleh menyentuh data toko.
class Perangkat {
  final String id;
  final String nama;
  final bool aktif;
  final DateTime terakhirAktif;

  const Perangkat({
    required this.id,
    required this.nama,
    required this.aktif,
    required this.terakhirAktif,
  });

  factory Perangkat.dariBaris(Map<String, dynamic> b) => Perangkat(
        id: b['id'] as String,
        nama: (b['nama'] as String?) ?? 'Perangkat',
        aktif: (b['status'] as String?) == 'aktif',
        terakhirAktif:
            DateTime.parse(b['terakhir_aktif'] as String).toLocal(),
      );

  /// Ini perangkat yang sedang dipakai membaca daftarnya?
  bool get iniSaya =>
      id == SupabaseService.instance.client?.auth.currentUser?.id;
}

/// Keadaan perangkat INI menurut server.
enum StatusPerangkatIni {
  aktif,

  /// Terdaftar tapi dicabut pemilik. Sinkronnya akan ditolak.
  dicabut,

  /// Tidak ada barisnya di daftar — belum terdaftar, atau sudah dilupakan.
  takTerdaftar,

  /// Belum bisa dipastikan: offline, atau daftarnya belum dibuat di server.
  takDiketahui,
}

/// Pintu ke daftar perangkat di server.
///
/// ── KENAPA TIDAK IKUT SINKRONISASI ──
///
/// Mesin sinkron kita penuh aturan halus — menang-kalah, urutan induk-anak,
/// kegagalan sebagian — dan semuanya sudah teruji. Menambah tabel kesembilan
/// ke sana berarti mengaduk yang sudah benar demi layar administratif yang
/// wajar saja kalau butuh internet.
///
/// ── KENAPA SEMUA KEGAGALAN DITELAN ──
///
/// Daftar ini dibuat lewat berkas SQL terpisah yang dijalankan pemilik. Di
/// antara aplikasinya diperbarui dan SQL-nya dijalankan, tabel dan fungsinya
/// BELUM ADA — dan aplikasi tidak boleh rusak karenanya. Jadi kegagalan yang
/// berarti "belum disiapkan" diperlakukan sebagai "belum tahu", bukan galat.
class PerangkatRepository {
  PerangkatRepository._();
  static final PerangkatRepository instance = PerangkatRepository._();

  SupabaseClient? get _klien => SupabaseService.instance.client;

  /// True kalau server menyatakan perangkat ini DICABUT.
  ///
  /// Disiarkan supaya layar mana pun bisa menanggapinya tanpa perlu tahu
  /// siapa yang memeriksanya.
  final ValueNotifier<bool> dicabut = ValueNotifier(false);

  /// True kalau perangkat ini PUNYA identitas tapi belum ada di daftar.
  ///
  /// Terjadi pada HP yang sudah terpasang sebelum daftarnya dibuat di server,
  /// dan pada HP yang barisnya dilupakan pemilik. Keduanya perlu mendaftar
  /// ulang — dan aplikasinya yang menawarkan, bukan pemilik yang harus ingat.
  final ValueNotifier<bool> belumTerdaftar = ValueNotifier(false);

  /// Periksa keadaan perangkat ini dan siarkan kalau dicabut.
  ///
  /// SENGAJA hanya menyalakan penanda saat server berkata "dicabut" dengan
  /// jelas. "Tidak ada barisnya" TIDAK dianggap dicabut — itu keadaan normal
  /// setiap perangkat sebelum daftarnya dibuat di server, dan
  /// memperlakukannya sebagai pencabutan akan mengunci seluruh HP begitu
  /// aplikasinya diperbarui.
  Future<void> periksaStatusSaya() async {
    final status = await statusSaya();
    dicabut.value = status == StatusPerangkatIni.dicabut;
    belumTerdaftar.value = status == StatusPerangkatIni.takTerdaftar;
  }

  /// Galat yang berarti "daftarnya belum dibuat di server".
  static bool belumDisiapkan(Object e) {
    if (e is PostgrestException) {
      // PGRST202: fungsi tidak ditemukan. 42P01: tabel tidak ada.
      // 42883: fungsi tidak ada (dari Postgres langsung).
      const kode = {'PGRST202', '42P01', '42883', 'PGRST205'};
      if (kode.contains(e.code)) return true;
      final p = e.message.toLowerCase();
      return p.contains('does not exist') || p.contains('not find');
    }
    return false;
  }

  /// Nama tebakan untuk HP ini, mis. "Samsung SM-A155F".
  ///
  /// Sekadar titik awal — pemilik bisa menggantinya dari halaman Perangkat.
  /// Nama yang bisa dikenali jauh lebih berguna daripada deretan kode saat
  /// pemilik harus memutuskan HP mana yang dicabut.
  Future<String> tebakNama() async {
    try {
      if (Platform.isAndroid) {
        final i = await DeviceInfoPlugin().androidInfo;
        final merek = i.manufacturer.trim();
        final model = i.model.trim();
        final gabung = [
          if (merek.isNotEmpty) merek[0].toUpperCase() + merek.substring(1),
          if (model.isNotEmpty) model,
        ].join(' ');
        if (gabung.isNotEmpty) return gabung;
      } else if (Platform.isIOS) {
        final i = await DeviceInfoPlugin().iosInfo;
        if (i.name.isNotEmpty) return i.name;
      }
    } catch (_) {
      // Nama cuma hiasan; kegagalannya tidak boleh menggagalkan pendaftaran.
    }
    return 'Perangkat';
  }

  /// Daftarkan perangkat ini memakai kunci pemasangan.
  ///
  /// Mengembalikan false HANYA kalau server menolak kuncinya. "Belum
  /// disiapkan" dianggap berhasil: identitas perangkatnya sudah ada, dan
  /// barisnya menyusul begitu SQL-nya dijalankan.
  Future<bool> daftarkan(String kunci) async {
    final k = _klien;
    if (k == null) return true;
    try {
      await k.rpc('daftarkan_perangkat',
          params: {'p_kunci': kunci, 'p_nama': await tebakNama()});
      return true;
    } catch (e) {
      if (belumDisiapkan(e)) {
        debugPrint('[perangkat] daftar dilewati: daftarnya belum dibuat');
        return true;
      }
      if (e is PostgrestException && e.code == '28000') return false;
      debugPrint('[perangkat] daftar gagal: $e');
      return true;
    }
  }

  /// Daftarkan identitas yang SUDAH dimiliki perangkat ini.
  ///
  /// Sengaja TIDAK membuat identitas baru: setiap identitas yang ditinggalkan
  /// menjadi baris yatim di daftar pengguna server, dan HP yang mendaftar
  /// ulang berkali-kali akan meninggalkan tumpukan.
  Future<bool> daftarkanIdentitasIni(String kunci) async {
    final berhasil = await daftarkan(kunci);
    if (berhasil) await periksaStatusSaya();
    return berhasil;
  }

  /// Tandai perangkat ini masih dipakai. Dipanggil sesudah tiap sinkron.
  Future<void> hadir() async {
    final k = _klien;
    if (k == null) return;
    try {
      await k.rpc('perangkat_hadir');
    } catch (e) {
      if (!belumDisiapkan(e)) debugPrint('[perangkat] hadir gagal: $e');
    }
  }

  /// Keadaan perangkat ini menurut server.
  Future<StatusPerangkatIni> statusSaya() async {
    final k = _klien;
    final id = k?.auth.currentUser?.id;
    if (k == null || id == null) return StatusPerangkatIni.takDiketahui;
    try {
      final baris = await k
          .from('perangkat')
          .select('status')
          .eq('id', id)
          .maybeSingle();
      if (baris == null) return StatusPerangkatIni.takTerdaftar;
      return baris['status'] == 'aktif'
          ? StatusPerangkatIni.aktif
          : StatusPerangkatIni.dicabut;
    } catch (e) {
      return StatusPerangkatIni.takDiketahui;
    }
  }

  /// Semua perangkat, yang terbaru dipakai di atas.
  Future<List<Perangkat>> semua() async {
    final k = _klien;
    if (k == null) return const [];
    final baris = await k
        .from('perangkat')
        .select()
        .order('terakhir_aktif', ascending: false);
    return baris.map(Perangkat.dariBaris).toList();
  }

  /// Semua perubahan lewat fungsi di server, bukan tulis langsung ke tabel.
  ///
  /// Sempat ditulis langsung, dan akibatnya pemilik tidak bisa mengganti nama
  /// HP-nya sendiri: satu aturan tabel harus melayani dua hal dengan syarat
  /// berbeda — ganti nama (aman untuk diri sendiri) dan ubah status (tidak
  /// boleh untuk diri sendiri). Dipisah jadi dua fungsi, syaratnya jadi jelas.
  Future<void> ubahNama(String id, String nama) async {
    await _klien
        ?.rpc('ubah_nama_perangkat', params: {'p_id': id, 'p_nama': nama});
  }

  Future<void> ubahStatus(String id, {required bool aktif}) async {
    await _klien
        ?.rpc('ubah_status_perangkat', params: {'p_id': id, 'p_aktif': aktif});
  }

  Future<void> lupakan(String id) async {
    await _klien?.rpc('lupakan_perangkat', params: {'p_id': id});
  }
}

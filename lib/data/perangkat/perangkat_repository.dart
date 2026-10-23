import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_service.dart';
import 'kode_nota.dart';
import '../../utils/pesan_galat.dart';

/// Perangkat lain yang masih memegang sebuah shift, dan sudah berapa lama
/// ia tidak memberi kabar ke server.
typedef PemegangShift = ({String nama, Duration diam});

/// Satu perangkat yang terdaftar boleh menyentuh data toko.
class Perangkat {
  final String id;
  final String nama;
  final bool aktif;
  final DateTime terakhirAktif;
  final DateTime didaftarkan;

  /// Mis. "Xiaomi Redmi Note 12 · Android 13". Null kalau HP-nya belum
  /// pernah mengirim (APK lama, atau supabase/perangkat_model.sql belum
  /// dijalankan).
  final String? model;
  final bool tablet;

  /// Kapan HP ini terakhir selesai menarik data dengan bersih — tanpa galat
  /// dan tanpa baris tertahan. Null kalau belum pernah: APK lama, atau
  /// supabase/perangkat_tarik.sql belum dijalankan.
  ///
  /// Berbeda dari [terakhirAktif] ("HP masih dipakai"): HP yang tarikannya
  /// bermasalah tetap memberi kabar, tapi kolom ini tidak maju.
  final DateTime? terakhirTarik;

  /// Baris server yang ditolak database HP ini (lihat `BarisTertahan`).
  final int jumlahTertahan;

  const Perangkat({
    required this.id,
    required this.nama,
    required this.aktif,
    required this.terakhirAktif,
    required this.didaftarkan,
    this.model,
    this.tablet = false,
    this.terakhirTarik,
    this.jumlahTertahan = 0,
  });

  factory Perangkat.dariBaris(Map<String, dynamic> b) {
    final terakhir = DateTime.parse(b['terakhir_aktif'] as String).toLocal();
    final dibuat = b['dibuat_pada'] as String?;
    return Perangkat(
      id: b['id'] as String,
      nama: (b['nama'] as String?) ?? 'Perangkat',
      aktif: (b['status'] as String?) == 'aktif',
      terakhirAktif: terakhir,
      didaftarkan: dibuat == null ? terakhir : DateTime.parse(dibuat).toLocal(),
      model: b['model'] as String?,
      tablet: b['tablet'] == true,
      terakhirTarik: switch (b['terakhir_tarik']) {
        final String t => DateTime.parse(t).toLocal(),
        _ => null,
      },
      jumlahTertahan: (b['jumlah_tertahan'] as num?)?.toInt() ?? 0,
    );
  }

  /// HP yang dipakai tapi lebih dari ini tidak menerima data ditandai.
  ///
  /// Sehari: kasir yang aktif berjualan seharian tanpa menerima satu pun
  /// perubahan dari server (harga, produk dihapus, open bill HP lain) sudah
  /// patut dicek. Jauh lebih pendek dari [batasDiam] — HP ini jelas masih
  /// dipakai, masalahnya ada di tarikannya.
  static const batasTidakMenarik = Duration(days: 1);

  /// Masalah data HP ini untuk ditampilkan ke owner, atau null.
  ///
  /// Hanya untuk HP aktif yang TIDAK sedang ditandai [perluDicek]: HP yang
  /// diam seminggu sudah mendapat peringatannya sendiri.
  ({String judul, String catatan})? masalahData({
    DateTime? sekarang,
    String? idSaya,
  }) {
    if (!aktif || perluDicek(sekarang: sekarang, idSaya: idSaya)) return null;
    if (jumlahTertahan > 0) {
      return (
        judul: '$jumlahTertahan data tertahan di HP ini',
        catatan: 'Data dari server belum bisa disimpan. Perbarui aplikasi '
            'di HP ini ke versi terbaru.',
      );
    }
    final tarik = terakhirTarik;
    if (tarik == null) {
      return (
        judul: 'Belum pernah menerima data',
        catatan: 'Perbarui aplikasi di HP ini, lalu buka dan tarik layar '
            'untuk menyegarkan.',
      );
    }
    final lama = (sekarang ?? DateTime.now()).difference(tarik);
    if (lama <= batasTidakMenarik) return null;
    return (
      judul: 'Tidak menerima data ${lama.inDays} hari',
      catatan: 'HP ini dipakai, tapi datanya tidak terbarui. Buka aplikasinya '
          'di HP itu dan tarik layar untuk menyegarkan.',
    );
  }

  /// Perlu perhatian owner: diam seminggu, atau datanya bermasalah.
  bool perluPerhatian({DateTime? sekarang, String? idSaya}) =>
      perluDicek(sekarang: sekarang, idSaya: idSaya) ||
      masalahData(sekarang: sekarang, idSaya: idSaya) != null;

  /// Berapa lama HP aktif boleh diam sebelum ditandai perlu dicek.
  ///
  /// HP aktif yang lama tidak sinkron menahan batas "centang biru" buang
  /// sampah — selama ia tercatat aktif, data bekas hapusan tidak pernah
  /// dibuang. Diam beberapa hari tidak merugikan (kasir libur), tapi HP yang
  /// hilang atau rusak menahannya selamanya. Seminggu cukup untuk libur akhir
  /// pekan, dan cukup pendek supaya HP yang benar-benar hilang ketahuan.
  static const batasDiam = Duration(days: 7);

  /// HP ini aktif tapi sudah [batasDiam] atau lebih tidak sinkron?
  ///
  /// HP yang sedang membaca daftar tidak pernah ditandai — ia jelas sedang
  /// dipakai — begitu juga HP yang sudah dicabut, karena tidak lagi ikut
  /// menahan buang sampah. [idSaya] hanya untuk test.
  bool perluDicek({DateTime? sekarang, String? idSaya}) {
    final saya = idSaya ?? SupabaseService.instance.client?.auth.currentUser?.id;
    if (!aktif || id == saya) return false;
    return (sekarang ?? DateTime.now()).difference(terakhirAktif) >= batasDiam;
  }

  /// Berapa hari penuh HP ini tidak sinkron.
  int hariDiam({DateTime? sekarang}) =>
      (sekarang ?? DateTime.now()).difference(terakhirAktif).inDays;
}

/// Jawaban pendaftaran perangkat dengan kunci pemasangan
/// (`daftarkan_perangkat`, supabase/perangkat_aman.sql).
enum HasilKunci {
  diterima,
  salah,

  /// Lebih dari 20 kunci salah dalam sejam untuk seluruh toko.
  terlaluBanyak,

  /// HP ini dicabut pemilik: harus dipulihkan dari halaman Perangkat, bukan
  /// dengan kunci.
  dicabut,

  /// Identitas HP ini sudah dihapus server (HP dilupakan pemilik). Perlu
  /// identitas baru sebelum mendaftar.
  identitasHilang,

  /// Server tidak terjangkau atau galat lain.
  gagal,
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

  /// Untuk test: subkelas yang mengganti cara membaca & mengubah daftar.
  @visibleForTesting
  PerangkatRepository.untukTest();

  /// Id perangkat ini (identitas di server). Null kalau belum masuk.
  String? get idSaya => _klien?.auth.currentUser?.id;

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

  /// True kalau identitas HP ini sudah DIHAPUS server — HP dilupakan
  /// pemilik. HP ini kembali seperti HP baru: perlu identitas baru dan kunci
  /// pemasangan.
  final ValueNotifier<bool> identitasHilang = ValueNotifier(false);

  static const _brankas = FlutterSecureStorage();
  static const _kunciDicabut = 'perangkat_dicabut';

  /// Baca tanda "dicabut" yang tersimpan. Panggil sekali saat aplikasi
  /// dibuka, SEBELUM layar pertama.
  ///
  /// Dulu tanda ini hanya diingat selama aplikasinya terbuka. HP yang dicabut
  /// cukup dimatikan internetnya lalu dibuka ulang — server tidak bisa
  /// ditanya, tandanya hilang, dan HP itu bisa dipakai login dan berjualan
  /// lagi.
  Future<void> muatTandaDicabut() async {
    try {
      dicabut.value = await _brankas.read(key: _kunciDicabut) == '1';
    } catch (e) {
      debugPrint('[perangkat] tanda dicabut tak terbaca: $e');
    }
  }

  Future<void> _aturDicabut(bool nilai) async {
    dicabut.value = nilai;
    try {
      if (nilai) {
        await _brankas.write(key: _kunciDicabut, value: '1');
      } else {
        await _brankas.delete(key: _kunciDicabut);
      }
    } catch (e) {
      debugPrint('[perangkat] tanda dicabut tak tersimpan: $e');
    }
  }

  /// Periksa keadaan perangkat ini dan siarkan kalau dicabut.
  ///
  /// Penanda hanya diubah oleh jawaban yang JELAS. "Tidak tahu" (offline)
  /// membiarkan penanda apa adanya — dulu justru menghapus tanda dicabut,
  /// sehingga HP yang dicabut bisa dipakai lagi cukup dengan mematikan
  /// internet. "Tidak ada barisnya" TIDAK dianggap dicabut: itu keadaan
  /// normal HP yang belum terdaftar.
  Future<StatusPerangkatIni> periksaStatusSaya() async {
    final status = await statusSaya();
    switch (status) {
      case StatusPerangkatIni.dicabut:
        await _aturDicabut(true);
      case StatusPerangkatIni.aktif:
        await _aturDicabut(false);
        belumTerdaftar.value = false;
        identitasHilang.value = false;
      case StatusPerangkatIni.takTerdaftar:
        await _aturDicabut(false);
        belumTerdaftar.value = true;
      case StatusPerangkatIni.takDiketahui:
        break;
    }
    return status;
  }

  /// Tanya server keadaan HP ini sekarang (tombol "Periksa lagi").
  ///
  /// False kalau server tidak terjangkau. Identitas yang ditolak server
  /// berarti HP ini dilupakan pemilik.
  Future<bool> periksaKeServer() async {
    final layanan = SupabaseService.instance;
    if (!await layanan.pastikanTerhubung()) {
      if (layanan.sebabTerputus == SebabTerputus.ditolak) {
        await tandaiIdentitasHilang();
        return true;
      }
      return false;
    }
    // Tiket yang masih berlaku belum berarti server menjawab.
    return await periksaStatusSaya() != StatusPerangkatIni.takDiketahui;
  }

  /// Server menolak identitas HP ini — ia sudah dihapus (HP dilupakan
  /// pemilik). Tanda dicabut dilepas, karena HP yang dilupakan kembali
  /// seperti HP baru dan boleh mendaftar ulang dengan kunci.
  Future<void> tandaiIdentitasHilang() async {
    await _aturDicabut(false);
    identitasHilang.value = true;
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
  /// "Belum disiapkan" (SQL-nya belum dijalankan) dianggap diterima:
  /// identitasnya sudah ada, dan barisnya menyusul.
  Future<HasilKunci> daftarkan(String kunci) async {
    final k = _klien;
    if (k == null) return HasilKunci.diterima;
    try {
      final jawaban = await k.rpc('daftarkan_perangkat',
          params: {'p_kunci': kunci, 'p_nama': await tebakNama()});
      final hasil = hasilKunciDari(jawaban);
      if (hasil == HasilKunci.diterima) await _ambilKodeNota(k);
      return hasil;
    } catch (e) {
      if (belumDisiapkan(e)) {
        debugPrint('[perangkat] daftar dilewati: daftarnya belum dibuat');
        return HasilKunci.diterima;
      }
      if (e is PostgrestException) {
        // Server lama (sebelum perangkat_aman.sql) melempar kunci salah.
        if (e.code == '28000') return HasilKunci.salah;
        // Identitasnya sudah dihapus: baris perangkat tidak bisa merujuknya.
        if (e.code == '23503') return HasilKunci.identitasHilang;
      }
      debugPrint('[perangkat] daftar gagal: $e');
      return HasilKunci.gagal;
    }
  }

  /// Jawaban `daftarkan_perangkat` → [HasilKunci]. Server lama tidak
  /// menjawab apa pun kalau berhasil.
  @visibleForTesting
  static HasilKunci hasilKunciDari(Object? jawaban) => switch (jawaban) {
    null || 'ok' => HasilKunci.diterima,
    'kunci_salah' => HasilKunci.salah,
    'terlalu_banyak' => HasilKunci.terlaluBanyak,
    'dicabut' => HasilKunci.dicabut,
    _ => HasilKunci.gagal,
  };

  /// Daftarkan identitas yang SUDAH dimiliki perangkat ini.
  ///
  /// Sengaja TIDAK membuat identitas baru: setiap identitas yang ditinggalkan
  /// menjadi baris yatim di daftar pengguna server, dan HP yang mendaftar
  /// ulang berkali-kali akan meninggalkan tumpukan.
  Future<HasilKunci> daftarkanIdentitasIni(String kunci) async {
    final hasil = await daftarkan(kunci);
    if (hasil == HasilKunci.diterima || hasil == HasilKunci.dicabut) {
      await periksaStatusSaya();
    }
    return hasil;
  }

  /// Tandai perangkat ini masih dipakai. Dipanggil sesudah tiap sinkron.
  /// [shiftId] adalah shift yang sedang dipegang perangkat ini, atau null
  /// kalau tidak sedang memegang apa pun — owner, atau kasir yang sudah
  /// keluar. Server memakainya untuk menolak pengakhiran shift yang masih
  /// dipakai perangkat lain.
  ///
  /// [tarikBersih]: tarikan putaran ini selesai tanpa galat DAN tanpa baris
  /// tertahan — hanya itu yang memajukan `terakhir_tarik`, patokan buang
  /// sampah dan "Data terakhir diterima" di halaman Perangkat. Kabar dari
  /// sentuhan layar tidak mengirimnya. [tertahan] null = tidak dilaporkan.
  Future<void> hadir(
    String? shiftId, {
    bool tarikBersih = false,
    int? tertahan,
  }) async {
    final k = _klien;
    if (k == null) return;
    try {
      try {
        await k.rpc('perangkat_hadir', params: {
          'p_shift_id': shiftId,
          if (tarikBersih) 'p_tarik_bersih': true,
          'p_tertahan': ?tertahan,
        });
      } catch (e) {
        // supabase/perangkat_tarik.sql belum dijalankan: fungsinya belum
        // menerima parameter baru. Kabar "masih dipakai" tetap harus sampai
        // — pemegang shift dan sesi diam bergantung padanya.
        if (!belumDisiapkan(e) || (!tarikBersih && tertahan == null)) rethrow;
        await k.rpc('perangkat_hadir', params: {'p_shift_id': shiftId});
      }
    } catch (e) {
      if (!belumDisiapkan(e)) debugPrint('[perangkat] hadir gagal: $e');
      return;
    }
    hadirTerakhir = DateTime.now();
    await _catatModel(k);
    if (!_kodeTerambil) await _ambilKodeNota(k);
  }

  /// Kapan [hadir] terakhir sampai ke server, atau null.
  DateTime? hadirTerakhir;

  /// Sudah mengambil huruf nota sejak aplikasi dibuka?
  bool _kodeTerambil = false;

  /// Ambil huruf perangkat ini untuk nomor nota (`perangkat.kode`). Gagal
  /// atau kolomnya belum ada (nomor_nota.sql belum dijalankan) = dicoba lagi
  /// di sinkron berikutnya; nota tetap terbit memakai kode lama.
  Future<void> _ambilKodeNota(SupabaseClient k) async {
    final id = k.auth.currentUser?.id;
    if (id == null) return;
    try {
      final baris = await k
          .from('perangkat')
          .select('kode')
          .eq('id', id)
          .maybeSingle();
      final kode = baris?['kode'] as String?;
      if (kode == null) return;
      await KodeNota.simpanDariServer(kode);
      _kodeTerambil = true;
    } catch (e) {
      debugPrint('[perangkat] kode nota gagal diambil: $e');
    }
  }

  /// Sudah mengirim model sejak aplikasi dibuka?
  bool _modelTercatat = false;

  /// Kirim model & jenis HP ini sekali per aplikasi dibuka — begitu HP lama
  /// ikut terisi tanpa perlu mendaftar ulang. Gagal = dicoba lagi di
  /// sinkron berikutnya; "belum disiapkan" (perangkat_model.sql belum
  /// dijalankan) juga, tanpa mengganggu apa pun.
  Future<void> _catatModel(SupabaseClient k) async {
    if (_modelTercatat) return;
    try {
      final (model, tablet) = await infoModel();
      await k.rpc(
        'catat_model_perangkat',
        params: {'p_model': model, 'p_tablet': tablet},
      );
      _modelTercatat = true;
    } catch (e) {
      if (!belumDisiapkan(e)) debugPrint('[perangkat] catat model gagal: $e');
    }
  }

  /// Model dan jenis HP ini, mis. ("Xiaomi Redmi Note 12 · Android 13",
  /// false). Tablet = sisi layar terpendek minimal 600dp — batas yang sama
  /// dengan pedoman Android untuk tata letak tablet.
  Future<(String?, bool)> infoModel() async {
    String? model;
    try {
      if (Platform.isAndroid) {
        final i = await DeviceInfoPlugin().androidInfo;
        final nama = await tebakNama();
        model = '$nama · Android ${i.version.release}';
      } else if (Platform.isIOS) {
        final i = await DeviceInfoPlugin().iosInfo;
        model = '${i.model} · iOS ${i.systemVersion}';
      }
    } catch (_) {
      // Model cuma keterangan; kegagalannya tidak boleh mengganggu sinkron.
    }
    final layar = PlatformDispatcher.instance.views.firstOrNull;
    final tablet = layar != null &&
        layar.physicalSize.shortestSide / layar.devicePixelRatio >= 600;
    return (model, tablet);
  }

  /// Perangkat AKTIF selain perangkat ini yang masih memegang shift ini —
  /// kosong kalau tidak ada. Perangkat yang 15 menit tidak memberi kabar
  /// tidak dihitung (supabase/shift_pemegang_basi.sql).
  ///
  /// Dijawab server, bukan dihitung di sini, supaya jawabannya sama untuk
  /// siapa pun yang bertanya. MELEMPAR kalau tidak bisa bertanya — pemanggil
  /// yang memutuskan apa artinya, karena "tidak tahu" dan "tidak ada" adalah
  /// dua hal yang sangat berbeda saat hendak menutup shift.
  Future<List<PemegangShift>> pemegangShiftLain(String shiftId) async {
    final k = _klien;
    if (k == null) throw StateError(pesanTakTersambung);
    final hasil = await k.rpc(
      'pemegang_shift_lain',
      params: {'p_shift_id': shiftId},
    );
    return [
      for (final b in hasil as List)
        (
          nama: (b['nama'] as String?) ?? 'Perangkat',
          diam: Duration(seconds: (b['diam_detik'] as num).toInt()),
        ),
    ];
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

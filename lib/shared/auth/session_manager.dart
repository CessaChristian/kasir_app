import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/app_database.dart';
import '../../data/db.dart';
import '../../features/auth/models/auth_session.dart';

/// Singleton untuk manajemen authentication session.
///
/// Session di-cache in-memory + persist ke SharedPreferences.
/// PENTING: `role` dan `permissions` dari storage TIDAK dipercaya;
/// SessionManager re-validate ke DB saat `restoreSession()` untuk
/// mencegah privilege escalation via tamper SharedPreferences (S6).
///
/// Session expire setelah 12 jam (S7), atau lebih cepat untuk kasir yang
/// memegang shift tapi [batasDiam] tidak memberi kabar ke server.
class SessionManager {
  static final SessionManager instance = SessionManager._();
  SessionManager._();

  /// Override DB untuk unit test. JANGAN dipakai di production code.
  static AppDatabase? dbOverride;
  AppDatabase get _dbx => dbOverride ?? db;

  static const String _sessionKey = 'auth_session';

  AuthSession? _currentSession;

  /// Set the current session dan persist ke storage.
  ///
  /// Ikut dihitung sebagai kabar ([catatKabar]): sesi hanya diubah saat
  /// orangnya memakai HP ini (login, buka/tutup shift) atau saat sinkron.
  /// Tanpa ini, kasir yang membuka shift sesudah lama diam di halaman tanpa
  /// shift langsung dikeluarkan pada pemeriksaan berikutnya.
  Future<void> setSession(AuthSession session) async {
    _currentSession = session;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, json.encode(session.toJson()));
    await catatKabar();
    // Login juga sentuhan — owner tidak boleh langsung dikeluarkan karena
    // sentuhan terakhirnya tercatat dari sesi sebelumnya.
    catatSentuhan();
  }

  /// Kasir yang memegang shift dan selama ini tidak memberi kabar ke server
  /// harus login ulang (keputusan owner 2026-10-20).
  ///
  /// ── KENAPA ──
  ///
  /// Server menolak "Tutup shift" selama ada perangkat lain yang memegang
  /// shift itu, dan perangkat yang mati atau aplikasinya digeser dari
  /// riwayat tidak sempat melepasnya. Maka server berhenti menghitung
  /// perangkat yang [batasDiam] tidak memberi kabar
  /// (supabase/shift_pemegang_basi.sql — angkanya HARUS sama). HP itu
  /// sendiri juga harus menganggap sesinya berakhir; kalau tidak, ia terus
  /// berjualan di shift yang menurut server sudah tidak dipegangnya.
  ///
  /// Shift-nya TIDAK ditutup — login lagi melanjutkannya. Owner tidak
  /// terkena: ia tidak memegang shift.
  static const batasDiam = Duration(minutes: 15);

  static const pesanDiam =
      'Sesi berakhir karena 15 menit tidak aktif. Silakan masuk lagi.';

  static const String _kunciKabar = 'kabar_terakhir';

  /// Terakhir kali HP ini memberi kabar — lihat [catatKabar].
  DateTime? _kabarTerakhir;

  /// Catat bahwa HP ini masih hidup dan dipakai.
  ///
  /// Dipanggil setiap putaran sinkron selesai — BERHASIL ATAU TIDAK — dan
  /// saat layar disentuh ([catatSentuhan]). Internet mati sengaja tidak
  /// dihitung diam (keputusan owner): aplikasinya tetap terbuka dan mencoba,
  /// kasir harus tetap bisa berjualan offline. Yang dihitung diam hanya saat
  /// sinkron tidak berjalan DAN layar tidak disentuh: aplikasi di latar
  /// belakang, layar mati, atau keranjang berisi yang ditinggal.
  ///
  /// Disimpan juga ke storage supaya aplikasi yang digeser dari riwayat lalu
  /// dibuka lagi tahu sudah berapa lama ia diam.
  Future<void> catatKabar([DateTime? waktu]) async {
    _kabarTerakhir = waktu ?? DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kunciKabar, _kabarTerakhir!.toIso8601String());
  }

  /// Terakhir kali layar disentuh, atau null kalau belum sejak aplikasi
  /// dibuka. Hanya di memori.
  DateTime? get sentuhanTerakhir => _sentuhanTerakhir;
  DateTime? _sentuhanTerakhir;

  /// Sentuhan di layar dihitung kabar juga (keputusan owner 2026-10-23).
  ///
  /// Dulu kabar hanya dicatat sinkron, padahal sinkron ditahan selama
  /// keranjang berisi: kasir yang sedang melayani pesanan dikeluarkan paksa
  /// setelah 15 menit dan pesanannya hilang — terbukti di HP. HP yang
  /// benar-benar ditinggal tetap dikeluarkan.
  ///
  /// Dipanggil di setiap sentuhan, jadi harus murah: jamnya dicatat di
  /// memori, dan baru ditulis ke penyimpanan kalau kabar terakhir sudah
  /// lewat [jedaSimpanSentuhan].
  void catatSentuhan([DateTime? waktu]) {
    final kini = waktu ?? DateTime.now();
    _sentuhanTerakhir = kini;
    final tersimpan = _sentuhanTersimpan;
    // Selisih mutlak: jam HP yang dimundurkan tidak boleh membuat sentuhan
    // berhenti tersimpan.
    if (tersimpan == null ||
        kini.difference(tersimpan).abs() >= jedaSimpanSentuhan) {
      _sentuhanTersimpan = kini;
      unawaited(_simpanSentuhan(kini));
    }
    final kabar = _kabarTerakhir;
    if (kabar != null && kini.difference(kabar) < jedaSimpanSentuhan) return;
    unawaited(catatKabar(kini));
  }

  DateTime? _sentuhanTersimpan;
  static const String _kunciSentuhan = 'sentuhan_terakhir';

  /// Disimpan supaya HP owner yang ditinggal lalu aplikasinya digeser dari
  /// riwayat tetap ketahuan sudah lama tidak disentuh saat dibuka lagi.
  Future<void> _simpanSentuhan(DateTime waktu) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kunciSentuhan, waktu.toIso8601String());
  }

  static const jedaSimpanSentuhan = Duration(minutes: 1);

  /// Akhiri sesi kalau kasir yang memegang shift sudah [batasDiam] tidak
  /// memberi kabar. True kalau sesinya diakhiri; [sesiDicabut] membawa
  /// [pesanDiam] ke layar.
  ///
  /// Dipanggil saat aplikasi dibuka, saat kembali dari latar belakang
  /// (SEBELUM sinkron, yang akan mencatat kabar baru), dan tiap menit selama
  /// aplikasi di depan — untuk keranjang yang dibiarkan berisi.
  Future<bool> akhiriKalauDiam({DateTime? sekarang}) async {
    final sesi = _currentSession;
    if (sesi != null && sesi.isOwner) {
      return _akhiriOwnerKalauDitinggal(sekarang ?? DateTime.now());
    }
    final kabar = _kabarTerakhir;
    if (sesi == null || !sesi.isCashier || sesi.shiftId == null) return false;
    if (kabar == null) return false;
    if ((sekarang ?? DateTime.now()).difference(kabar) < batasDiam) {
      return false;
    }
    await clearSession();
    sesiDicabut.value = pesanDiam;
    return true;
  }

  static const pesanDiamOwner =
      'Sesi owner berakhir karena 15 menit tidak disentuh. Silakan masuk lagi.';

  /// Owner: HANYA sentuhan yang dihitung (keputusan owner 2026-10-24).
  ///
  /// Tujuannya berbeda dari aturan kasir: mencegah orang lain memakai HP
  /// owner yang ditinggal dalam keadaan terbuka — membuka Kelola Kasir atau
  /// mengubah harga. Sinkron sengaja tidak dihitung: ia berjalan tiap lima
  /// menit selama aplikasi terbuka, jadi aturannya tidak akan pernah berlaku.
  Future<bool> _akhiriOwnerKalauDitinggal(DateTime sekarang) async {
    final sentuh = _sentuhanTerakhir;
    if (sentuh == null || sekarang.difference(sentuh) < batasDiam) {
      return false;
    }
    await clearSession();
    sesiDicabut.value = pesanDiamOwner;
    return true;
  }

  /// Clear current session.
  Future<void> clearSession() async {
    _currentSession = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
  }

  /// Restore session dari storage.
  ///
  /// Flow validasi:
  /// 1. Baca JSON dari SharedPreferences
  /// 2. Cek expiration (S7) — kalau expired → clear
  /// 3. Re-query user dari DB (S6) — kalau hilang/nonaktif → clear
  /// 4. Overwrite `role` dan `permissions` dari DB — TIDAK percaya nilai di storage
  Future<void> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionJson = prefs.getString(_sessionKey);
    final kabar = prefs.getString(_kunciKabar);
    _kabarTerakhir = kabar == null ? null : DateTime.tryParse(kabar);
    final sentuhan = prefs.getString(_kunciSentuhan);
    _sentuhanTerakhir = sentuhan == null ? null : DateTime.tryParse(sentuhan);

    if (sessionJson == null) return;

    AuthSession session;
    try {
      final sessionMap = json.decode(sessionJson) as Map<String, dynamic>;
      session = AuthSession.fromJson(sessionMap);
    } catch (_) {
      await clearSession();
      return;
    }

    // S7: cek expiration
    if (session.isExpired) {
      await clearSession();
      return;
    }

    // S6: re-validate user dari DB — JANGAN percaya role/permissions di storage
    try {
      final user = await (_dbx.select(_dbx.users)
            ..where((u) => u.id.equals(session.userId))
            ..limit(1))
          .getSingleOrNull();

      if (user == null || !user.isActive || user.deletedAt != null) {
        // Akun dinonaktifkan/dihapus (atau barisnya tidak ada) setelah sesi
        // dibuat
        await clearSession();
        return;
      }

      // Refresh permissions dari DB
      final freshPermissions = await _getUserPermissionsFromDb(user.id, user.role);

      // Overwrite role + permissions dengan nilai DB (anti-tamper)
      _currentSession = session.copyWith(
        username: user.username,
        role: user.role,
        permissions: freshPermissions,
      );

      // Sinkronkan storage agar konsisten dengan DB
      await prefs.setString(_sessionKey, json.encode(_currentSession!.toJson()));

      // Belum pernah tercatat = baru dipasang APK yang mengenal aturan ini;
      // hitungannya dimulai sekarang, bukan langsung mengeluarkan kasirnya.
      if (_kabarTerakhir == null) await catatKabar();
      await akhiriKalauDiam();
    } catch (_) {
      // DB error saat restore → clear session, user perlu login ulang
      await clearSession();
    }
  }

  /// Bertambah setiap kali isi sesi yang sedang berjalan BERUBAH: daftar
  /// izinnya, atau namanya diganti owner.
  ///
  /// Layar yang menampilkan menu & nama mendengarkan ini supaya ikut digambar
  /// ulang. Tanpa itu, perubahan yang baru turun dari server baru terlihat
  /// setelah pengguna keluar dan masuk lagi.
  final ValueNotifier<int> sesiBerubah = ValueNotifier(0);

  /// Baca ulang izin sesi yang sedang berjalan dari database.
  ///
  /// ── KENAPA PERLU ──
  ///
  /// Daftar izin dibaca SEKALI saat login lalu disimpan di dalam sesi.
  /// Sinkronisasi memperbarui tabelnya, tapi sesi yang sedang berjalan tidak
  /// tahu apa-apa. Akibatnya membingungkan di lapangan: pemilik bilang "sudah
  /// saya beri izin", kasir menyegarkan, dan tombolnya tetap tidak muncul —
  /// baru muncul setelah ia keluar dan masuk lagi, tanpa ada yang memberi tahu
  /// bahwa itu syaratnya.
  ///
  /// Dipanggil setiap kali sinkronisasi berhasil. Owner sengaja dilewati:
  /// izinnya tidak pernah berasal dari tabel, [hasPermission] selalu
  /// menjawab true untuknya.
  Future<void> muatUlangIzin() async {
    final sesi = _currentSession;
    if (sesi == null || sesi.isOwner) return;

    List<String> baru;
    try {
      baru = await _getUserPermissionsFromDb(sesi.userId, sesi.role);
    } catch (_) {
      // Gagal membaca bukan alasan untuk mencabut izin yang sedang berlaku.
      return;
    }

    if (baru.toSet().length == sesi.permissions.toSet().length &&
        baru.toSet().containsAll(sesi.permissions)) {
      return; // tidak berubah — jangan menggambar ulang layar tanpa alasan
    }

    _currentSession = sesi.copyWith(permissions: baru);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _sessionKey, json.encode(_currentSession!.toJson()));
    sesiBerubah.value++;
  }

  /// Berisi alasan kalau sesi yang sedang berjalan DICABUT dari jarak jauh,
  /// atau null selama sesinya masih sah.
  ///
  /// Layar yang sedang tampil mendengarkan ini lalu memaksa kembali ke halaman
  /// login. Alasannya ikut dibawa supaya pengguna diberi tahu APA yang
  /// terjadi — dilempar ke layar login tanpa penjelasan membuatnya mengira
  /// aplikasinya rusak dan mencoba masuk berulang kali.
  final ValueNotifier<String?> sesiDicabut = ValueNotifier(null);

  /// Periksa ulang apakah akun yang sedang login masih boleh dipakai.
  ///
  /// ── KENAPA PERLU ──
  ///
  /// `is_active` hanya diperiksa di dua tempat: saat login, dan di
  /// [restoreSession] yang HANYA berjalan sekali di `main()`. Selama sesi
  /// berlangsung tidak ada satu pun kode yang memeriksanya lagi.
  ///
  /// Akibatnya penonaktifan kasir nyaris tidak berguna: pemilik mencabut
  /// akses, datanya sampai ke HP kasir lewat sinkronisasi — dan kasirnya
  /// TETAP bisa berjualan tanpa batas waktu selama aplikasinya tidak ditutup.
  /// Menekan tombol Home pun tidak cukup; `restoreSession` baru jalan lagi
  /// kalau proses aplikasinya benar-benar mati.
  ///
  /// Dipanggil setiap kali sinkronisasi berhasil, jadi pencabutan berlaku
  /// dalam hitungan menit tanpa kasir perlu melakukan apa pun.
  Future<void> periksaAkunMasihBerlaku() async {
    final sesi = _currentSession;
    if (sesi == null) return;

    User? user;
    try {
      user = await (_dbx.select(_dbx.users)
            ..where((u) => u.id.equals(sesi.userId))
            ..limit(1))
          .getSingleOrNull();
    } catch (_) {
      // Gagal membaca bukan alasan untuk mengeluarkan orang yang sedang
      // bekerja. Kalau memang dicabut, putaran berikutnya akan menangkapnya.
      return;
    }

    final alasan = user == null
        ? 'Akun Anda sudah tidak ada.'
        : user.deletedAt != null
        ? 'Akun Anda dihapus oleh pemilik.'
        : !user.isActive
            ? 'Akses Anda dinonaktifkan oleh pemilik.'
            : null;
    if (alasan == null) {
      // Owner mengganti nama akun ini dari HP lain: nama di menu ikut
      // berganti tanpa perlu login ulang.
      if (user!.username != sesi.username) {
        await setSession(sesi.copyWith(username: user.username));
        sesiBerubah.value++;
      }
      return;
    }

    await clearSession();
    sesiDicabut.value = alasan;
  }

  /// Ganti shift berjalan di sesi ini — sesudah kasir membuka (id) atau
  /// menutup (null) shift. Layar yang mendengarkan [sesiBerubah] ikut
  /// digambar ulang.
  Future<void> aturShift(String? shiftId) async {
    final sesi = _currentSession;
    if (sesi == null || sesi.shiftId == shiftId) return;
    await setSession(sesi.denganShift(shiftId));
    sesiBerubah.value++;
  }

  /// Berisi pesan kalau shift yang sedang dipegang HP ini DITUTUP dari
  /// perangkat lain; layar menampilkannya lalu mengosongkannya kembali.
  final ValueNotifier<String?> shiftDitutupDariLuar = ValueNotifier(null);

  /// Berisi pesan kalau shift HP ini DIGABUNG server ke shift lain akun yang
  /// sama; layar menampilkannya lalu mengosongkannya kembali.
  final ValueNotifier<String?> shiftDigabung = ValueNotifier(null);

  /// Lepaskan shift dari sesi ini kalau shiftnya sudah ditutup dari
  /// perangkat lain.
  ///
  /// ── KENAPA PERLU ──
  ///
  /// Satu shift bisa dipegang lebih dari satu HP — disengaja, supaya kasir
  /// yang berpindah perangkat tidak melahirkan shift kedua. Akibatnya "Tutup
  /// shift" di satu HP ikut menutup shift yang masih dipakai HP satunya.
  ///
  /// Tanpa pemeriksaan ini HP itu tidak diberi tahu apa-apa: penjualannya
  /// tetap berhasil dan transaksinya menempel ke shift yang sudah tutup.
  /// Rekapnya lalu memuat penjualan SESUDAH jam tutupnya sendiri — sudah
  /// terbukti terjadi di emulator, bukan dugaan.
  ///
  /// Sejak v37 kasirnya TIDAK dikeluarkan dari akun: login dan shift sudah
  /// terpisah, jadi cukup shiftnya yang dilepas — kasir tetap di dalam dan
  /// bisa membuka shift baru.
  ///
  /// Gagal membaca sengaja diam: kasir yang sedang melayani tidak boleh
  /// diganggu hanya karena satu kueri tersendat.
  Future<void> periksaShiftMasihBerjalan({int sisaGabungan = 10}) async {
    final sesi = _currentSession;
    final shiftId = sesi?.shiftId;
    if (sesi == null || shiftId == null) return;

    Shift? shift;
    try {
      shift = await (_dbx.select(_dbx.shifts)
            ..where((s) => s.id.equals(shiftId))
            ..limit(1))
          .getSingleOrNull();
    } catch (_) {
      return;
    }

    // Shift yang belum tersinkron ke sini belum tentu sudah ditutup — barisnya
    // memang belum sampai. Yang dijadikan alasan hanya yang JELAS tertutup.
    if (shift == null || (shift.endAt == null && shift.deletedAt == null)) {
      return;
    }

    // Digabung server ke shift akun yang sama yang lebih dulu sampai
    // (supabase/shift_gabung.sql): kasir tetap berjualan, sesinya pindah ke
    // shift tujuan. Tujuannya sendiri diperiksa di putaran ini juga — bisa
    // saja sudah ditutup HP lain.
    final tujuan = shift.digabungKe;
    if (tujuan != null && sisaGabungan > 0) {
      await aturShift(tujuan);
      shiftDigabung.value =
          'Shift ini digabung dengan shift yang lebih dulu dibuka akun ini '
          'di perangkat lain. Penjualan tetap tercatat.';
      return periksaShiftMasihBerjalan(sisaGabungan: sisaGabungan - 1);
    }

    await aturShift(null);
    shiftDitutupDariLuar.value =
        'Shift ini sudah ditutup dari perangkat lain. Buka shift baru untuk '
        'melanjutkan.';
  }

  /// Dipanggil layar setelah selesai memindahkan pengguna ke halaman login.
  void tandaiPencabutanSudahDitangani() => sesiDicabut.value = null;

  /// Helper: ambil permissions dari DB.
  Future<List<String>> _getUserPermissionsFromDb(
      String userId, String role) async {
    if (role == 'owner') {
      final all = await _dbx.select(_dbx.permissions).get();
      return all
          .map((p) => p.code)
          .where((k) => !izinBukanUntukOwner.contains(k))
          .toList();
    }
    final perms = await (_dbx.select(_dbx.userPermissions)
          ..where((up) => up.userId.equals(userId))
          ..where((up) => up.enabled.equals(true)))
        .get();
    return perms.map((p) => p.permissionCode).toList();
  }

  AuthSession? get currentSession => _currentSession;
  bool get isLoggedIn => _currentSession != null;
  bool get isOwner => _currentSession?.isOwner ?? false;
  bool get isCashier => _currentSession?.isCashier ?? false;

  /// Izin yang TIDAK pernah dimiliki owner, sekalipun ia pemilik toko.
  ///
  /// ── KENAPA ADA PENGECUALIAN ──
  ///
  /// Owner tidak menjalankan shift — `auth_repository.dart` memang tidak
  /// pernah membukakan shift untuknya. Tapi menjual TIDAK butuh shift:
  /// `createSale` menerima `shiftId` yang boleh kosong. Jadi selama owner
  /// lolos semua izin, menu Kasir tetap muncul di HP-nya, dan transaksi yang
  /// dibuat di sana tersimpan TANPA shift — tidak masuk laporan shift mana
  /// pun, dan tidak terhitung di rekap kasir siapa pun.
  ///
  /// Itu juga sumber nomor nota kembar: nomornya dihitung dari jumlah
  /// transaksi hari ini di perangkat masing-masing, jadi dua perangkat yang
  /// sama-sama bisa menjual pasti bertabrakan cepat atau lambat.
  ///
  /// Dibuat daftar, bukan satu `if`, supaya kalau nanti ada izin lain yang
  /// juga tidak masuk akal untuk owner, tempat menambahkannya sudah jelas.
  static const izinBukanUntukOwner = <String>{
    'create_transaction',
    'open_close_shift',
  };

  /// Check permission. Owner always returns true, KECUALI
  /// [izinBukanUntukOwner].
  ///
  /// Untuk owner jawabannya TIDAK boleh diambil dari daftar izin di sesinya.
  /// Daftar itu diisi seluruh kode yang ada di tabel `permissions`, jadi ia
  /// memuat `create_transaction` juga — versi pertama tambalan ini membaca
  /// daftar tersebut dan akibatnya tidak mengubah apa pun.
  bool hasPermission(String permissionCode) {
    if (_currentSession == null) return false;
    if (_currentSession!.isOwner) {
      return !izinBukanUntukOwner.contains(permissionCode);
    }
    return _currentSession!.permissions.contains(permissionCode);
  }

  void requireLoggedIn() {
    if (!isLoggedIn) {
      throw StateError('Sesi sudah berakhir. Silakan masuk lagi.');
    }
  }

  void requireOwner() {
    requireLoggedIn();
    if (!isOwner) throw IzinDitolak('Hanya owner yang boleh melakukan ini.');
  }

  void requirePermission(String permissionCode) {
    requireLoggedIn();
    if (!hasPermission(permissionCode)) {
      throw IzinDitolak(
        'Akun ini tidak punya izin untuk melakukan ini. '
        'Minta owner mengaktifkannya.',
        kode: permissionCode,
      );
    }
  }

  String? get currentUserId => _currentSession?.userId;

  // =====================================
  // Context-aware permission (Phase 1 multi-business)
  // =====================================

  /// Nama lama dari [hasPermission]. Keduanya kini menjawab dari sumber yang
  /// SAMA.
  ///
  /// ── KENAPA INI DULU BERBEDA, DAN KENAPA ITU BERBAHAYA ──
  ///
  /// Dulu fungsi ini membaca matriks role PATEN, sedangkan [hasPermission]
  /// membaca `user_permissions` yang bisa diatur owner. Dua fungsi bernama
  /// mirip, menjawab pertanyaan yang sama, dari sumber berbeda.
  ///
  /// Akibatnya nyata dan membingungkan: menu "Pantau Shift" dijaga fungsi ini,
  /// sedangkan menu Produk/Kasir/Riwayat/Laporan dijaga [hasPermission]. Owner
  /// yang menyalakan izin `view_shift_reports` di halaman Kelola Izin melihat
  /// tombolnya TETAP tidak muncul — karena yang memeriksa bukan tabel yang
  /// baru saja ia ubah. Tidak ada error, tidak ada penjelasan.
  ///
  /// Dibiarkan sebagai penerus panggilan, bukan dihapus, supaya pemanggil yang
  /// ada tidak perlu diubah sekaligus. Untuk kode baru pakai [hasPermission].
  bool hasCurrentPermission(String permission) => hasPermission(permission);
}

/// Akun yang sedang masuk tidak berhak melakukan sesuatu. Pesannya siap
/// ditampilkan; [kode] = izin yang kurang (null untuk aksi khusus owner),
/// supaya halaman bisa menyebut nama izinnya.
class IzinDitolak extends StateError {
  final String? kode;
  IzinDitolak(super.message, {this.kode});
}

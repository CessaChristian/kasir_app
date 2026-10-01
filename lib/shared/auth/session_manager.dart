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
/// Session expire setelah 12 jam (S7).
class SessionManager {
  static final SessionManager instance = SessionManager._();
  SessionManager._();

  /// Override DB untuk unit test. JANGAN dipakai di production code.
  static AppDatabase? dbOverride;
  AppDatabase get _dbx => dbOverride ?? db;

  static const String _sessionKey = 'auth_session';

  AuthSession? _currentSession;

  /// Set the current session dan persist ke storage.
  Future<void> setSession(AuthSession session) async {
    _currentSession = session;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, json.encode(session.toJson()));
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

      if (user == null || !user.isActive) {
        // User dihapus atau dinonaktifkan setelah session dibuat
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
        ? 'Akun Anda sudah dihapus.'
        : user.deletedAt != null
            ? 'Akun Anda sudah dihapus.'
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

  /// Keluarkan kasir kalau shiftnya sudah diakhiri dari perangkat lain.
  ///
  /// ── KENAPA PERLU ──
  ///
  /// Satu shift kini bisa dipegang lebih dari satu HP — disengaja, supaya
  /// kasir yang berpindah perangkat tidak melahirkan shift kedua. Tapi
  /// akibatnya menekan "Akhiri Shift" di satu HP ikut menutup shift yang
  /// masih dipakai HP satunya.
  ///
  /// Tanpa pemeriksaan ini HP itu tidak diberi tahu apa-apa: menunya masih
  /// lengkap, penjualannya tetap berhasil, dan transaksinya menempel ke shift
  /// yang sudah tutup. Rekapnya lalu memuat penjualan yang terjadi SESUDAH
  /// jam tutupnya sendiri — sudah terbukti terjadi di emulator, bukan dugaan.
  ///
  /// Gagal membaca sengaja diam: kasir yang sedang melayani tidak boleh
  /// dilempar keluar hanya karena satu kueri tersendat.
  Future<void> periksaShiftMasihBerjalan() async {
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

    await clearSession();
    sesiDicabut.value = 'Shift ini sudah diakhiri dari perangkat lain. '
        'Masuk lagi untuk membuka shift baru.';
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
    if (!isLoggedIn) throw StateError('User must be logged in');
  }

  void requireOwner() {
    requireLoggedIn();
    if (!isOwner) throw StateError('Owner access required');
  }

  void requirePermission(String permissionCode) {
    requireLoggedIn();
    if (!hasPermission(permissionCode)) {
      throw StateError('Permission required: $permissionCode');
    }
  }

  String? get currentUserId => _currentSession?.userId;
  String? get currentShiftId => _currentSession?.shiftId;
  String? get currentUsername => _currentSession?.username;

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

  /// Throw kalau no permission. Pakai ini di UI handler.
  void requireCurrentPermission(String permission) {
    if (!hasCurrentPermission(permission)) {
      throw StateError('Permission required: $permission');
    }
  }

  /// Helper untuk dual check pattern (edit/delete own data).
  /// Return true kalau:
  /// - User punya permission `*_any_*` (owner override), ATAU
  /// - User punya permission `*_own_*` AND recordOwnerId == currentUserId
  /// Bolehkah pengguna yang sedang login mengubah atau menghapus catatan
  /// milik [pemilikCatatan]?
  ///
  /// ── ATURAN PATEN, TIDAK BISA DIATUR PER AKUN ──
  ///
  ///   owner       -> boleh, siapa pun pembuatnya
  ///   selain owner -> hanya catatannya sendiri
  ///
  /// Dulu ini dijaga empat kode izin yang bisa dinyalakan satu-satu:
  /// `edit_own_expense`, `edit_any_expense`, `delete_own_transaction`,
  /// `delete_any_transaction`. Keempatnya dibuang karena bisa disetel ke
  /// kombinasi yang tidak masuk akal — kasir yang diberi `delete_any_*` bisa
  /// menghapus transaksi kasir lain, dan pemilik yang lupa menyalakan
  /// `edit_any_*` justru tidak bisa membetulkan pengeluaran anak buahnya.
  ///
  /// Aturan di atas adalah yang sebenarnya dimaksud sejak awal, dan sekarang
  /// tidak ada cara untuk menyetelnya keliru.
  bool bolehUbahCatatan(String? pemilikCatatan) {
    final sesi = _currentSession;
    if (sesi == null) return false;
    if (sesi.isOwner) return true;
    return pemilikCatatan != null && pemilikCatatan == sesi.userId;
  }
}

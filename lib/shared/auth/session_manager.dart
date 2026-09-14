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

  /// Bertambah setiap kali daftar izin sesi yang sedang berjalan BERUBAH.
  ///
  /// Layar yang menyaring menu berdasarkan izin mendengarkan ini supaya ikut
  /// digambar ulang. Tanpa itu, izin yang baru turun dari server baru terlihat
  /// setelah pengguna keluar dan masuk lagi.
  final ValueNotifier<int> izinBerubah = ValueNotifier(0);

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
    izinBerubah.value++;
  }

  /// Helper: ambil permissions dari DB.
  Future<List<String>> _getUserPermissionsFromDb(
      String userId, String role) async {
    if (role == 'owner') {
      final all = await _dbx.select(_dbx.permissions).get();
      return all.map((p) => p.code).toList();
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

  /// Check permission. Owner always returns true.
  bool hasPermission(String permissionCode) {
    if (_currentSession == null) return false;
    if (_currentSession!.isOwner) return true;
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

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_database.dart';
import 'db.dart';

/// State holder global untuk active business.
///
/// Singleton pattern (mirror SessionManager). Listen via [ListenableBuilder]
/// atau [AnimatedBuilder] untuk auto-rebuild saat business switch.
///
/// Lifecycle:
/// 1. Setelah login: panggil [loadInitial] untuk populate availableBusinesses
///    + restore last active business dari SharedPreferences.
/// 2. Saat owner switch business: panggil [switchTo] dengan businessId.
/// 3. Saat logout: panggil [clear].
class BusinessContext extends ChangeNotifier {
  static final BusinessContext instance = BusinessContext._();
  BusinessContext._();

  /// Override DB untuk unit test. JANGAN dipakai di production code.
  static AppDatabase? dbOverride;
  AppDatabase get _dbx => dbOverride ?? db;

  static const String _activeBusinessKey = 'active_business_id';

  BusinessesData? _activeBusiness;
  List<BusinessesData> _availableBusinesses = [];

  BusinessesData? get activeBusiness => _activeBusiness;
  String? get activeBusinessId => _activeBusiness?.id;
  String? get activeType => _activeBusiness?.type;
  List<BusinessesData> get availableBusinesses =>
      List.unmodifiable(_availableBusinesses);

  bool get isReady => _activeBusiness != null;
  bool get hasMultipleBusinesses => _availableBusinesses.length > 1;

  /// Switch ke business lain. Validate user punya akses dulu.
  /// Throw [UnauthorizedException] kalau tidak punya akses.
  Future<void> switchTo(String businessId, {required String userId}) async {
    final hasAccess = await _userHasAccessToBusiness(userId, businessId);
    if (!hasAccess) {
      throw UnauthorizedException(
        'User $userId tidak punya akses ke business $businessId',
      );
    }

    final business = await (_dbx.select(_dbx.businesses)
          ..where((b) => b.id.equals(businessId) & b.deletedAt.isNull()))
        .getSingleOrNull();

    if (business == null) {
      throw StateError('Business $businessId tidak ditemukan atau sudah dihapus');
    }

    _activeBusiness = business;
    // Reload daftar juga — tanpa ini business yang dibuat setelah login
    // tidak muncul di daftar sampai app restart (bug switcher basi).
    _availableBusinesses = await _loadBusinessesForUser(userId);
    await _persistChoice(businessId);
    notifyListeners();
  }

  /// Dipanggil main() SEBELUM ada session: siapkan branding (warna/logo/nama)
  /// untuk halaman login dari business aktif terakhir yang dipersist.
  /// No-op kalau active business sudah terisi (mis. oleh restoreSession).
  Future<void> loadPersistedForBranding() async {
    if (_activeBusiness != null) return;
    final lastUsedId = await _loadPersistedChoice();
    final all = await (_dbx.select(_dbx.businesses)
          ..where((b) => b.deletedAt.isNull() & b.isActive.equals(true)))
        .get();
    if (all.isEmpty) return;
    _activeBusiness = all.firstWhere(
      (b) => b.id == lastUsedId,
      orElse: () => all.first,
    );
    notifyListeners();
  }

  /// Dipanggil setelah login. Load available businesses untuk user.
  /// Restore last active business dari SharedPreferences.
  Future<void> loadInitial({required String userId}) async {
    _availableBusinesses = await _loadBusinessesForUser(userId);

    if (_availableBusinesses.isEmpty) {
      _activeBusiness = null;
      notifyListeners();
      return;
    }

    final lastUsedId = await _loadPersistedChoice();
    _activeBusiness = _availableBusinesses.firstWhere(
      (b) => b.id == lastUsedId,
      orElse: () => _availableBusinesses.first,
    );
    notifyListeners();
  }

  /// Re-fetch data business aktif dari DB (dipanggil setelah edit profil
  /// business, misal ganti nama). Refresh juga daftar available businesses.
  Future<void> refreshActiveBusiness({required String userId}) async {
    final activeId = _activeBusiness?.id;
    _availableBusinesses = await _loadBusinessesForUser(userId);
    if (activeId != null) {
      _activeBusiness = _availableBusinesses.firstWhere(
        (b) => b.id == activeId,
        orElse: () => _availableBusinesses.isNotEmpty
            ? _availableBusinesses.first
            : _activeBusiness!,
      );
    }
    notifyListeners();
  }

  /// Clear saat logout
  void clear() {
    _activeBusiness = null;
    _availableBusinesses = [];
    notifyListeners();
  }

  // ============ Private helpers ============

  Future<List<BusinessesData>> _loadBusinessesForUser(String userId) async {
    final query = _dbx.select(_dbx.businesses).join([
      innerJoin(
        _dbx.userBusinessRoles,
        _dbx.userBusinessRoles.businessId.equalsExp(_dbx.businesses.id) &
            _dbx.userBusinessRoles.userId.equals(userId) &
            _dbx.userBusinessRoles.deletedAt.isNull(),
      ),
    ])
      ..where(_dbx.businesses.deletedAt.isNull() & _dbx.businesses.isActive.equals(true));

    final rows = await query.get();
    return rows.map((row) => row.readTable(_dbx.businesses)).toList();
  }

  Future<bool> _userHasAccessToBusiness(
      String userId, String businessId) async {
    final result = await (_dbx.select(_dbx.userBusinessRoles)
          ..where((r) =>
              r.userId.equals(userId) &
              r.businessId.equals(businessId) &
              r.deletedAt.isNull())
          ..limit(1))
        .get();
    return result.isNotEmpty;
  }

  Future<void> _persistChoice(String businessId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeBusinessKey, businessId);
  }

  Future<String?> _loadPersistedChoice() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeBusinessKey);
  }
}

class UnauthorizedException implements Exception {
  final String message;
  UnauthorizedException(this.message);
  @override
  String toString() => 'UnauthorizedException: $message';
}

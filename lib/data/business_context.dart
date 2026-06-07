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

    final business = await (db.select(db.businesses)
          ..where((b) => b.id.equals(businessId) & b.deletedAt.isNull()))
        .getSingleOrNull();

    if (business == null) {
      throw StateError('Business $businessId tidak ditemukan atau sudah dihapus');
    }

    _activeBusiness = business;
    await _persistChoice(businessId);
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

  /// Clear saat logout
  void clear() {
    _activeBusiness = null;
    _availableBusinesses = [];
    notifyListeners();
  }

  // ============ Private helpers ============

  Future<List<BusinessesData>> _loadBusinessesForUser(String userId) async {
    final query = db.select(db.businesses).join([
      innerJoin(
        db.userBusinessRoles,
        db.userBusinessRoles.businessId.equalsExp(db.businesses.id) &
            db.userBusinessRoles.userId.equals(userId) &
            db.userBusinessRoles.deletedAt.isNull(),
      ),
    ])
      ..where(db.businesses.deletedAt.isNull() & db.businesses.isActive.equals(true));

    final rows = await query.get();
    return rows.map((row) => row.readTable(db.businesses)).toList();
  }

  Future<bool> _userHasAccessToBusiness(
      String userId, String businessId) async {
    final result = await (db.select(db.userBusinessRoles)
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

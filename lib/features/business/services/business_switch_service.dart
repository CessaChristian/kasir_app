import 'package:drift/drift.dart';

import '../../../data/app_database.dart';
import '../../../data/business_context.dart';
import '../../../data/db.dart';
import '../../../data/uuid_helper.dart';
import '../../../shared/auth/session_manager.dart';

/// Alur aktivasi (ganti) business — dipanggil dari BusinessDetailPage
/// setelah owner mengonfirmasi dialog.
///
/// Urutan (spec REVISI 2, D2): validasi akses → tutup shift aktif → buka
/// shift baru di business target → update session → switch BusinessContext
/// → refresh role cache. Root MaterialApp otomatis rebuild (key berubah)
/// = "soft restart" ke dashboard business baru.
class BusinessSwitchService {
  BusinessSwitchService._();

  /// Override DB untuk unit test. JANGAN dipakai di production code.
  static AppDatabase? dbOverride;
  static AppDatabase get _dbx => dbOverride ?? db;

  static Future<void> activate(String targetBusinessId) async {
    final session = SessionManager.instance.currentSession;
    if (session == null) {
      throw StateError('Tidak ada session aktif. Login ulang dulu.');
    }
    final userId = session.userId;

    // 0. Fail-fast: validasi akses SEBELUM menyentuh shift, supaya tidak
    // ada state setengah jadi kalau akses ditolak.
    final access = await (_dbx.select(_dbx.userBusinessRoles)
          ..where((r) =>
              r.userId.equals(userId) &
              r.businessId.equals(targetBusinessId) &
              r.deletedAt.isNull())
          ..limit(1))
        .get();
    if (access.isEmpty) {
      throw UnauthorizedException(
          'User $userId tidak punya akses ke business $targetBusinessId');
    }

    // Owner TIDAK menjalankan shift (shiftId null) — cukup ganti context tanpa
    // menyentuh shift. Hanya cashier yang punya siklus tutup-buka shift.
    final isCashierWithShift = session.shiftId != null;

    if (isCashierWithShift) {
      // 1. Tutup shift aktif (kalau masih terbuka).
      await (_dbx.update(_dbx.shifts)
            ..where((s) => s.id.equals(session.shiftId!) & s.endAt.isNull()))
          .write(ShiftsCompanion(endAt: Value(DateTime.now())));

      // 2. Buka shift baru di business target (invariant: cashier selalu punya
      // shift aktif — tanpa ini transaksi berikutnya menempel ke shift
      // business lama).
      final newShiftId = newUuid();
      await _dbx.into(_dbx.shifts).insert(ShiftsCompanion.insert(
            id: Value(newShiftId),
            businessId: targetBusinessId,
            userId: userId,
          ));

      // 3. Session menunjuk shift baru.
      await SessionManager.instance
          .setSession(session.copyWith(shiftId: newShiftId));
    }

    // 4. Switch context — memicu rebuild root (soft restart).
    await BusinessContext.instance
        .switchTo(targetBusinessId, userId: userId);

    // 5. Role cache untuk business baru.
    await SessionManager.instance.refreshRoleCache();
  }
}

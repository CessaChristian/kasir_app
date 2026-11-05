import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Menahan pembacaan tabel users persis di tengah pemeriksaan akun, supaya
/// kasir bisa dikeluarkan tepat di titik itu tanpa bergantung waktu.
class _Gerbang extends QueryInterceptor {
  Completer<void>? tahan;
  final masuk = Completer<void>();

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final g = tahan;
    if (g != null && statement.contains('"users"')) {
      if (!masuk.isCompleted) masuk.complete();
      await g.future;
    }
    return executor.runSelect(statement, args);
  }
}

/// Review B4: owner mengganti nama akun tepat saat HP kasir keluar sendiri.
/// Kabar ganti nama tidak boleh memasukkan kasir itu lagi tanpa PIN.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sm = SessionManager.instance;

  test('kasir keluar selagi akun dibaca → tidak masuk lagi', () async {
    SharedPreferences.setMockInitialValues({});
    final gerbang = _Gerbang();
    final db = AppDatabase.forTesting(
      NativeDatabase.memory().interceptWith(gerbang),
    );
    SessionManager.dbOverride = db;
    addTearDown(() async {
      SessionManager.dbOverride = null;
      await sm.clearSession();
      await db.close();
    });
    await db.into(db.users).insert(
      UsersCompanion.insert(
        id: const Value('k-1'),
        username: 'sari-baru',
        pinHash: 'pin',
        salt: 's',
        role: 'cashier',
      ),
    );
    await sm.setSession(
      AuthSession.create(
        userId: 'k-1',
        username: 'sari',
        role: 'cashier',
        shiftId: null,
        permissions: const [],
      ),
    );
    await sm.ingatPinMasuk('k-1', 'pin', salt: 's');

    gerbang.tahan = Completer<void>();
    final periksa = sm.periksaAkunMasihBerlaku();
    await gerbang.masuk.future;

    await sm.clearSession(); // 15 menit tidak disentuh

    gerbang.tahan!.complete();
    gerbang.tahan = null;
    await periksa;

    expect(sm.isLoggedIn, isFalse);
    final p = await SharedPreferences.getInstance();
    expect(p.getString('auth_session'), isNull);
    expect(p.getString('pin_saat_masuk'), isNull);
  });
}

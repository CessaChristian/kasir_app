import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Masuk sebagai owner untuk test yang memanggil repository langsung.
///
/// Repository sekarang ikut memeriksa siapa yang masuk (revisi QA C9), jadi
/// test yang dulu memanggilnya tanpa sesi harus menyebut siapa pemanggilnya.
/// Sesi dihapus otomatis sesudah test.
Future<void> masukSebagaiOwner({String userId = 'owner-test'}) async {
  SharedPreferences.setMockInitialValues({});
  await SessionManager.instance.setSession(
    AuthSession.create(
      userId: userId,
      username: 'owner',
      role: 'owner',
      shiftId: null,
      permissions: const [],
    ),
  );
  addTearDown(SessionManager.instance.clearSession);
}

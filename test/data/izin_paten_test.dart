import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mengunci aturan siapa boleh mengubah/menghapus catatan milik siapa.
///
/// ── KENAPA JADI PATEN ──
///
/// Dulu ini dijaga empat izin yang bisa dinyalakan satu-satu:
/// `edit_own_expense`, `edit_any_expense`, `delete_own_transaction`,
/// `delete_any_transaction`. Kombinasinya bisa disetel ke keadaan yang tidak
/// masuk akal: kasir yang diberi `delete_any_transaction` bisa menghapus
/// transaksi kasir LAIN, sedangkan pemilik yang lupa menyalakan
/// `edit_any_expense` justru tidak bisa membetulkan pengeluaran anak buahnya.
///
/// Sekarang aturannya tetap dan tidak bisa disetel keliru.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SessionManager.dbOverride = db;
  });

  tearDown(() async {
    await SessionManager.instance.clearSession();
    SessionManager.dbOverride = null;
    await db.close();
  });

  test('keempat kode izin lama sudah tidak ada di kode', () async {
    // Penjaga: kalau salah satunya muncul lagi, artinya ada yang menghidupkan
    // kembali jalur yang bisa disetel keliru.
    final katalog = await db.select(db.permissions).get();
    final kode = katalog.map((p) => p.code).toSet();

    for (final mati in const [
      'edit_own_expense',
      'edit_any_expense',
      'delete_own_transaction',
      'delete_any_transaction',
    ]) {
      expect(kode, isNot(contains(mati)), reason: '$mati sudah dipatenkan');
    }
  });

  test('katalog izin berbahasa Indonesia', () async {
    // Yang membacanya pemilik warung, bukan pengembang. "Edit Any Expense
    // (owner override)" tidak berarti apa-apa baginya.
    final katalog = await db.select(db.permissions).get();
    expect(katalog, hasLength(6));

    for (final p in katalog) {
      expect(p.name, isNot(matches(RegExp(r'^(View|Manage|Create|Edit|Delete|Open)\b'))),
          reason: '"${p.name}" masih berbahasa Inggris');
    }
  });
}

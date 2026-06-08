import 'app_database.dart';
import 'business_context.dart';

final db = AppDatabase();

// Wire BusinessContext → AppDatabase setelah keduanya ter-instantiate.
// Dipisah dari app_database.dart untuk menghindari circular import:
//   business_context.dart → app_database.dart (OK)
//   app_database.dart → business_context.dart (CIRCULAR — dilarang)
// db.dart bisa import keduanya karena tidak di-import oleh keduanya.
//
// ignore: unused_element — variabel ini hanya diperlukan untuk side-effect saat import
final _wireBusinessContext = () {
  AppDatabase.activeBusinessIdProvider =
      () => BusinessContext.instance.activeBusinessId;
  return true;
}();

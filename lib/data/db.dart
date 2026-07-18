import 'app_database.dart';
import 'business_context.dart';

// Wiring BusinessContext -> AppDatabase dilakukan DI DALAM initializer `db`.
//
// PENTING: top-level variable di Dart bersifat lazy — hanya dieksekusi saat
// pertama kali DIBACA. Wiring ini sebelumnya ditaruh di variabel terpisah
// (_wireBusinessContext) yang tidak pernah dibaca siapa pun, sehingga tidak
// pernah jalan dan semua watch method return Stream.empty() (halaman stuck
// loading selamanya). Dengan menaruhnya di initializer `db`, wiring dijamin
// jalan sebelum query apa pun karena semua akses DB lewat `db`.
//
// File ini dipisah dari app_database.dart untuk menghindari circular import:
//   business_context.dart -> app_database.dart (OK)
//   app_database.dart -> business_context.dart (CIRCULAR — dilarang)
// db.dart bisa import keduanya karena tidak di-import oleh keduanya.
final AppDatabase db = () {
  AppDatabase.activeBusinessIdProvider =
      () => BusinessContext.instance.activeBusinessId;
  return AppDatabase();
}();

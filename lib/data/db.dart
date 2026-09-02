import 'app_database.dart';

/// Instance database tunggal untuk seluruh aplikasi.
///
/// Dulu file ini juga memasang jembatan BusinessContext -> AppDatabase supaya
/// setiap query otomatis tersaring per bisnis. Aplikasi kini difokuskan ke
/// satu bisnis, jadi penyaringan itu — beserta seluruh risikonya kalau lupa
/// dipasang — sudah tidak ada.
final AppDatabase db = AppDatabase();

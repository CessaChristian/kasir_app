import 'package:uuid/uuid.dart';

const _uuidGenerator = Uuid();

/// Generate UUID v4 string. Pakai ini untuk semua primary key entity baru.
///
/// Pattern di Drift table:
/// ```dart
/// TextColumn get id => text().clientDefault(() => newUuid())();
/// ```
String newUuid() => _uuidGenerator.v4();

/// UUID yang SELALU SAMA untuk pasangan nilai yang sama.
///
/// Dipakai untuk baris yang identitasnya ditentukan isinya, bukan oleh siapa
/// yang membuatnya duluan — misalnya "izin X milik user Y". Pasangan itu hanya
/// boleh ada satu, dan perangkat mana pun yang membuatnya harus menghasilkan
/// baris yang SAMA, bukan dua baris berbeda yang lalu bertabrakan saat sync.
///
/// Dengan UUID acak, HP owner dan HP kasir yang sama-sama membuat izin yang
/// sama menghasilkan dua `id` berbeda untuk satu pasangan — dan batasan unik
/// pada pasangan itu akan menolak yang kedua, lalu barisnya tertahan
/// selamanya. UUID turunan membuat keduanya menghasilkan `id` identik,
/// sehingga yang terjadi cuma saling menimpa dengan isi yang sama.
///
/// Memakai UUID v5 (SHA-1 atas namespace tetap) supaya bentuknya tetap UUID
/// sah dan diterima kolom `uuid` PostgreSQL.
String uuidTurunan(String kunci) =>
    _uuidGenerator.v5(Namespace.url.value, kunci);

import 'package:uuid/uuid.dart';

const _uuidGenerator = Uuid();

/// Generate UUID v4 string. Pakai ini untuk semua primary key entity baru.
///
/// Pattern di Drift table:
/// ```dart
/// TextColumn get id => text().clientDefault(() => newUuid())();
/// ```
String newUuid() => _uuidGenerator.v4();

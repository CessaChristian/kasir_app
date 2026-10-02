import 'package:drift/drift.dart';
import '../../../data/app_database.dart';
import '../../../data/supabase/supabase_service.dart';
import '../../../data/uuid_helper.dart';
import '../../../utils/crypto_utils.dart';
import '../../../shared/auth/session_manager.dart';

/// Menjawab: apakah [nama] sudah dipakai akun LAIN (selain [kecualiId]) di
/// server? Melempar [StateError] kalau tidak bisa memastikan.
typedef PemeriksaNamaServer = Future<bool> Function(
    String nama, String kecualiId);

/// Repository for managing cashier accounts
class CashierRepository {
  final AppDatabase _db;
  final PemeriksaNamaServer _namaDipakaiDiServer;

  CashierRepository(this._db, {PemeriksaNamaServer? namaDipakaiDiServer})
      : _namaDipakaiDiServer = namaDipakaiDiServer ?? _periksaKeSupabase;

  static const panjangNamaMin = 3;
  static const panjangNamaMaks = 30;

  /// Kelola Kasir adalah hak PATEN owner, bukan izin yang bisa diberikan —
  /// semua fungsi yang mengubah akun kasir memeriksanya di sini, tidak hanya
  /// lewat menu yang disembunyikan. Izin bawaan kasir baru: [izinBawaanKasir].
  void _requireManageCashiers() {
    SessionManager.instance.requireOwner();
  }

  Future<User> createCashier({
    required String username,
    required String pin,
  }) async {
    _requireManageCashiers();

    // 1. Validate PIN format
    if (!CryptoUtils.isValidPinFormat(pin)) {
      throw ArgumentError('PIN harus ${CryptoUtils.pinLength} digit angka');
    }

    // 2. Check if username already exists
    final existing = await (_db.select(_db.users)
          ..where((u) => u.username.equals(username)))
        .get();

    if (existing.isNotEmpty) {
      throw StateError('Username sudah dipakai.');
    }

    // 3. Generate salt and hash PIN
    final salt = CryptoUtils.generateSalt();
    final pinHash = CryptoUtils.hashPin(pin, salt);

    // 4. Primary key WAJIB UUID supaya unik lintas device saat sync.
    final userId = newUuid();

    // I1: Bungkus insert user + set permissions dalam satu transaksi.
    // Kalau permissions gagal di-set, user juga di-rollback agar tidak
    // ada akun "zombie" tanpa permission.
    return await _db.transaction<User>(() async {
      await _db.into(_db.users).insert(
            UsersCompanion.insert(
              id: Value(userId),
              username: username,
              pinHash: pinHash,
              salt: salt,
              role: 'cashier',
              isActive: const Value(true),
            ),
          );

      await _setDefaultCashierPermissions(userId);

      final created = await (_db.select(_db.users)
            ..where((u) => u.id.equals(userId)))
          .getSingleOrNull();
      if (created == null) {
        throw StateError(
            'Akun kasir berhasil dibuat. Kasir dapat login menggunakan username dan PIN yang baru.');
      }
      return created;
    });
  }

  /// Semua akun kasir, terbaru dulu.
  Future<List<User>> getAllCashiers() async {
    return await (_db.select(_db.users)
          ..where((u) => u.role.equals('cashier'))
          ..orderBy([(u) => OrderingTerm.desc(u.createdAt)]))
        .get();
  }

  /// Toggle cashier active status
  Future<void> toggleCashierStatus(String userId, bool isActive) async {
    _requireManageCashiers();
    await (_db.update(_db.users)..where((u) => u.id.equals(userId))).write(
      UsersCompanion(
        isActive: Value(isActive),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value('pending'),
      ),
    );
  }

  /// Reset cashier PIN
  Future<void> resetCashierPin(String userId, String newPin) async {
    _requireManageCashiers();

    // 1. Validate PIN format
    if (!CryptoUtils.isValidPinFormat(newPin)) {
      throw ArgumentError('PIN harus ${CryptoUtils.pinLength} digit angka');
    }

    // 2. Generate new salt and hash
    final salt = CryptoUtils.generateSalt();
    final pinHash = CryptoUtils.hashPin(newPin, salt);

    // 3. Update user
    await (_db.update(_db.users)..where((u) => u.id.equals(userId))).write(
      UsersCompanion(
        salt: Value(salt),
        pinHash: Value(pinHash),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value('pending'),
      ),
    );
  }

  /// Ganti username kasir.
  ///
  /// Riwayat ikut memakai nama baru, karena shift, transaksi, dan pengeluaran
  /// menunjuk akun lewat id, bukan lewat namanya. Itu memang tujuannya:
  /// membetulkan salah ketik. Satu akun = satu orang — karyawan baru dibuatkan
  /// akun baru, bukan meminjam akun lama.
  ///
  /// Nama WAJIB dicek ke server, bukan cuma ke HP ini: HP lain bisa saja baru
  /// membuat akun bernama sama yang belum tertarik ke sini. Kalau lolos, dua
  /// akun bernama sama, server menolak salah satunya, dan sinkronnya macet.
  Future<void> gantiNamaKasir(String userId, String namaBaru) async {
    _requireManageCashiers();

    final nama = namaBaru.trim();
    if (nama.length < panjangNamaMin || nama.length > panjangNamaMaks) {
      throw ArgumentError(
          'Nama harus $panjangNamaMin–$panjangNamaMaks karakter.');
    }

    final akun = await (_db.select(_db.users)
          ..where((u) => u.id.equals(userId)))
        .getSingleOrNull();
    if (akun == null || akun.role != 'cashier') {
      throw StateError('Akun kasir tidak ditemukan.');
    }
    if (akun.username == nama) return;

    final kembarDiSini = await (_db.select(_db.users)
          ..where((u) => u.username.equals(nama) & u.id.equals(userId).not()))
        .get();
    if (kembarDiSini.isNotEmpty ||
        await _namaDipakaiDiServer(nama, userId)) {
      throw StateError('Nama "$nama" sudah dipakai akun lain.');
    }

    await (_db.update(_db.users)..where((u) => u.id.equals(userId))).write(
      UsersCompanion(
        username: Value(nama),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value('pending'),
      ),
    );
  }

  static Future<bool> _periksaKeSupabase(String nama, String kecualiId) async {
    final supabase = SupabaseService.instance;
    if (!supabase.online) {
      throw StateError('Ganti nama butuh internet, supaya nama yang sama '
          'tidak dipakai dua akun.');
    }
    try {
      final baris = await supabase.client!
          .from('users')
          .select('id')
          .eq('username', nama)
          .neq('id', kecualiId)
          .limit(1);
      return baris.isNotEmpty;
    } catch (_) {
      throw StateError('Gagal memeriksa nama ke server. Coba lagi.');
    }
  }

  /// Set default permissions for a new cashier
  Future<void> _setDefaultCashierPermissions(String userId) async {
    // Hanya izin yang MENYALA yang disisipkan. Baris `enabled: false` dan
    // baris yang tidak ada sama sekali berperilaku persis sama — keduanya
    // membuat `hasPermission` bernilai false — jadi menyimpannya cuma
    // menambah baris yang harus ikut disinkronkan tanpa guna.
    //
    // Daftarnya diambil dari satu tetapan bersama supaya tidak berbeda dengan
    // yang dipakai migrasi saat mengisi ulang izin yang hilang.
    for (final kode in izinBawaanKasir) {
      await _db.into(_db.userPermissions).insert(
            UserPermissionsCompanion.insert(
              id: uuidTurunan('$userId:$kode'),
              userId: userId,
              permissionCode: kode,
              enabled: const Value(true),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
  }

}

import 'package:drift/drift.dart';
import '../../../data/app_database.dart';
import '../../../data/nama_tercatat.dart';
import '../../../data/supabase/server_terjangkau.dart';
import '../../../data/supabase/supabase_service.dart';
import '../../../data/uuid_helper.dart';
import '../../../utils/crypto_utils.dart';
import '../../../shared/auth/session_manager.dart';
import '../models/ringkasan_kasir.dart';

/// Menjawab: apakah [nama] sudah dipakai akun LAIN (selain [kecualiId]) di
/// server? [kecualiId] null untuk akun baru. Melempar [StateError] kalau
/// tidak bisa memastikan.
typedef PemeriksaNamaServer =
    Future<bool> Function(String nama, String? kecualiId);

/// Menjawab: apakah server bisa dihubungi sekarang?
typedef PemeriksaKoneksi = Future<bool> Function();

/// Pesan saat Kelola Kasir dipakai tanpa internet.
const pesanButuhInternet = 'Butuh internet — coba lagi setelah tersambung.';

/// Repository for managing cashier accounts
///
/// Semua perubahan akun kasir WAJIB online (keputusan owner 2026-10-07):
/// akibatnya dirasakan di HP kasir, dan username harus dicek ke server
/// supaya dua HP tidak membuat akun bernama sama. Ditegakkan di sini, bukan
/// hanya di halaman.
class CashierRepository {
  final AppDatabase _db;
  final PemeriksaNamaServer _namaDipakaiDiServer;
  final PemeriksaKoneksi _terhubung;

  CashierRepository(
    this._db, {
    PemeriksaNamaServer? namaDipakaiDiServer,
    PemeriksaKoneksi? terhubung,
  }) : _namaDipakaiDiServer = namaDipakaiDiServer ?? _periksaKeSupabase,
       _terhubung = terhubung ?? serverTerjangkau;

  /// Server bisa dihubungi sekarang? Dipakai halaman sebelum membuka lembar.
  Future<bool> terhubung() => _terhubung();

  Future<void> _wajibOnline() async {
    if (!await _terhubung()) throw StateError(pesanButuhInternet);
  }

  static const panjangNamaMin = 3;
  static const panjangNamaMaks = 30;

  /// Aturan username, ditegakkan di sini untuk akun baru maupun ganti nama
  /// (lembarnya memakai [periksaUsername] yang sama).
  static String? periksaUsername(String nama) {
    final n = nama.trim();
    if (n.isEmpty) return 'Username wajib diisi';
    if (n.length < panjangNamaMin || n.length > panjangNamaMaks) {
      return 'Username harus $panjangNamaMin–$panjangNamaMaks karakter';
    }
    if (n.contains(RegExp(r'\s'))) return 'Username tidak boleh memuat spasi';
    // Dipakai sebagai penanda akun yang dihapus (lihat [usernameTerhapus]).
    if (n.contains(penandaDihapus)) {
      return 'Username tidak boleh memuat "$penandaDihapus"';
    }
    return null;
  }

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

    final galatNama = periksaUsername(username);
    if (galatNama != null) throw ArgumentError(galatNama);
    username = username.trim();

    // 1. Validate PIN format
    if (!CryptoUtils.isValidPinFormat(pin)) {
      throw ArgumentError('PIN harus ${CryptoUtils.pinLength} digit angka');
    }
    await _wajibOnline();

    // 2. Username tidak boleh kembar — di HP ini MAUPUN di server. HP lain
    // bisa saja baru membuat akun bernama sama yang belum tertarik ke sini;
    // kalau lolos, server menolak salah satunya dan sinkronnya macet.
    final existing = await (_db.select(
      _db.users,
    )..where((u) => u.username.equals(username))).get();

    if (existing.isNotEmpty || await _namaDipakaiDiServer(username, null)) {
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
      await _db
          .into(_db.users)
          .insert(
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

      final created = await (_db.select(
        _db.users,
      )..where((u) => u.id.equals(userId))).getSingleOrNull();
      if (created == null) {
        throw StateError(
          'Akun kasir berhasil dibuat. Kasir dapat login menggunakan username dan PIN yang baru.',
        );
      }
      return created;
    });
  }

  /// Semua akun kasir yang belum dihapus, terbaru dulu. Akun yang dihapus
  /// tidak tampil lagi di mana pun selain sebagai nama di riwayat.
  Future<List<User>> getAllCashiers() async {
    return await (_db.select(_db.users)
          ..where((u) => u.role.equals('cashier') & u.deletedAt.isNull())
          ..orderBy([(u) => OrderingTerm.desc(u.createdAt)]))
        .get();
  }

  /// Daftar kartu Kelola Kasir: akun aktif dulu, lalu yang nonaktif;
  /// masing-masing terbaru dulu. Ikut berubah setiap kali akun, shift, atau
  /// izin berubah — termasuk yang datang dari sinkron.
  Stream<List<RingkasanKasir>> watchDaftarKasir() => _db
      .customSelect(
        'SELECT 1',
        readsFrom: {
          _db.users,
          _db.shifts,
          _db.userPermissions,
          _db.permissions,
        },
      )
      .watch()
      .asyncMap((_) => _daftarKasir());

  Future<List<RingkasanKasir>> _daftarKasir() async {
    final kasir = await getAllCashiers();
    if (kasir.isEmpty) return const [];
    final id = [for (final k in kasir) k.id];

    final shift = await (_db.select(
      _db.shifts,
    )..where((s) => s.deletedAt.isNull() & s.userId.isIn(id))).get();
    final kodeIzin = {
      for (final p in await _db.select(_db.permissions).get()) p.code,
    };
    final izinMenyala = await (_db.select(
      _db.userPermissions,
    )..where((u) => u.enabled.equals(true) & u.userId.isIn(id))).get();

    final hasil = [
      for (final k in kasir)
        () {
          final milik = shift.where((s) => s.userId == k.id);
          final berjalan = milik.where((s) => s.endAt == null);
          final selesai = milik.where((s) => s.endAt != null);
          return RingkasanKasir(
            akun: k,
            mulaiShiftBerjalan: berjalan.isEmpty
                ? null
                : berjalan
                      .map((s) => s.startAt)
                      .reduce((a, b) => a.isAfter(b) ? a : b),
            selesaiShiftTerakhir: selesai.isEmpty
                ? null
                : selesai
                      .map((s) => s.endAt!)
                      .reduce((a, b) => a.isAfter(b) ? a : b),
            izinAktif: izinMenyala
                .where(
                  (u) =>
                      u.userId == k.id && kodeIzin.contains(u.permissionCode),
                )
                .length,
            izinTotal: kodeIzin.length,
          );
        }(),
    ];
    // Aktif dulu; urutan bawaan (terbaru dulu) dipertahankan di tiap bagian.
    return [
      ...hasil.where((r) => r.akun.isActive),
      ...hasil.where((r) => !r.akun.isActive),
    ];
  }

  /// Aktifkan / nonaktifkan akun kasir.
  ///
  /// Menonaktifkan ikut MENGAKHIRI shift kasir itu yang masih berjalan.
  /// Kasirnya dikeluarkan dari HP-nya, jadi tidak ada lagi yang bisa
  /// menutupnya — tanpa ini shiftnya tercatat "Aktif" selamanya di Riwayat
  /// Shift dan Dashboard.
  Future<void> toggleCashierStatus(String userId, bool isActive) async {
    _requireManageCashiers();
    await _wajibOnline();
    final sekarang = DateTime.now();
    await _db.transaction(() async {
      await (_db.update(_db.users)..where((u) => u.id.equals(userId))).write(
        UsersCompanion(
          isActive: Value(isActive),
          updatedAt: Value(sekarang),
          syncStatus: const Value('pending'),
        ),
      );
      if (!isActive) await _akhiriShiftBerjalan(userId, sekarang);
    });
  }

  /// Hapus akun kasir (keputusan owner 2026-10-07): PERMANEN, tidak bisa
  /// dipulihkan — beda dengan nonaktif.
  ///
  /// Barisnya TIDAK dibuang: shift, transaksi, dan pengeluaran lamanya masih
  /// menunjuk id-nya. Yang terjadi, dalam satu transaksi:
  /// - `deleted_at` diisi → hilang dari Kelola Kasir, login & sesi ditolak;
  /// - ikut dinonaktifkan → HP dengan APK lama (belum kenal `deleted_at`)
  ///   tetap menolaknya;
  /// - username diganti [usernameTerhapus] → nama aslinya bebas dipakai
  ///   akun baru; riwayat lama memakai salinan nama + " (dihapus)";
  /// - shift yang masih berjalan diakhiri (sama seperti nonaktif).
  Future<void> hapusKasir(String userId) async {
    _requireManageCashiers();
    await _wajibOnline();
    final akun = await (_db.select(
      _db.users,
    )..where((u) => u.id.equals(userId))).getSingleOrNull();
    if (akun == null || akun.role != 'cashier') {
      throw StateError('Akun kasir tidak ditemukan.');
    }
    if (akun.deletedAt != null) return;

    final sekarang = DateTime.now();
    await _db.transaction(() async {
      await (_db.update(_db.users)..where((u) => u.id.equals(userId))).write(
        UsersCompanion(
          username: Value(usernameTerhapus(akun.username, akun.id)),
          isActive: const Value(false),
          deletedAt: Value(sekarang),
          updatedAt: Value(sekarang),
          syncStatus: const Value('pending'),
        ),
      );
      await _akhiriShiftBerjalan(userId, sekarang);
    });
  }

  Future<void> _akhiriShiftBerjalan(String userId, DateTime sekarang) =>
      (_db.update(_db.shifts)..where(
            (s) =>
                s.userId.equals(userId) &
                s.endAt.isNull() &
                s.deletedAt.isNull(),
          ))
          .write(
            ShiftsCompanion(
              endAt: Value(sekarang),
              updatedAt: Value(sekarang),
              syncStatus: const Value('pending'),
            ),
          );

  /// Reset cashier PIN
  Future<void> resetCashierPin(String userId, String newPin) async {
    _requireManageCashiers();

    // 1. Validate PIN format
    if (!CryptoUtils.isValidPinFormat(newPin)) {
      throw ArgumentError('PIN harus ${CryptoUtils.pinLength} digit angka');
    }

    await _wajibOnline();

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
    final galatNama = periksaUsername(nama);
    if (galatNama != null) throw ArgumentError(galatNama);

    await _wajibOnline();

    final akun = await (_db.select(
      _db.users,
    )..where((u) => u.id.equals(userId))).getSingleOrNull();
    if (akun == null || akun.role != 'cashier' || akun.deletedAt != null) {
      throw StateError('Akun kasir tidak ditemukan.');
    }
    if (akun.username == nama) return;

    final kembarDiSini = await (_db.select(
      _db.users,
    )..where((u) => u.username.equals(nama) & u.id.equals(userId).not())).get();
    if (kembarDiSini.isNotEmpty || await _namaDipakaiDiServer(nama, userId)) {
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

  static Future<bool> _periksaKeSupabase(String nama, String? kecualiId) async {
    final supabase = SupabaseService.instance;
    if (!supabase.online) {
      throw StateError(
        'Butuh internet, supaya username yang sama tidak '
        'dipakai dua akun.',
      );
    }
    try {
      // `id` di server bertipe uuid: membandingkannya dengan teks kosong
      // ditolak Postgres ("invalid input syntax for type uuid") — dulu itu
      // membuat Tambah Akun SELALU gagal. Akun baru belum punya id, jadi
      // syaratnya cukup dilewati.
      var kueri = supabase.client!
          .from('users')
          .select('id')
          .eq('username', nama);
      if (kecualiId != null) kueri = kueri.neq('id', kecualiId);
      final baris = await kueri.limit(1);
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
      await _db
          .into(_db.userPermissions)
          .insert(
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

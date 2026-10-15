import 'package:drift/drift.dart';

import '../../../data/app_database.dart';
import '../../../data/models/sale_line.dart';
import '../../../data/supabase/supabase_service.dart';
import '../../../data/sync/sync_engine.dart';
import '../../../shared/auth/session_manager.dart';
import '../models/isi_bill.dart';

/// Panjang maksimal nama bill (desain).
const panjangMaksNamaBill = 40;

/// Galat nama bill, atau null kalau boleh dipakai. Nama yang sama dengan
/// bill terbuka lain di [terbuka] ditolak tanpa membedakan huruf besar/kecil;
/// bill [kecualiId] (yang sedang diperbarui) tidak dihitung.
String? periksaNamaBill(
  String nama,
  Iterable<OpenBill> terbuka, {
  String? kecualiId,
}) {
  final rapi = nama.trim().toLowerCase();
  if (rapi.isEmpty) return 'Nama bill wajib diisi';
  if (rapi.length > panjangMaksNamaBill) {
    return 'Nama bill maksimal $panjangMaksNamaBill huruf';
  }
  final bentrok = terbuka.any(
    (b) => b.id != kecualiId && b.name.trim().toLowerCase() == rapi,
  );
  return bentrok ? 'Nama sudah dipakai bill lain' : null;
}

/// Satu-satunya pintu data Open Bill. Bill milik shift yang sedang berjalan;
/// membayarnya lewat `SalesRepository.createSale(billId: ...)`.
class OpenBillRepository {
  final AppDatabase _db;

  OpenBillRepository(this._db);

  SimpleSelectStatement<$OpenBillsTable, OpenBill> _kueriTerbuka(
    String shiftId,
  ) => _db.select(_db.openBills)
    ..where(
      (b) =>
          b.shiftId.equals(shiftId) &
          b.transactionId.isNull() &
          b.deletedAt.isNull(),
    )
    ..orderBy([(b) => OrderingTerm.desc(b.createdAt)]);

  /// Bill terbuka di [shiftId], terbaru dulu. Tanpa shift = kosong.
  Stream<List<OpenBill>> watchTerbuka(String? shiftId) =>
      shiftId == null ? Stream.value(const []) : _kueriTerbuka(shiftId).watch();

  Future<List<OpenBill>> _terbuka(String shiftId) =>
      _kueriTerbuka(shiftId).get();

  /// Jumlah bill terbuka di [shiftId] — penghalang tutup shift.
  Future<int> jumlahTerbuka(String shiftId) async =>
      (await _terbuka(shiftId)).length;

  /// Tarik bill terbaru dari server, sebisanya, supaya bill dari HP lain di
  /// shift yang sama ikut terhitung. Gagal diabaikan: data lokal tetap
  /// dipakai.
  Future<void> segarkanDariServer() async {
    try {
      if (!SupabaseService.instance.online) return;
      await SyncEngine(
        _db,
      ).tarikTabel('open_bills').timeout(const Duration(seconds: 4));
    } catch (_) {
      // Sengaja dibisukan — lihat catatan di atas.
    }
  }

  /// Simpan isi keranjang sebagai bill baru, atau perbarui bill [id].
  /// Mengembalikan id bill-nya.
  Future<String> simpan({
    String? id,
    required String nama,
    required List<SaleLine> baris,
  }) async {
    final sm = SessionManager.instance;
    sm.requirePermission('create_transaction');
    final sesi = sm.currentSession!;
    final shiftId = sesi.shiftId;
    if (shiftId == null) {
      throw StateError('Buka shift dulu untuk mulai berjualan');
    }
    if (baris.isEmpty) throw StateError('Keranjang masih kosong');
    final rapi = nama.trim();
    final sekarang = DateTime.now();

    return _db.transaction(() async {
      final galat = periksaNamaBill(
        rapi,
        await _terbuka(shiftId),
        kecualiId: id,
      );
      if (galat != null) throw StateError(galat);

      if (id == null) {
        final baru = await _db
            .into(_db.openBills)
            .insertReturning(
              OpenBillsCompanion.insert(
                name: rapi,
                shiftId: shiftId,
                userId: sesi.userId,
                items: kodekanIsiBill(baris),
                createdAt: Value(sekarang),
                updatedAt: Value(sekarang),
              ),
            );
        return baru.id;
      }

      final diubah =
          await (_db.update(_db.openBills)..where(
                (b) =>
                    b.id.equals(id) &
                    b.transactionId.isNull() &
                    b.deletedAt.isNull(),
              ))
              .write(
                OpenBillsCompanion(
                  name: Value(rapi),
                  items: Value(kodekanIsiBill(baris)),
                  updatedAt: Value(sekarang),
                  syncStatus: const Value('pending'),
                ),
              );
      if (diubah == 0) {
        throw StateError('Bill ini sudah dibayar atau dihapus.');
      }
      return id;
    });
  }

  /// Hapus bill [id] (desain: cukup konfirmasi, tanpa alasan).
  Future<void> hapus(String id) async {
    SessionManager.instance.requirePermission('create_transaction');
    final sekarang = DateTime.now();
    await (_db.update(_db.openBills)..where(
          (b) =>
              b.id.equals(id) & b.transactionId.isNull() & b.deletedAt.isNull(),
        ))
        .write(
          OpenBillsCompanion(
            deletedAt: Value(sekarang),
            updatedAt: Value(sekarang),
            syncStatus: const Value('pending'),
          ),
        );
  }
}

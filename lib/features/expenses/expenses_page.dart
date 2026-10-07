import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../utils/currency_formatter.dart';
import '../../data/db.dart';
import 'repositories/expense_repository.dart';
import '../shift/repositories/shift_repository.dart';
import '../../data/app_database.dart';
import '../../data/nama_tercatat.dart';
import '../../shared/auth/cakupan_riwayat.dart';
import '../../shared/auth/session_manager.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/dialog_pembatalan.dart';
import 'widgets/dialog_pengeluaran.dart';
import 'widgets/batalkan_pengeluaran.dart';
import '../../shared/widgets/sync_refresh.dart';

/// Shift mana yang layak muncul di daftar "Riwayat Shift".
///
/// Dipisah dari halamannya supaya bisa diuji — dulu aturannya terkubur di
/// dalam pemuat data, jadi satu-satunya cara memeriksanya adalah lewat
/// emulator, dan dua kekeliruan di bawah lolos karenanya.
///
/// ── SHIFT YANG MASIH BERJALAN IKUT ──
///
/// Dulu syaratnya `endAt != null` — hanya shift yang sudah ditutup. Akibatnya
/// pemilik tidak bisa melihat pengeluaran kasir yang sedang bertugas sampai
/// kasirnya menekan "Akhiri Shift"; pengeluaran sore hari baru terlihat besok
/// pagi. Untuk halaman yang gunanya mengawasi, itu titik buta.
///
/// ── SHIFT AKTIF SENDIRI TIDAK IKUT ──
///
/// Punya sendiri sudah tampil utuh di bagian "Shift Aktif" di atasnya.
/// Menampilkannya lagi di riwayat hanya menduplikasi.
///
/// ── SHIFT KOSONG TIDAK IKUT ──
///
/// Ini riwayat PENGELUARAN. Shift tanpa satu pun catatan tidak menambah
/// keterangan apa pun, dan dulu harus dibuka satu per satu untuk ketahuan
/// kosong.
List<ShiftEntry> riwayatLayakTampil({
  required List<ShiftEntry> semua,
  required Map<String, List<Expense>> perShift,
  required String? shiftAktifSaya,
}) {
  return semua
      .where((e) =>
          e.shift.id != shiftAktifSaya &&
          (perShift[e.shift.id]?.isNotEmpty ?? false))
      .toList();
}

/// Halaman Pengeluaran KASIR (tampilan lama, dimigrasi di fase kasir).
/// Owner memakai `PengeluaranOwnerPage`.
class ExpensesPage extends StatefulWidget {
  const ExpensesPage({super.key});

  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  final _expenseRepo = ExpenseRepository(db);
  final _shiftRepo = ShiftRepository(db);
  List<ShiftEntry> _pastShifts = [];

  /// Untuk menampilkan siapa yang membatalkan sebuah pengeluaran.
  Map<String, String> _namaAkun = const {};
  bool _bolehLihatRiwayat = true;
  Map<String, List<Expense>> _expensesByShift = {};
  bool _loadingHistory = true;

  // Stream dibuat sekali di initState — stabil, tidak re-create tiap rebuild
  Stream<List<Expense>>? _expensesStream;
  String? _activeShiftId;

  @override
  void initState() {
    super.initState();
    final session = SessionManager.instance.currentSession;
    _activeShiftId = session?.shiftId;
    if (_activeShiftId != null) {
      _expensesStream = _expenseRepo.watchExpensesByShift(_activeShiftId!);
    }
    _loadPastShifts();
    _expenseRepo.namaAkun().then((m) {
      if (mounted) setState(() => _namaAkun = m);
    });
  }

  Future<void> _loadPastShifts() async {
    final session = SessionManager.instance.currentSession;
    if (session == null) {
      setState(() => _loadingHistory = false);
      return;
    }

    // Aturannya sama dengan halaman Riwayat — lihat `CakupanRiwayat`. Kasir
    // dengan izin `view_history` melihat shift-shift lamanya sendiri; tanpa
    // izin itu hanya shift yang sedang berjalan, yang sudah tampil di atas.
    // (Owner memakai `PengeluaranOwnerPage`, bukan halaman ini.)
    final cakupan = CakupanRiwayat.dariSesi();
    if (cakupan.jenis == JenisCakupan.shiftAktif) {
      if (mounted) {
        setState(() {
          _bolehLihatRiwayat = false;
          _pastShifts = [];
          _loadingHistory = false;
        });
      }
      return;
    }
    final semua = await _shiftRepo.getShiftsWithUser(
      userId: cakupan.jenis == JenisCakupan.semua ? null : cakupan.userId,
    );

    final kandidat = semua
        .where((e) => e.shift.id != session.shiftId)
        .toList();

    // Dimuat di depan, satu kueri untuk semua kartu. Selain lebih hemat, ini
    // yang membuat halaman tahu shift mana yang kosong — shift tanpa
    // pengeluaran tidak ada gunanya muncul di riwayat PENGELUARAN.
    final perShift = await _expenseRepo.getExpensesForShifts(
      kandidat.map((e) => e.shift.id).toList(),
    );
    final berisi = riwayatLayakTampil(
      semua: semua,
      perShift: perShift,
      shiftAktifSaya: session.shiftId,
    );

    if (mounted) {
      setState(() {
        _pastShifts = berisi;
        _expensesByShift = perShift;
        _loadingHistory = false;
      });
    }
  }

  Future<void> _showAddExpenseDialog() async {
    final session = SessionManager.instance.currentSession;
    if (session == null) return;

    // Pengeluaran selalu menempel ke sebuah shift. Tombolnya hanya tampil
    // saat shift berjalan; penjaga ini pengaman kalau sesi tanpa shift.
    final shiftId = session.shiftId;
    if (shiftId == null) {
      AppToast.error(
          context, 'Pengeluaran hanya bisa dicatat saat shift aktif (kasir).');
      return;
    }

    // Dialog hanya mengumpulkan isian; DB baru disentuh setelah dialog
    // benar-benar tertutup (stream yang memancar saat dialog masih beranimasi
    // keluar dulu memicu galat _dependents.isEmpty).
    final result = await tampilkanDialogPengeluaran(
      context,
      subjudul: 'Masukan Pengeluaran shift',
    );
    if (result == null || !mounted) return;

    await _expenseRepo.addExpense(
      shiftId: shiftId,
      userId: session.userId,
      description: result.keterangan,
      amount: result.amount,
      category: result.kategori.kode,
      qty: result.qty,
    );
  }

  /// Batalkan pengeluaran: pilih alasan, dan — untuk kasir — masukkan PIN
  /// owner. Pengeluaran tidak bisa diedit: yang salah dibatalkan lalu
  /// dicatat ulang.
  Future<void> _batalkan(Expense e) async {
    final berhasil =
        await batalkanPengeluaranLewatDialog(context, _expenseRepo, e);
    if (berhasil && mounted) _loadPastShifts();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final hasActiveShift = _activeShiftId != null;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      floatingActionButton: hasActiveShift
          ? FloatingActionButton(
              onPressed: _showAddExpenseDialog,
              backgroundColor: primaryColor,
              child: const Icon(Icons.add_rounded, color: Colors.white),
            )
          : null,
      body: SyncRefresh(
        sesudah: _loadPastShifts,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            // ---- Shift Aktif ----
            if (hasActiveShift) ...[
              _buildSectionHeader('Shift Aktif', isActive: true),
              const SizedBox(height: 8),
              StreamBuilder<List<Expense>>(
                // Gunakan field yang stabil, bukan buat stream baru tiap build
                stream: _expensesStream,
                builder: (context, snapshot) {
                  final expenses = snapshot.data ?? [];
                  // Yang dibatalkan tetap tampil, tapi TIDAK dihitung.
                  final total = expenses
                      .where((e) => e.deletedAt == null)
                      .fold<int>(0, (s, e) => s + e.amount);

                  return Column(
                    children: [
                      if (expenses.isEmpty)
                        _buildEmptyCard('Belum ada pengeluaran di shift ini.\nTap + untuk menambah.'),
                      for (final e in expenses)
                        _buildExpenseCard(e),
                      if (expenses.isNotEmpty)
                        _buildTotalCard(total, primaryColor),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        color: Colors.orange.shade700),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Tidak ada shift aktif saat ini.',
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // ---- Riwayat Shift Sebelumnya ----
            // Disembunyikan seluruhnya untuk kasir tanpa izin `view_history`:
            // ia hanya bekerja dengan shift yang sedang berjalan.
            if (_bolehLihatRiwayat) ...[
              _buildSectionHeader('Riwayat Shift'),
              const SizedBox(height: 8),
              if (_loadingHistory)
                const Center(child: CircularProgressIndicator())
              else if (_pastShifts.isEmpty)
                _buildEmptyCard('Belum ada pengeluaran tercatat.')
              else
                for (final entri in _pastShifts)
                  _ShiftHistoryCard(
                    entri: entri,
                    expenses: _expensesByShift[entri.shift.id] ?? const [],
                    namaAkun: _namaAkun,
                  ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, {bool isActive = false}) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        Container(
          width: 3,
          height: 18,
          decoration: BoxDecoration(
            color: primaryColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        if (isActive) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Colors.green.shade500,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  'Live',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.green.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEmptyCard(String message) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
      ),
    );
  }

  Widget _buildExpenseCard(Expense e) {
    final batal = e.deletedAt != null;
    // Aturannya di ExpenseRepository.bolehDibatalkan: owner semua, kasir
    // hanya miliknya di shift yang sedang berjalan.
    final bolehBatal = _expenseRepo.bolehDibatalkan(e);

    return Opacity(
      opacity: batal ? 0.6 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: batal ? Colors.grey.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.arrow_downward_rounded,
                  color: Colors.red, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.description,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  if (batal)
                    InfoPembatalan(
                      dibatalkanPada: e.deletedAt!,
                      alasan: e.cancelReason,
                      namaPembatal: e.namaPembatal(_namaAkun),
                      ringkas: true,
                    )
                  else
                    Text(
                      DateFormat('HH:mm').format(e.createdAt),
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '- Rp ${formatRupiah(e.amount)}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                    decoration: batal ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (batal) ...[
                  const SizedBox(height: 4),
                  const LabelDibatalkan(),
                ],
              ],
            ),
            if (bolehBatal) ...[
              const SizedBox(width: 4),
              IconButton(
                onPressed: () => _batalkan(e),
                tooltip: 'Batalkan pengeluaran',
                icon: Icon(Icons.block_rounded,
                    size: 18, color: Colors.red.shade400),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTotalCard(int total, Color primaryColor) {
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.account_balance_wallet_outlined,
                color: Colors.red.shade400, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Total Pengeluaran',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700),
            ),
          ),
          Text(
            'Rp ${formatRupiah(total)}',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.red.shade600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Widget kartu riwayat shift (bisa collapsed/expanded)
///
/// Pengeluaran DITERIMA sudah jadi, tidak dimuat sendiri. Halaman induk
/// memuatnya sekali untuk semua kartu — kalau tiap kartu memuat sendiri,
/// halaman tidak pernah tahu kartu mana yang kosong, dan nominalnya baru
/// terlihat setelah kartunya dibuka.
class _ShiftHistoryCard extends StatefulWidget {
  final ShiftEntry entri;
  final List<Expense> expenses;

  /// Untuk menampilkan siapa yang membatalkan.
  final Map<String, String> namaAkun;

  const _ShiftHistoryCard({
    required this.entri,
    required this.expenses,
    required this.namaAkun,
  });

  @override
  State<_ShiftHistoryCard> createState() => _ShiftHistoryCardState();
}

class _ShiftHistoryCardState extends State<_ShiftHistoryCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final shift = widget.entri.shift;
    final expenses = widget.expenses;
    // Yang dibatalkan tetap tampil, tapi TIDAK dihitung.
    final total = expenses
        .where((e) => e.deletedAt == null)
        .fold<int>(0, (s, e) => s + e.amount);
    final fmt = DateFormat('dd MMM yyyy');
    final timeFmt = DateFormat('HH:mm');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.work_history_rounded,
                        color: Colors.grey.shade500, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fmt.format(shift.startAt),
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${timeFmt.format(shift.startAt)} – ${shift.endAt != null ? timeFmt.format(shift.endAt!) : 'Berlangsung'}',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),
                  if (total > 0)
                    Text(
                      'Rp ${formatRupiah(total)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                  const SizedBox(width: 8),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: Colors.grey.shade400,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Divider(height: 1, color: Colors.grey.shade100),
            if (expenses.isEmpty)
              Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  'Tidak ada pengeluaran pada shift ini.',
                  style: TextStyle(
                      fontSize: 13, color: Colors.grey.shade500),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    for (final e in expenses)
                      Opacity(
                        opacity: e.deletedAt != null ? 0.6 : 1,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              const Icon(Icons.arrow_downward_rounded,
                                  size: 14, color: Colors.red),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      e.description,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                    if (e.deletedAt != null)
                                      InfoPembatalan(
                                        dibatalkanPada: e.deletedAt!,
                                        alasan: e.cancelReason,
                                        namaPembatal:
                                            e.namaPembatal(widget.namaAkun),
                                        ringkas: true,
                                      ),
                                  ],
                                ),
                              ),
                              Text(
                                'Rp ${formatRupiah(e.amount)}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.red,
                                  decoration: e.deletedAt != null
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Divider(color: Colors.grey.shade100),
                    Row(
                      children: [
                        Text('Total',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.red.shade700)),
                        const Spacer(),
                        Text(
                          'Rp ${formatRupiah(total)}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ---- Data model yang dikembalikan dialog ----

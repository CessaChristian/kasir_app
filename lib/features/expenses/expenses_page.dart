import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../utils/currency_formatter.dart';
import '../../data/db.dart';
import '../../data/app_database.dart';
import '../../shared/auth/session_manager.dart';
import '../../shared/widgets/app_toast.dart';

class ExpensesPage extends StatefulWidget {
  const ExpensesPage({super.key});

  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  List<Shift> _pastShifts = [];
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
      _expensesStream = db.watchExpensesByShift(_activeShiftId!);
    }
    _loadPastShifts();
  }

  Future<void> _loadPastShifts() async {
    final session = SessionManager.instance.currentSession;
    if (session == null) {
      setState(() => _loadingHistory = false);
      return;
    }

    final shifts = await db.getShiftsByUser(session.userId);
    // Pisahkan shift aktif (endAt null) dari history
    final pastShifts = shifts
        .where((s) => s.endAt != null && s.id != session.shiftId)
        .toList();

    if (mounted) {
      setState(() {
        _pastShifts = pastShifts;
        _loadingHistory = false;
      });
    }
  }

  Future<void> _showAddExpenseDialog() async {
    final session = SessionManager.instance.currentSession;
    if (session == null) return;

    // Dialog hanya mengumpulkan data — TIDAK ada operasi DB di dalamnya.
    // Setelah showDialog resolve, dialog sudah 100% hilang dari tree,
    // baru kemudian DB operation dijalankan. Ini mencegah _dependents.isEmpty
    // yang terjadi ketika stream emit sementara dialog masih animating out.
    final result = await showDialog<_ExpenseInput>(
      context: context,
      builder: (ctx) => _AddExpenseDialog(primaryColor: Theme.of(context).colorScheme.primary),
    );

    // Hanya lanjut jika user menekan Simpan (bukan Batal/dismiss)
    if (result == null || !mounted) return;

    // Dialog sudah sepenuhnya gone dari tree → aman memanggil DB
    await db.addExpense(
      shiftId: session.shiftId,
      userId: session.userId,
      description: result.desc,
      amount: result.amount,
    );
  }

  Future<void> _deleteExpense(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.delete_outline_rounded,
                    color: Colors.red.shade400, size: 28),
              ),
              const SizedBox(height: 16),
              const Text(
                'Hapus Pengeluaran?',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)),
              ),
              const SizedBox(height: 8),
              Text(
                'Data ini akan dihapus permanen dan tidak dapat dikembalikan.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.4),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.grey.shade700,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                      child: const Text('Batal', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade400,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Hapus', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed == true) {
      await db.deleteExpense(id);
    }
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
      body: ListView(
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
                final total =
                    expenses.fold<int>(0, (s, e) => s + e.amount);

                return Column(
                  children: [
                    if (expenses.isEmpty)
                      _buildEmptyCard('Belum ada pengeluaran di shift ini.\nTap + untuk menambah.'),
                    for (final e in expenses)
                      _buildExpenseCard(e, canDelete: true, canEdit: SessionManager.instance.canPerformActionOnRecord(
                        anyPermission: 'edit_any_expense',
                        ownPermission: 'edit_own_expense',
                        recordOwnerId: e.userId,
                      )),
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
          _buildSectionHeader('Riwayat Shift'),
          const SizedBox(height: 8),
          if (_loadingHistory)
            const Center(child: CircularProgressIndicator())
          else if (_pastShifts.isEmpty)
            _buildEmptyCard('Belum ada riwayat shift sebelumnya.')
          else
            for (final shift in _pastShifts)
              _ShiftHistoryCard(shift: shift),
        ],
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

  Widget _buildExpenseCard(Expense e, {required bool canDelete, bool canEdit = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
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
            child:
                const Icon(Icons.arrow_downward_rounded, color: Colors.red, size: 20),
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
                Text(
                  DateFormat('HH:mm').format(e.createdAt),
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          Text(
            '- Rp ${formatRupiah(e.amount)}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),
          if (canEdit) ...[
            const SizedBox(width: 4),
            IconButton(
              onPressed: () => _showEditExpenseDialog(e),
              icon: Icon(Icons.edit_outlined,
                  size: 18, color: Colors.blue.shade400),
              visualDensity: VisualDensity.compact,
            ),
          ],
          if (canDelete) ...[
            const SizedBox(width: 4),
            IconButton(
              onPressed: () => _deleteExpense(e.id),
              icon: Icon(Icons.delete_outline_rounded,
                  size: 20, color: Colors.red.shade300),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showEditExpenseDialog(Expense expense) async {
    final amountC = TextEditingController(text: expense.amount.toString());
    final descC = TextEditingController(text: expense.description);
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Pengeluaran'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: descC,
                decoration: const InputDecoration(
                  labelText: 'Keterangan',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: amountC,
                decoration: const InputDecoration(
                  labelText: 'Jumlah (Rp)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Wajib diisi';
                  if (int.tryParse(v) == null || int.parse(v) <= 0) {
                    return 'Masukkan angka valid';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await db.updateExpense(
        id: expense.id,
        amount: int.parse(amountC.text),
        description: descC.text.trim(),
      );
      if (mounted) AppToast.success(context, 'Pengeluaran berhasil diupdate');
    } catch (e) {
      if (mounted) AppToast.error(context, 'Gagal update: $e');
    }
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
class _ShiftHistoryCard extends StatefulWidget {
  final Shift shift;

  const _ShiftHistoryCard({required this.shift});

  @override
  State<_ShiftHistoryCard> createState() => _ShiftHistoryCardState();
}

class _ShiftHistoryCardState extends State<_ShiftHistoryCard> {
  bool _expanded = false;
  List<Expense> _expenses = [];
  bool _loaded = false;

  Future<void> _loadExpenses() async {
    if (_loaded) return;
    final result = await db.getExpensesByShift(widget.shift.id);
    if (mounted) {
      setState(() {
        _expenses = result;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final shift = widget.shift;
    final total = _expenses.fold<int>(0, (s, e) => s + e.amount);
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
            onTap: () async {
              await _loadExpenses();
              setState(() => _expanded = !_expanded);
            },
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
                  if (_loaded && total > 0)
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
            if (!_loaded)
              const Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              )
            else if (_expenses.isEmpty)
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
                    for (final e in _expenses)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            const Icon(Icons.arrow_downward_rounded,
                                size: 14, color: Colors.red),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                e.description,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            Text(
                              'Rp ${formatRupiah(e.amount)}',
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.red),
                            ),
                          ],
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
class _ExpenseInput {
  final String desc;
  final int amount;
  const _ExpenseInput({required this.desc, required this.amount});
}

// ---- Dialog mandiri: hanya kumpulkan data, tidak sentuh DB ----
class _AddExpenseDialog extends StatefulWidget {
  final Color primaryColor;
  const _AddExpenseDialog({required this.primaryColor});

  @override
  State<_AddExpenseDialog> createState() => _AddExpenseDialogState();
}

class _AddExpenseDialogState extends State<_AddExpenseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _descC = TextEditingController();
  final _amountC = TextEditingController();

  @override
  void dispose() {
    _descC.dispose();
    _amountC.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      _ExpenseInput(
        desc: _descC.text.trim(),
        amount: parseRupiah(_amountC.text) ?? 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = widget.primaryColor;
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.add_card_rounded, color: primary),
                  ),
                  const SizedBox(width: 14),
                  const Text(
                    'Tambah Pengeluaran',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _descC,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Keterangan',
                  hintText: 'Contoh: Beli es batu',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  prefixIcon: const Icon(Icons.description_outlined),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _amountC,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  RupiahInputFormatter(),
                ],
                decoration: InputDecoration(
                  labelText: 'Jumlah',
                  prefixText: 'Rp ',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  prefixIcon: const Icon(Icons.payments_outlined),
                ),
                validator: (v) {
                  final amount = parseRupiah(v ?? '');
                  if (amount == null || amount <= 0) return 'Masukkan jumlah valid';
                  return null;
                },
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.grey.shade700,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                      child: const Text('Batal'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Simpan',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

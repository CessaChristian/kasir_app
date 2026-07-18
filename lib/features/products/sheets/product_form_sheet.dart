import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../../data/db.dart';
import '../../../data/app_database.dart';
import '../../../utils/currency_formatter.dart';
import '../category_manager.dart';

class FormResult {
  final String name;
  final int price;
  final String? barcode;
  final String? categoryId;
  final bool trackStock;
  final int? stock;
  final bool hasSpicyOption;
  final String? imagePath;

  FormResult({
    required this.name,
    required this.price,
    required this.barcode,
    this.categoryId,
    required this.trackStock,
    required this.stock,
    required this.hasSpicyOption,
    this.imagePath,
  });
}

class ProductFormSheet extends StatefulWidget {
  final Product? editing;

  const ProductFormSheet({super.key, this.editing});

  @override
  State<ProductFormSheet> createState() => _ProductFormSheetState();
}

class _ProductFormSheetState extends State<ProductFormSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameC;
  late final TextEditingController _priceC;
  late final TextEditingController _barcodeC;
  late final TextEditingController _stockC;

  Category? _selectedCategory;
  bool _categoryInitialized = false;
  bool _trackStock = false;
  bool _hasSpicyOption = false;
  String? _imagePath;

  @override
  void initState() {
    super.initState();
    final p = widget.editing;
    _nameC = TextEditingController(text: p?.name ?? '');
    _priceC = TextEditingController(
      text: p != null ? formatRupiah(p.price) : '',
    );
    _barcodeC = TextEditingController(text: p?.barcode ?? '');
    _trackStock = p?.trackStock ?? false;
    _stockC = TextEditingController(text: p?.stock?.toString() ?? '');
    _hasSpicyOption = p?.hasSpicyOption ?? false;
    _imagePath = p?.imagePath;
    // LOW-2: rebuild saat stok berubah supaya hint "stok 0 = habis"
    // muncul/hilang real-time.
    _stockC.addListener(_onStockChanged);
  }

  void _onStockChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _stockC.removeListener(_onStockChanged);
    _nameC.dispose();
    _priceC.dispose();
    _barcodeC.dispose();
    _stockC.dispose();
    super.dispose();
  }

  int? _int(String s) => int.tryParse(s.trim());

  // Ada input yang akan hilang kalau sheet ditutup?
  bool get _isDirty =>
      _nameC.text.trim().isNotEmpty ||
      _priceC.text.trim().isNotEmpty ||
      _barcodeC.text.trim().isNotEmpty ||
      _stockC.text.trim().isNotEmpty ||
      _selectedCategory != null;

  // True saat pop berasal dari submit sukses — lewati dialog konfirmasi.
  bool _saving = false;

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final price = parseRupiah(_priceC.text);
    if (price == null || price <= 0) return;

    _saving = true;
    Navigator.pop(
      context,
      FormResult(
        name: _nameC.text.trim(),
        price: price,
        barcode: _barcodeC.text.trim().isEmpty ? null : _barcodeC.text.trim(),
        categoryId: _selectedCategory?.id,
        trackStock: _trackStock,
        stock: _trackStock ? (_int(_stockC.text) ?? 0) : null,
        hasSpicyOption: _hasSpicyOption,
        imagePath: _imagePath,
      ),
    );
  }

  Future<void> _pickImage() async {
    final primaryColor = Theme.of(context).colorScheme.primary;

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Pilih Sumber Foto',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.camera_alt_rounded, color: primaryColor),
                ),
                title: const Text('Kamera'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.photo_library_rounded, color: primaryColor),
                ),
                title: const Text('Galeri'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );

    if (source == null) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 80,
    );

    if (picked != null && mounted) {
      setState(() => _imagePath = picked.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final isEditing = widget.editing != null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_saving || !_isDirty) {
          Navigator.of(context).pop();
          return;
        }
        final keluar = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Buang perubahan?'),
            content: const Text('Data produk yang sudah diisi akan hilang.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Lanjut Mengisi'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Buang', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
        if (keluar == true && context.mounted) Navigator.of(context).pop();
      },
      child: Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + inset),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 14),

                // Header
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: primaryColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isEditing
                            ? Icons.edit_rounded
                            : Icons.add_business_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEditing ? 'Edit Produk' : 'Tambah Produk',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A1A),
                            ),
                          ),
                          Text(
                            isEditing
                                ? 'Perbarui detail produk'
                                : 'Isi detail produk baru',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // ---- Foto Produk ----
                _buildImagePicker(primaryColor),
                const SizedBox(height: 14),

                // Form fields
                _buildTextField(
                  controller: _nameC,
                  label: 'Nama produk',
                  hint: 'Masukkan nama produk',
                  icon: Icons.inventory_2_outlined,
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Nama wajib diisi' : null,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 10),

                _buildTextField(
                  controller: _priceC,
                  label: 'Harga',
                  hint: '0',
                  icon: Icons.payments_outlined,
                  prefixText: 'Rp ',
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    RupiahInputFormatter(),
                  ],
                  validator: (v) {
                    final price = parseRupiah(v ?? '');
                    if (price == null || price <= 0) return 'Harga tidak valid';
                    return null;
                  },
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 10),

                _buildTextField(
                  controller: _barcodeC,
                  label: 'Barcode (opsional)',
                  hint: 'Scan atau ketik barcode',
                  icon: Icons.qr_code_rounded,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 10),

                // Category Picker
                StreamBuilder<List<Category>>(
                  stream: db.watchCategories(),
                  builder: (context, snapshot) {
                    final categories = snapshot.data ?? [];

                    if (!_categoryInitialized &&
                        _selectedCategory == null &&
                        widget.editing?.categoryId != null &&
                        categories.isNotEmpty) {
                      _categoryInitialized = true;
                      final match = categories
                          .where((c) => c.id == widget.editing!.categoryId)
                          .firstOrNull;
                      if (match != null) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) setState(() => _selectedCategory = match);
                        });
                      }
                    }

                    final selIcon = IconData(
                      _selectedCategory?.iconCodepoint ??
                          Icons.category_rounded.codePoint,
                      fontFamily: 'MaterialIcons',
                    );

                    return Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _showCategorySheet(categories),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              child: Row(
                                children: [
                                  Icon(selIcon, color: primaryColor, size: 22),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Kategori',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade600),
                                        ),
                                        const SizedBox(height: 1),
                                        Text(
                                          _selectedCategory?.name ??
                                              'Pilih kategori',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                            color: _selectedCategory != null
                                                ? const Color(0xFF1A1A1A)
                                                : Colors.grey.shade400,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.keyboard_arrow_down_rounded,
                                      color: Colors.grey.shade500),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: () => CategoryManager.show(context),
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: primaryColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: primaryColor.withValues(alpha: 0.3)),
                            ),
                            child: Icon(Icons.list_alt_rounded,
                                color: primaryColor, size: 20),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 10),

                // ---- Pilihan Level Pedas ----
                _buildToggle(
                  title: 'Ada pilihan level pedas',
                  subtitle: _hasSpicyOption
                      ? 'Tidak Pedas / Normal / Pedas'
                      : 'Produk tidak punya pilihan kepedasan',
                  icon: Icons.local_fire_department_rounded,
                  value: _hasSpicyOption,
                  primaryColor: primaryColor,
                  activeColor: Colors.deepOrange,
                  onChanged: (v) => setState(() => _hasSpicyOption = v),
                ),
                const SizedBox(height: 8),

                // ---- Lacak Stok ----
                _buildToggle(
                  title: 'Lacak stok',
                  subtitle: _trackStock
                      ? 'Stok berkurang otomatis saat penjualan'
                      : 'Stok tidak akan dilacak',
                  icon: _trackStock
                      ? Icons.inventory_rounded
                      : Icons.inventory_outlined,
                  value: _trackStock,
                  primaryColor: primaryColor,
                  activeColor: primaryColor,
                  onChanged: (v) => setState(() => _trackStock = v),
                ),

                // Stock input
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  child: _trackStock
                      ? Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildTextField(
                                controller: _stockC,
                                label: 'Jumlah stok',
                                hint: '0',
                                icon: Icons.numbers_rounded,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly
                                ],
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _submit(),
                                // LOW-2: cegah stok kosong/0 disimpan tanpa
                                // disadari — produk akan langsung tampil
                                // sebagai "habis" dan tidak bisa dijual.
                                validator: (v) {
                                  final s = (v ?? '').trim();
                                  if (s.isEmpty) {
                                    return 'Isi jumlah stok awal';
                                  }
                                  final n = int.tryParse(s);
                                  if (n == null) return 'Angka tidak valid';
                                  if (n < 0) return 'Stok tidak boleh negatif';
                                  return null;
                                },
                              ),
                              if ((_int(_stockC.text) ?? 0) == 0 &&
                                  _stockC.text.trim().isNotEmpty)
                                Padding(
                                  padding:
                                      const EdgeInsets.only(top: 6, left: 4),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.info_outline,
                                        size: 14,
                                        color: Colors.orange.shade700,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          'Stok 0 — produk akan langsung tampil sebagai habis.',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.orange.shade700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),

                const SizedBox(height: 20),

                // Submit button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isEditing
                              ? Icons.save_rounded
                              : Icons.add_rounded,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isEditing ? 'Simpan Perubahan' : 'Tambah Produk',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  void _showCategorySheet(List<Category> categories) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.fromLTRB(0, 12, 0, 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.category_rounded,
                        color: primaryColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Pilih Kategori',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A1A)),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: Colors.grey.shade200),
            // Opsi tanpa kategori
            _categoryOption(
              icon: Icons.block_rounded,
              name: 'Tanpa Kategori',
              isSelected: _selectedCategory == null,
              primaryColor: primaryColor,
              onTap: () {
                setState(() => _selectedCategory = null);
                Navigator.pop(context);
                // Cegah keyboard muncul lagi (fokus balik ke field teks).
                FocusManager.instance.primaryFocus?.unfocus();
              },
            ),
            Divider(height: 1, color: Colors.grey.shade100),
            // List kategori
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: categories.length,
                separatorBuilder: (_, i) =>
                    Divider(height: 1, color: Colors.grey.shade100),
                itemBuilder: (_, i) {
                  final c = categories[i];
                  final icon = IconData(
                    c.iconCodepoint ?? Icons.category_rounded.codePoint,
                    fontFamily: 'MaterialIcons',
                  );
                  return _categoryOption(
                    icon: icon,
                    name: c.name,
                    isSelected: _selectedCategory?.id == c.id,
                    primaryColor: primaryColor,
                    onTap: () {
                      setState(() => _selectedCategory = c);
                      Navigator.pop(context);
                      // Cegah keyboard muncul lagi (fokus balik ke field teks).
                      FocusManager.instance.primaryFocus?.unfocus();
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _categoryOption({
    required IconData icon,
    required String name,
    required bool isSelected,
    required Color primaryColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: isSelected
          ? primaryColor.withValues(alpha: 0.06)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isSelected
                      ? primaryColor.withValues(alpha: 0.12)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon,
                    color: isSelected ? primaryColor : Colors.grey.shade600,
                    size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected
                        ? primaryColor
                        : const Color(0xFF1A1A1A),
                  ),
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle_rounded,
                    color: primaryColor, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImagePicker(Color primaryColor) {
    final hasImage =
        _imagePath != null && File(_imagePath!).existsSync();

    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        width: double.infinity,
        height: 100,
        decoration: BoxDecoration(
          color: hasImage ? Colors.transparent : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasImage
                ? Colors.grey.shade300
                : primaryColor.withValues(alpha: 0.4),
            style: BorderStyle.solid,
          ),
        ),
        child: hasImage
            ? Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Image.file(
                      File(_imagePath!),
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Row(
                      children: [
                        _imageActionBtn(
                          icon: Icons.edit_rounded,
                          onTap: _pickImage,
                          color: primaryColor,
                        ),
                        const SizedBox(width: 6),
                        _imageActionBtn(
                          icon: Icons.close_rounded,
                          onTap: () => setState(() => _imagePath = null),
                          color: Colors.red,
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 28,
                    color: primaryColor.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tambah Foto Produk',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: primaryColor.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Opsional — tap untuk pilih foto',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Widget _imageActionBtn({
    required IconData icon,
    required VoidCallback onTap,
    required Color color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 4,
            ),
          ],
        ),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }

  Widget _buildToggle({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required Color primaryColor,
    required Color activeColor,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: value
            ? activeColor.withValues(alpha: 0.08)
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: value
              ? activeColor.withValues(alpha: 0.3)
              : Colors.grey.shade200,
        ),
      ),
      child: SwitchListTile(
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: value ? activeColor : const Color(0xFF1A1A1A),
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        secondary: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: value ? activeColor : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
        value: value,
        onChanged: onChanged,
        activeThumbColor: activeColor,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    String? prefixText,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    TextInputAction? textInputAction,
    void Function(String)? onFieldSubmitted,
  }) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        validator: validator,
        textInputAction: textInputAction,
        onFieldSubmitted: onFieldSubmitted,
        style: const TextStyle(fontSize: 15, color: Color(0xFF1A1A1A)),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.grey.shade600),
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade400),
          prefixIcon: Icon(icon, color: primaryColor),
          prefixText: prefixText,
          prefixStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: Color(0xFF1A1A1A),
          ),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          errorStyle: const TextStyle(height: 0),
        ),
      ),
    );
  }
}

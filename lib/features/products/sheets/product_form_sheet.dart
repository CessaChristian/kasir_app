import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../data/db.dart';
import '../../../data/app_database.dart';
import '../../../utils/currency_formatter.dart';
import '../category_manager.dart';

/// Result data dari product form
class FormResult {
  final String name;
  final int price;
  final String? barcode;
  final String? categoryId;
  final bool trackStock;
  final int? stock;

  FormResult({
    required this.name,
    required this.price,
    required this.barcode,
    this.categoryId,
    required this.trackStock,
    required this.stock,
  });
}

/// Bottom sheet untuk add/edit produk
/// Returns FormResult atau null jika dibatalkan
class ProductFormSheet extends StatefulWidget {
  final Product? editing;

  const ProductFormSheet({
    super.key,
    this.editing,
  });

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
  bool _trackStock = false;

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
  }

  @override
  void dispose() {
    _nameC.dispose();
    _priceC.dispose();
    _barcodeC.dispose();
    _stockC.dispose();
    super.dispose();
  }

  int? _int(String s) => int.tryParse(s.trim());

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final price = parseRupiah(_priceC.text);

    Navigator.pop(
      context,
      FormResult(
        name: _nameC.text.trim(),
        price: price!,
        barcode: _barcodeC.text.trim().isEmpty ? null : _barcodeC.text.trim(),
        categoryId: _selectedCategory?.id,
        trackStock: _trackStock,
        stock: _trackStock ? (_int(_stockC.text) ?? 0) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final isEditing = widget.editing != null;

    return Container(
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
                const SizedBox(height: 20),
                
                // Header
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: primaryColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isEditing ? Icons.edit_rounded : Icons.add_business_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEditing ? 'Edit Produk' : 'Tambah Produk',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A1A),
                            ),
                          ),
                          Text(
                            isEditing ? 'Perbarui detail produk' : 'Isi detail produk baru',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                
                // Form fields
                _buildTextField(
                  controller: _nameC,
                  label: 'Nama produk',
                  hint: 'Masukkan nama produk',
                  icon: Icons.inventory_2_outlined,
                  validator: (v) => v == null || v.isEmpty ? 'Nama wajib diisi' : null,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                
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
                const SizedBox(height: 16),
                
                _buildTextField(
                  controller: _barcodeC,
                  label: 'Barcode (opsional)',
                  hint: 'Scan atau ketik barcode',
                  icon: Icons.qr_code_rounded,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                
                // Category Dropdown
                StreamBuilder<List<Category>>(
                  stream: db.watchCategories(),
                  builder: (context, snapshot) {
                    final categories = snapshot.data ?? [];

                    if (_selectedCategory == null && widget.editing?.categoryId != null && categories.isNotEmpty) {
                      final match = categories.where((c) => c.id == widget.editing!.categoryId).firstOrNull;
                      if (match != null) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) setState(() => _selectedCategory = match);
                        });
                      }
                    }

                    return Row(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: DropdownButtonFormField<Category>(
                              initialValue: _selectedCategory,
                              decoration: InputDecoration(
                                labelText: 'Kategori',
                                labelStyle: TextStyle(color: Colors.grey.shade600),
                                prefixIcon: Icon(Icons.category_outlined, color: primaryColor),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              ),
                              dropdownColor: Colors.white,
                              items: categories.map((c) {
                                return DropdownMenuItem(
                                  value: c,
                                  child: Text(c.name),
                                );
                              }).toList(),
                              onChanged: (v) => setState(() => _selectedCategory = v),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: () => CategoryManager.show(context),
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: primaryColor.withValues(alpha:0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: primaryColor.withValues(alpha:0.3)),
                            ),
                            child: Icon(
                              Icons.list_alt_rounded,
                              color: primaryColor,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 20),
                
                // Track stock switch
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: _trackStock ? primaryColor.withValues(alpha:0.08) : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _trackStock ? primaryColor.withValues(alpha:0.3) : Colors.grey.shade200,
                    ),
                  ),
                  child: SwitchListTile(
                    title: Text(
                      'Lacak stok',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: _trackStock ? primaryColor : const Color(0xFF1A1A1A),
                      ),
                    ),
                    subtitle: Text(
                      _trackStock
                          ? 'Stok akan berkurang otomatis saat penjualan'
                          : 'Stok tidak akan dilacak',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    secondary: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _trackStock ? primaryColor : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _trackStock ? Icons.inventory_rounded : Icons.inventory_outlined,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    value: _trackStock,
                    onChanged: (v) => setState(() => _trackStock = v),
                    activeThumbColor: primaryColor,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                
                // Stock input (animated)
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  child: _trackStock
                      ? Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: _buildTextField(
                            controller: _stockC,
                            label: 'Jumlah stok',
                            hint: '0',
                            icon: Icons.numbers_rounded,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _submit(),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                
                const SizedBox(height: 28),
                
                // Submit button
                SizedBox(
                  width: double.infinity,
                  height: 52,
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
                          isEditing ? Icons.save_rounded : Icons.add_rounded,
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
        style: const TextStyle(
          fontSize: 15,
          color: Color(0xFF1A1A1A),
        ),
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
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          errorStyle: const TextStyle(height: 0),
        ),
      ),
    );
  }
}

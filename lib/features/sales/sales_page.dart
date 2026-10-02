import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/db.dart';
import '../../data/sync/sync_otomatis.dart';
import '../../data/sync/sync_service.dart';
import '../../shared/widgets/label_sinkron.dart';
import 'repositories/sales_repository.dart';
import '../products/repositories/product_repository.dart';
import '../../data/app_database.dart';
import '../../data/uuid_helper.dart';
import '../../utils/currency_formatter.dart';
import '../../shared/auth/session_manager.dart';
import 'dart:io';

import '../../shared/services/image_storage_service.dart';
import '../../shared/widgets/sync_refresh.dart';
import 'models/keranjang.dart';
import 'models/pilihan_produk.dart';
import 'sheets/pilihan_produk_sheet.dart';
import 'cart_page.dart';
import '../../shared/widgets/error_state_widget.dart';
import '../../shared/widgets/ikon_pilihan_produk.dart';

class SalesPage extends StatefulWidget {
  const SalesPage({super.key});

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> with TickerProviderStateMixin {
  final _salesRepo = SalesRepository(db);
  final _productRepo = ProductRepository(db);
  final _keranjang = Keranjang();
  bool _keranjangTadinyaBerisi = false;
  final Set<String> _addingProducts = {};
  // C4: Cache hasil File.existsSync agar tidak blocking main thread setiap rebuild
  final Map<String, bool> _imageExistsCache = {};
  String? _selectedCategoryId;
  String _searchQuery = '';
  final GlobalKey _cartIconKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Membuka halaman kasir adalah momen alami untuk memastikan harganya
    // terbaru — jeda minimum di dalam penjadwal yang mencegah ini menembak
    // berulang kali saat berpindah-pindah halaman.
    SyncOtomatis.instance.picu('halaman kasir dibuka');
    SyncService.instance.terakhirBerhasil.addListener(_sesudahSync);
    _keranjang.addListener(_keranjangBerubah);
  }

  /// Satu titik untuk SEMUA perubahan keranjang — dari halaman ini maupun
  /// dari halaman Keranjang yang memakai objek yang sama.
  void _keranjangBerubah() {
    final berisi = !_keranjang.isEmpty;
    // Sinkron otomatis ditunda selama pesanan disusun.
    SyncOtomatis.instance.sedangMenyusunPesanan = berisi;
    // Keranjang yang baru saja kosong adalah titik teraman untuk menyegarkan.
    // Tanpa ini sinkron yang tertunda bisa tertahan sepanjang jam ramai,
    // karena keranjang nyaris tidak pernah kosong lebih dari sesaat.
    if (_keranjangTadinyaBerisi && !berisi) {
      SyncOtomatis.instance.lanjutkanYangTertunda();
    }
    _keranjangTadinyaBerisi = berisi;
    if (mounted) setState(() {});
  }

  /// Buang ingatan "gambar ini tidak ada" setiap kali sinkronisasi selesai.
  ///
  /// [_imageExistsCache] menyimpan hasil `File.existsSync()` supaya disk tidak
  /// diperiksa setiap kali layar digambar ulang. Tapi sinkronisasi gambar
  /// MENGUNDUH berkas baru — dan tanpa dibuang, jawaban "tidak ada" yang
  /// terlanjur tersimpan membuat gambar yang baru saja sampai tetap tidak
  /// muncul sampai halamannya dibuka ulang.
  void _sesudahSync() {
    if (!mounted || _imageExistsCache.isEmpty) return;
    setState(_imageExistsCache.clear);
  }

  @override
  void dispose() {
    SyncService.instance.terakhirBerhasil.removeListener(_sesudahSync);
    _keranjang
      ..removeListener(_keranjangBerubah)
      ..dispose();
    // Kalau tidak dibersihkan, meninggalkan halaman dengan keranjang berisi
    // membuat penjadwal mengira pesanan masih disusun — dan sinkron otomatis
    // berhenti selamanya.
    SyncOtomatis.instance.sedangMenyusunPesanan = false;
    super.dispose();
  }

  bool _imageExists(String? path) {
    if (path == null || path.isEmpty) return false;
    return _imageExistsCache.putIfAbsent(
        path, () => ImageStorageService.adaSync(path));
  }

  Future<void> _playAddToCartAnimation(Offset startPosition) async {
    HapticFeedback.lightImpact();

    final cartIconContext = _cartIconKey.currentContext;
    if (cartIconContext == null) return;

    final cartIconBox = cartIconContext.findRenderObject() as RenderBox;
    final cartIconPosition = cartIconBox.localToGlobal(Offset.zero);
    final cartIconCenter = Offset(
      cartIconPosition.dx + cartIconBox.size.width / 2,
      cartIconPosition.dy + cartIconBox.size.height / 2,
    );

    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    final animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    final positionAnimation =
        Tween<Offset>(begin: startPosition, end: cartIconCenter).animate(
          CurvedAnimation(parent: animationController, curve: Curves.easeInOut),
        );

    final scaleAnimation = Tween<double>(begin: 1.0, end: 0.3).animate(
      CurvedAnimation(parent: animationController, curve: Curves.easeInOut),
    );

    final opacityAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: animationController,
        curve: const Interval(0.6, 1.0, curve: Curves.easeOut),
      ),
    );

    final primaryColor = Theme.of(context).colorScheme.primary;

    overlayEntry = OverlayEntry(
      builder: (context) => AnimatedBuilder(
        animation: animationController,
        builder: (context, child) {
          return Positioned(
            left: positionAnimation.value.dx - 16,
            top: positionAnimation.value.dy - 16,
            child: Transform.scale(
              scale: scaleAnimation.value,
              child: Opacity(
                opacity: opacityAnimation.value,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: primaryColor,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );

    overlay.insert(overlayEntry);
    await animationController.forward();
    overlayEntry.remove();
    animationController.dispose();
  }

  Future<void> _addToCart(Product p, Offset tapPosition) async {
    // Lock per-produk: cegah tap ganda sebelum setState selesai
    if (_addingProducts.contains(p.id)) return;
    _addingProducts.add(p.id);

    try {
      // Produk yang punya pilihan ditanyakan SETIAP kali diketuk: pilihan
      // berbeda jadi baris baru. Menambah jumlah dengan pilihan yang sama
      // dilakukan lewat tombol + di keranjang.
      String? notes;
      if (kelompokUntuk(p).isNotEmpty) {
        notes = await tanyaPilihanProduk(context, p);
        if (notes == null) return; // lembar ditutup = batal
      }

      if (!mounted) return;
      await _playAddToCartAnimation(tapPosition);
      if (!mounted) return;
      _keranjang.tambah(
        idProduk: p.id,
        nama: p.name,
        harga: p.price,
        catatan: notes,
      );
    } finally {
      _addingProducts.remove(p.id);
    }
  }

  Future<void> _checkout(
    PaymentMethod paymentMethod,
    int? cashReceived,
    String orderType,
  ) async {
    final isCash = paymentMethod == PaymentMethod.cash;

    try {
      final session = SessionManager.instance.currentSession;

      await _salesRepo.createSale(
        transactionId: newUuid(),
        lines: _keranjang.baris,
        paymentMethod: isCash ? 'cash' : 'qris',
        orderType: orderType,
        cashReceived: cashReceived,
        cashierUserId: session?.userId,
        shiftId: session?.shiftId,
      );

      _keranjang.kosongkan();
    } catch (e) {
      rethrow;
    }
  }

  void _openCart() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CartPage(
        keranjang: _keranjang,
        onCheckout: _checkout,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          // Seberapa segar datanya. Ditaruh paling atas di halaman kasir
          // karena di sinilah harga basi merugikan uang sungguhan.
          const Align(
            alignment: Alignment.centerLeft,
            child: LabelSinkron(),
          ),

          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                onChanged: (value) => setState(() => _searchQuery = value),
                style: const TextStyle(fontSize: 15, color: Color(0xFF1A1A1A)),
                decoration: InputDecoration(
                  hintText: 'Cari produk...',
                  hintStyle: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 15,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: primaryColor,
                    size: 22,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.close_rounded,
                            color: Colors.grey.shade500,
                            size: 20,
                          ),
                          onPressed: () => setState(() => _searchQuery = ''),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
            ),
          ),

          // Category Filter
          SizedBox(
            height: 48,
            child: StreamBuilder<List<Category>>(
              stream: _productRepo.watchCategories(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return const SizedBox.shrink();
                final categories = snapshot.data ?? [];
                return ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _buildCategoryChip(
                      label: 'Semua',
                      isSelected: _selectedCategoryId == null,
                      onTap: () => setState(() => _selectedCategoryId = null),
                    ),
                    const SizedBox(width: 8),
                    for (final c in categories) ...[
                      _buildCategoryChip(
                        label: c.name,
                        isSelected: _selectedCategoryId == c.id,
                        onTap: () => setState(() => _selectedCategoryId = c.id),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                );
              },
            ),
          ),

          const SizedBox(height: 8),

          // Product Grid
          Expanded(
            child: StreamBuilder<List<Product>>(
              stream: _productRepo.watchProducts(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return ErrorStateWidget(
                    title: 'Gagal memuat produk',
                    onRetry: () => setState(() {}),
                  );
                }
                var items = snapshot.data ?? [];

                if (_selectedCategoryId != null) {
                  items = items
                      .where((p) => p.categoryId == _selectedCategoryId)
                      .toList();
                }

                if (_searchQuery.isNotEmpty) {
                  final query = _searchQuery.toLowerCase();
                  items = items
                      .where((p) => p.name.toLowerCase().contains(query))
                      .toList();
                }

                if (items.isEmpty) return _buildEmptyState();

                return LayoutBuilder(
                  builder: (context, constraints) {
                    const cols = 3;
                    const spacing = 10.0;
                    const hPad = 32.0;
                    final cardWidth =
                        (constraints.maxWidth - hPad - (cols - 1) * spacing) /
                        cols;

                    // Kelompokkan produk menjadi baris-baris @3
                    final rows = <List<Product>>[];
                    for (int i = 0; i < items.length; i += cols) {
                      rows.add(
                        items.sublist(i, (i + cols).clamp(0, items.length)),
                      );
                    }

                    // C4: Pre-compute pakai cache — existsSync hanya dipanggil
                    // sekali per file selama lifecycle widget, tidak per rebuild.
                    final rowHasImageList = rows
                        .map((rowItems) =>
                            rowItems.any((p) => _imageExists(p.imagePath)))
                        .toList();

                    return SyncRefresh(
                      child: ListView.builder(
                        // Tanpa ini, gerakan menarik tidak terbaca saat
                        // produknya sedikit dan layar belum penuh.
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                        itemCount: rows.length,
                        itemBuilder: (_, rowIdx) {
                          final rowItems = rows[rowIdx];
                          final rowHasImage = rowHasImageList[rowIdx];
                          final noImageHeight = cardWidth / 1.12;

                          final rowWidget = Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (int i = 0; i < cols; i++) ...[
                                if (i > 0) const SizedBox(width: spacing),
                                Expanded(
                                  child: i < rowItems.length
                                      ? _buildProductCard(
                                          rowItems[i],
                                          rowHasImage: rowHasImage,
                                          cardWidth: cardWidth,
                                        )
                                      : const SizedBox(),
                                ),
                              ],
                            ],
                          );

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            // Baris bergambar: tinggi mengikuti konten (IntrinsicHeight)
                            // Baris tanpa gambar: tinggi tetap & kompak
                            child: rowHasImage
                                ? IntrinsicHeight(child: rowWidget)
                                : SizedBox(height: noImageHeight, child: rowWidget),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildCartBar(),
    );
  }

  Widget _buildCategoryChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isSelected ? primaryColor : Colors.grey.shade300,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: primaryColor.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected ? Colors.white : Colors.grey.shade700,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProductCard(
    Product p, {
    required bool rowHasImage,
    required double cardWidth,
  }) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final hasImage = ImageStorageService.adaSync(p.imagePath);
    final imgHeight = cardWidth * 0.60;

    Widget content;

    if (hasImage) {
      // === Kartu DENGAN gambar ===
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.file(
              File(ImageStorageService.lokasiPenuhSync(p.imagePath!)),
              height: imgHeight,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, e, s) => const SizedBox.shrink(),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            p.name,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  'Rp ${formatRupiah(p.price)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IkonPilihanProduk(produk: p),
            ],
          ),
        ],
      );
    } else {
      // === Kartu TANPA gambar — nama di tengah, harga di bawah ===
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Center(
              child: Text(
                p.name,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  'Rp ${formatRupiah(p.price)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IkonPilihanProduk(produk: p),
            ],
          ),
        ],
      );
    }

    return GestureDetector(
      onTapDown: (details) => _addToCart(p, details.globalPosition),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.grey.shade200,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: content,
        ),
      ),
    );
  }


  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.inventory_2_outlined,
              size: 32,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty
                ? 'Produk tidak ditemukan'
                : (_selectedCategoryId != null
                      ? 'Tidak ada produk di kategori ini'
                      : 'Belum ada produk'),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartBar() {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: InkWell(
          onTap: _openCart,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  key: _cartIconKey,
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: primaryColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Stack(
                    children: [
                      const Center(
                        child: Icon(
                          Icons.shopping_cart_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      if (!_keranjang.isEmpty)
                        Positioned(
                          right: 4,
                          top: 4,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${_keranjang.jumlahBaris}',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: primaryColor,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Total Belanja',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Rp ${formatRupiah(_keranjang.total)}',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 20,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

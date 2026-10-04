import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../data/sync/sync_otomatis.dart';

import '../../../shared/services/image_storage_service.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../data/db.dart';
import '../repositories/product_repository.dart';
import '../../../data/app_database.dart';
import '../../../shared/constants/category_icons.dart';
import '../../../utils/currency_formatter.dart';
import '../../../shared/ui/bulatan_pilihan.dart';
import '../../../shared/ui/kolom_isian.dart';
import '../../../shared/ui/lembar_konfirmasi.dart';
import '../../../shared/ui/lembar_pilih.dart';
import '../../../shared/ui/pegang_lembar.dart';
import '../../../shared/ui/sakelar_pilihan.dart';
import '../../../shared/ui/teks_teras.dart';
import '../../../shared/ui/warna_teras.dart';
import '../../sales/models/pilihan_produk.dart';

class FormResult {
  final String name;
  final int price;
  final String? categoryId;
  final bool hasSpicyOption;
  final bool hasSweetOption;
  final bool hasIceOption;
  final String? imagePath;

  FormResult({
    required this.name,
    required this.price,
    this.categoryId,
    required this.hasSpicyOption,
    required this.hasSweetOption,
    required this.hasIceOption,
    this.imagePath,
  });
}

/// Pesan galat form produk (desain menampilkannya satu baris di atas
/// tombol simpan), atau null kalau isian sah.
String? galatFormProduk({required String nama, required String hargaTeks}) {
  if (nama.trim().isEmpty) return 'Nama produk wajib diisi';
  final harga = parseRupiah(hargaTeks);
  if (harga == null || harga <= 0) return 'Harga wajib diisi';
  return null;
}

class ProductFormSheet extends StatefulWidget {
  final Product? editing;

  const ProductFormSheet({super.key, this.editing});

  @override
  State<ProductFormSheet> createState() => _ProductFormSheetState();
}

class _ProductFormSheetState extends State<ProductFormSheet> {
  final _productRepo = ProductRepository(db);

  /// Galat isian, tampil di atas tombol simpan (desain).
  String? _galat;

  late final TextEditingController _nameC;
  late final TextEditingController _priceC;

  Category? _selectedCategory;
  bool _categoryInitialized = false;
  bool _hasSpicyOption = false;
  bool _hasSweetOption = false;
  bool _hasIceOption = false;
  String? _imagePath;
  final _imageStorage = ImageStorageService();

  /// Gambar yang DIBUAT selama sesi form ini. Kalau user memilih foto
  /// berkali-kali, atau akhirnya membatalkan, file-file ini jadi yatim:
  /// sudah ada di folder permanen tapi tidak dirujuk baris mana pun.
  ///
  /// Gambar LAMA milik produk tidak pernah masuk daftar ini — penghapusannya
  /// urusan products_page, yang tahu penyimpanan ke database sungguh berhasil.
  final _gambarBaru = <String>{};

  @override
  void initState() {
    super.initState();
    // Tahan sinkron selama form terbuka. Foto yang baru dipilih sudah menjadi
    // berkas tapi belum dirujuk baris mana pun sampai "Simpan Perubahan"
    // ditekan — dan memilih foto justru memicu sinkron, karena aplikasi
    // berpindah ke galeri lalu kembali aktif. Tanpa penahan ini, pembersihan
    // berkas yatim membuang foto yang sedang dipegang pengguna.
    SyncOtomatis.instance.sedangMenyuntingProduk = true;
    final p = widget.editing;
    _nameC = TextEditingController(text: p?.name ?? '');
    _priceC = TextEditingController(
      text: p != null ? formatRupiah(p.price) : '',
    );
    _hasSpicyOption = p?.hasSpicyOption ?? false;
    _hasSweetOption = p?.hasSweetOption ?? false;
    _hasIceOption = p?.hasIceOption ?? false;
    _imagePath = p?.imagePath;
  }


  @override
  void dispose() {
    SyncOtomatis.instance.sedangMenyuntingProduk = false;
    // Lunasi sinkron yang tertunda selama form terbuka.
    SyncOtomatis.instance.lanjutkanYangTertunda();
    _nameC.dispose();
    _priceC.dispose();
    super.dispose();
  }


  // Ada perubahan yang akan hilang kalau sheet ditutup?
  //
  // Sengaja membandingkan dengan produk aslinya, bukan sekadar mengecek
  // "apakah field terisi". Pada mode Edit semua field sudah terisi data lama
  // sejak initState, sehingga pengecekan isNotEmpty selalu bernilai true dan
  // dialog "Buang perubahan?" muncul walau user belum menyentuh apa pun.
  bool get _isDirty {
    final p = widget.editing;

    // Mode Tambah: kotor kalau user sudah mengisi atau mengubah apa pun.
    // Sakelar pilihan dan foto ikut dicek — sebelumnya terlewat,
    // sehingga sakelar dan foto bisa hilang tanpa peringatan.
    if (p == null) {
      return _nameC.text.trim().isNotEmpty ||
          parseRupiah(_priceC.text) != null ||
          _selectedCategory != null ||
          _hasSpicyOption ||
          _hasSweetOption ||
          _hasIceOption ||
          _imagePath != null;
    }

    // Mode Edit: kotor hanya kalau berbeda dari produk aslinya.
    //
    // Kategori dimuat asinkron lewat StreamBuilder di bawah, jadi
    // _selectedCategory masih null selama beberapa frame pertama. Selama
    // pengisian itu belum selesai, jangan dianggap berubah.
    final categoryPending = p.categoryId != null && !_categoryInitialized;
    final categoryChanged =
        !categoryPending && _selectedCategory?.id != p.categoryId;

    // Harga dibandingkan sebagai angka, bukan teks, supaya tidak rapuh
    // terhadap format titik ribuan dari RupiahInputFormatter.
    return _nameC.text.trim() != p.name ||
        parseRupiah(_priceC.text) != p.price ||
        categoryChanged ||
        _hasSpicyOption != p.hasSpicyOption ||
        _hasSweetOption != p.hasSweetOption ||
        _hasIceOption != p.hasIceOption ||
        _imagePath != p.imagePath;
  }

  // True saat pop berasal dari submit sukses — lewati dialog konfirmasi.
  bool _saving = false;

  /// Buang gambar yang dibuat sesi ini tapi tidak jadi dipakai.
  ///
  /// [kecuali] adalah pilihan akhir yang dibawa keluar form — hanya itu yang
  /// dipertahankan. Aman dipanggil untuk file yang sudah tidak ada.
  Future<void> _bersihkanGambarYatim({String? kecuali}) async {
    for (final relatif in _gambarBaru) {
      if (relatif == kecuali) continue;
      await _imageStorage.hapus(relatif);
    }
    _gambarBaru.clear();
  }

  void _submit() {
    final galat =
        galatFormProduk(nama: _nameC.text, hargaTeks: _priceC.text);
    if (galat != null) {
      setState(() => _galat = galat);
      return;
    }
    final price = parseRupiah(_priceC.text)!;

    _saving = true;
    // Sisa pilihan yang tidak jadi dipakai boleh langsung dibuang: file-file
    // itu belum pernah tercatat di database mana pun.
    unawaited(_bersihkanGambarYatim(kecuali: _imagePath));
    Navigator.pop(
      context,
      FormResult(
        name: _nameC.text.trim(),
        price: price,
        categoryId: _selectedCategory?.id,
        hasSpicyOption: _hasSpicyOption,
        hasSweetOption: _hasSweetOption,
        hasIceOption: _hasIceOption,
        imagePath: _imagePath,
      ),
    );
  }

  Future<void> _pickImage() async {
    final pilihan = await pilihDariDaftar<ImageSource?>(
      context,
      judul: 'Pilih Sumber Foto',
      ikon: Icons.add_photo_alternate_rounded,
      terpilih: null,
      opsi: const [
        OpsiLembar(
          nilai: ImageSource.camera,
          label: 'Kamera',
          ikon: Icons.camera_alt_rounded,
        ),
        OpsiLembar(
          nilai: ImageSource.gallery,
          label: 'Galeri',
          ikon: Icons.photo_library_rounded,
        ),
      ],
    );
    final source = pilihan?.nilai;
    if (source == null) return;

    // SENGAJA tanpa maxWidth/imageQuality: biar picker menyerahkan gambar
    // ASLI. Kompresi dilakukan sekali saja di ImageStorageService (ke WebP).
    // Mengompres di sini lalu di sana = dua kali lossy, kualitas turun dua
    // tahap tanpa ukuran ikut mengecil sebanding.
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source);
    if (picked == null) return;

    try {
      // Hasilnya path RELATIF (products/<uuid>.webp) — itu yang masuk DB.
      // File-nya sudah berada di folder permanen, bukan cache.
      final relatif = await _imageStorage.simpan(File(picked.path));
      _gambarBaru.add(relatif);
      if (mounted) setState(() => _imagePath = relatif);
    } catch (e) {
      if (mounted) AppToast.error(context, 'Gagal menyimpan gambar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    final isEditing = widget.editing != null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_saving || !_isDirty) {
          Navigator.of(context).pop();
          return;
        }
        final keluar = await tampilkanLembarKonfirmasi(
          context,
          ikon: Icons.edit_off_rounded,
          judul: 'Buang perubahan?',
          catatan: 'Data produk yang sudah diisi akan hilang.',
          labelAksi: 'Buang',
        );
        if (keluar) {
          // Semua gambar sesi ini jadi yatim. Gambar LAMA milik produk tidak
          // ikut terhapus — perubahannya memang dibatalkan.
          await _bersihkanGambarYatim();
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: Container(
        decoration: const BoxDecoration(
          color: WarnaTeras.kartu,
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 10, 20, 24 + inset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PegangLembar(),
              _judul(isEditing),
              const SizedBox(height: 16),
              _kotakFoto(),
              const SizedBox(height: 10),
              KolomIsian(
                controller: _nameC,
                label: 'Nama Produk',
                ikon: Icons.inventory_2_outlined,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() => _galat = null),
              ),
              const SizedBox(height: 10),
              KolomIsian(
                controller: _priceC,
                label: 'Harga',
                ikon: Icons.payments_outlined,
                prefixText: 'Rp ',
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  RupiahInputFormatter(),
                ],
                onChanged: (_) => setState(() => _galat = null),
              ),
              const SizedBox(height: 10),
              _pilihKategori(),
              const SizedBox(height: 10),
              for (final k in KelompokPilihan.values) ...[
                _sakelar(k),
                const SizedBox(height: 8),
              ],
              SizedBox(
                height: 20,
                child: Text(
                  _galat ?? '',
                  style: const TextStyle(
                    fontSize: TeksTeras.kecil,
                    color: WarnaTeras.merah,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              // Desain (revisi 2026-10-04): [Batalkan] [Simpan] berdampingan.
              // Batalkan lewat maybePop supaya tetap ditanya "Buang
              // perubahan?" kalau isian sudah diubah.
              Row(
                children: [
                  Expanded(
                    flex: 10,
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF5A5048),
                          side: const BorderSide(color: Color(0xFFE2D9D0)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        child: const Text(
                          'Batalkan',
                          style: TextStyle(
                            fontSize: TeksTeras.biasa,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 14,
                    child: SizedBox(
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: WarnaTeras.oranye,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        icon: Icon(
                          isEditing ? Icons.save_rounded : Icons.add_rounded,
                          size: 21,
                        ),
                        label: FittedBox(
                          child: Text(
                            isEditing ? 'Simpan Perubahan' : 'Tambah Produk',
                            style: const TextStyle(
                              fontSize: TeksTeras.biasa,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
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

  Widget _judul(bool isEditing) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: WarnaTeras.oranye,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            isEditing ? Icons.edit_square : Icons.add_business_rounded,
            size: 21,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEditing ? 'Edit Produk' : 'Tambah Produk',
              style: const TextStyle(
                fontSize: TeksTeras.menu,
                fontWeight: FontWeight.w600,
                color: WarnaTeras.teks,
              ),
            ),
            Text(
              isEditing ? 'Perbarui detail produk' : 'Isi detail produk baru',
              style: const TextStyle(
                fontSize: TeksTeras.kecil,
                color: WarnaTeras.teksSamar,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Kotak foto krem bertepi oranye (desain). Dengan foto: foto penuh,
  /// "Ganti foto" di kanan bawah, ✕ hapus di kanan atas.
  Widget _kotakFoto() {
    final ada = _imagePath != null && ImageStorageService.adaSync(_imagePath);
    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        height: 96,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFFFAF3EC),
          border: Border.all(color: const Color(0xFFF0A94E)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: ada
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(
                    File(ImageStorageService.lokasiPenuhSync(_imagePath!)),
                    fit: BoxFit.cover,
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: _pil(Icons.edit_rounded, 'Ganti foto'),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: () => setState(() => _imagePath = null),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: const BoxDecoration(
                          color: Color(0xA61E140A),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          size: 19,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 30,
                    color: WarnaTeras.oranye,
                  ),
                  SizedBox(width: 10),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tambahkan foto produk',
                        style: TextStyle(
                          fontSize: TeksTeras.biasa,
                          color: WarnaTeras.oranye,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Opsional - tap untuk pilih foto',
                        style: TextStyle(
                          fontSize: TeksTeras.kecil,
                          color: WarnaTeras.teksSamar,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Widget _pil(IconData ikon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xA61E140A),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ikon, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: TeksTeras.kecil,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pilihKategori() {
    return StreamBuilder<List<Category>>(
      stream: _productRepo.watchCategories(),
      builder: (context, snapshot) {
        final categories = snapshot.data ?? [];

        // Kategori dimuat asinkron: pada mode Edit, pilihan awal baru bisa
        // diisi setelah daftarnya datang.
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

        final dipilih = _selectedCategory;
        return KolomPilihan(
          ikon: dipilih == null
              ? Icons.category_rounded
              : categoryIconFromCodepoint(dipilih.iconCodepoint),
          label: 'Kategori',
          nilai: dipilih?.name ?? 'Pilih Kategori',
          kosong: dipilih == null,
          onTap: () async {
            // Cegah keyboard muncul lagi setelah lembar ditutup.
            FocusManager.instance.primaryFocus?.unfocus();
            final hasil = await pilihDariDaftar<Category?>(
              context,
              judul: 'Pilih Kategori',
              ikon: Icons.category_rounded,
              terpilih: categories
                  .where((c) => c.id == dipilih?.id)
                  .firstOrNull,
              opsi: [
                const OpsiLembar(
                  nilai: null,
                  label: 'Tanpa Kategori',
                  ikon: Icons.block_rounded,
                ),
                for (final c in categories)
                  OpsiLembar(
                    nilai: c,
                    label: c.name,
                    ikon: categoryIconFromCodepoint(c.iconCodepoint),
                  ),
              ],
            );
            if (hasil != null && mounted) {
              setState(() => _selectedCategory = hasil.nilai);
            }
          },
        );
      },
    );
  }

  bool _nilaiPilihan(KelompokPilihan k) => switch (k) {
        KelompokPilihan.pedas => _hasSpicyOption,
        KelompokPilihan.manis => _hasSweetOption,
        KelompokPilihan.es => _hasIceOption,
      };

  Widget _sakelar(KelompokPilihan k) {
    final g = gayaPilihan(k);
    final nyala = _nilaiPilihan(k);
    final nama = k.label.toLowerCase();
    return SakelarPilihan(
      ikon: g.ikon,
      warna: g.warna,
      jalur: g.jalur,
      judul: 'Ada pilihan level $nama',
      keterangan: nyala
          ? k.daftar.join(' / ')
          : switch (k) {
              KelompokPilihan.pedas => 'Produk tidak punya level kepedasan',
              _ => 'Produk tidak punya level $nama',
            },
      nilai: nyala,
      onUbah: (v) => setState(() {
        switch (k) {
          case KelompokPilihan.pedas:
            _hasSpicyOption = v;
          case KelompokPilihan.manis:
            _hasSweetOption = v;
          case KelompokPilihan.es:
            _hasIceOption = v;
        }
      }),
    );
  }
}

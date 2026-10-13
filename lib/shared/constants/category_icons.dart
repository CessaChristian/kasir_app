import 'package:flutter/material.dart';

/// Ikon kategori yang bisa DIPILIH di halaman Kategori — 12 ikon desain,
/// urut desain. `glass_cup` di desain tidak ada di Flutter, jadi diganti
/// gelas yang paling mirip (`local_drink`).
const kIkonPilihanKategori = <IconData>[
  Icons.rice_bowl,
  Icons.ramen_dining,
  Icons.lunch_dining,
  Icons.emoji_food_beverage,
  Icons.coffee_rounded,
  Icons.local_drink_rounded,
  Icons.local_bar_rounded,
  Icons.local_cafe_rounded,
  Icons.bakery_dining,
  Icons.icecream,
  Icons.cake_rounded,
  Icons.local_pizza,
];

/// Semua ikon yang bisa TAMPIL: pilihan desain + ikon pemilih lama, supaya
/// kategori yang dibuat dengan versi aplikasi sebelumnya tetap berikon sama.
///
/// PENTING (jangan diubah jadi non-const): Flutter melakukan "tree shaking"
/// ikon saat build release, yaitu membuang glyph yang tidak terpakai supaya
/// ukuran APK kecil. Proses itu hanya bisa mendeteksi [IconData] yang bersifat
/// `const`. Karena itu codepoint yang tersimpan di database TIDAK boleh dipakai
/// membuat `IconData(codepoint)` baru saat runtime — melainkan dicocokkan ke
/// daftar const di bawah lewat [categoryIconFromCodepoint].
const _ikonDikenal = <IconData>[
  ...kIkonPilihanKategori,
  Icons.restaurant_rounded,
  Icons.fastfood,
  Icons.dinner_dining,
  Icons.breakfast_dining,
  Icons.kebab_dining,
  Icons.set_meal,
  Icons.soup_kitchen,
  Icons.tapas,
  Icons.sports_bar_rounded,
  Icons.water_drop_rounded,
  Icons.blender,
  Icons.cookie,
  Icons.storefront_rounded,
  Icons.sell_rounded,
  Icons.label_rounded,
  Icons.star_rounded,
  Icons.local_offer_rounded,
  Icons.category_rounded,
];

/// Nama untuk produk tanpa kategori. Bukan baris di database: tidak bisa
/// dihapus atau disembunyikan (keputusan owner 2026-10-13).
const namaTanpaKategori = 'Tanpa Kategori';
const kIkonTanpaKategori = Icons.block_rounded;

/// Ikon yang dipakai kalau kategori belum punya ikon, atau codepoint-nya
/// tidak dikenal (mis. data lama dari versi aplikasi sebelumnya).
const kDefaultCategoryIcon = Icons.category_rounded;

/// Peta `codePoint` -> [IconData] const, dibangun sekali dari [_ikonDikenal].
final Map<int, IconData> _iconByCodePoint = {
  for (final icon in _ikonDikenal) icon.codePoint: icon,
};

/// Ubah `categories.icon_codepoint` dari database menjadi [IconData] const.
///
/// Mengembalikan [kDefaultCategoryIcon] kalau codepoint null atau tidak
/// dikenal.
IconData categoryIconFromCodepoint(int? codepoint) {
  if (codepoint == null) return kDefaultCategoryIcon;
  return _iconByCodePoint[codepoint] ?? kDefaultCategoryIcon;
}

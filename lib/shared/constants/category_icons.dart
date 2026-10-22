import 'package:flutter/material.dart';

/// Ikon kategori yang bisa DIPILIH di halaman Kategori — 12 ikon desain,
/// urut desain, ditambah sendok garpu & cookie (keputusan owner 2026-10-17:
/// dipakai Makanan & Snack). `glass_cup` di desain tidak ada di Flutter,
/// jadi diganti gelas yang paling mirip (`local_drink`).
///
/// 12 ikon terakhir tambahan owner 2026-10-22 untuk kategori yang belum
/// punya ikon pas (mis. Add on yang terpaksa memakai sendok garpu). Ikon
/// yang dulu sudah dikenal dipakai apa adanya — varian lain (mis.
/// `fastfood_rounded`) punya codepoint berbeda, dan kategori lama yang
/// memakainya akan berganti ikon.
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
  Icons.restaurant_rounded,
  Icons.cookie,
  Icons.add_circle_rounded, // Add on / topping
  Icons.egg_alt, // telur / lauk tambahan
  Icons.fastfood, // paket
  Icons.breakfast_dining, // roti
  Icons.kebab_dining, // sate
  Icons.soup_kitchen, // sup / kuah
  Icons.set_meal, // ikan / seafood
  Icons.blender, // jus
  Icons.takeout_dining, // bungkus
  Icons.local_fire_department_rounded, // pedas
  Icons.star_rounded, // rekomendasi
  Icons.local_offer_rounded, // promo
];

/// Semua ikon yang bisa TAMPIL: pilihan di atas + ikon pemilih lama, supaya
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
  Icons.dinner_dining,
  Icons.tapas,
  Icons.sports_bar_rounded,
  Icons.water_drop_rounded,
  Icons.storefront_rounded,
  Icons.sell_rounded,
  Icons.label_rounded,
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

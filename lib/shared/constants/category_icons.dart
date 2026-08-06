import 'package:flutter/material.dart';

/// Daftar ikon yang boleh dipilih untuk kategori produk.
///
/// SATU-SATUNYA sumber kebenaran — dipakai oleh pemilih ikon di
/// CategoryManager maupun oleh tampilan yang membaca ikon dari database.
///
/// PENTING (jangan diubah jadi non-const): Flutter melakukan "tree shaking"
/// ikon saat build release, yaitu membuang glyph yang tidak terpakai supaya
/// ukuran APK kecil. Proses itu hanya bisa mendeteksi [IconData] yang bersifat
/// `const`. Karena itu codepoint yang tersimpan di database TIDAK boleh dipakai
/// membuat `IconData(codepoint)` baru saat runtime — melainkan dicocokkan ke
/// daftar const di bawah lewat [categoryIconFromCodepoint].
const kCategoryIcons = <(IconData, String)>[
  (Icons.restaurant_rounded, 'Restoran'),
  (Icons.rice_bowl, 'Nasi'),
  (Icons.ramen_dining, 'Mie/Ramen'),
  (Icons.fastfood, 'Fast Food'),
  (Icons.lunch_dining, 'Makan Siang'),
  (Icons.dinner_dining, 'Makan Malam'),
  (Icons.breakfast_dining, 'Sarapan'),
  (Icons.local_pizza, 'Pizza'),
  (Icons.kebab_dining, 'Kebab'),
  (Icons.bakery_dining, 'Roti/Bakery'),
  (Icons.set_meal, 'Set Meal'),
  (Icons.soup_kitchen, 'Sup'),
  (Icons.tapas, 'Tapas'),
  (Icons.local_cafe_rounded, 'Kafe'),
  (Icons.coffee_rounded, 'Kopi'),
  (Icons.emoji_food_beverage, 'Minuman Hangat'),
  (Icons.local_bar_rounded, 'Bar'),
  (Icons.sports_bar_rounded, 'Minuman Segar'),
  (Icons.water_drop_rounded, 'Air'),
  (Icons.blender, 'Jus'),
  (Icons.cake_rounded, 'Kue'),
  (Icons.icecream, 'Es Krim'),
  (Icons.cookie, 'Snack'),
  (Icons.storefront_rounded, 'Toko'),
  (Icons.sell_rounded, 'Promo'),
  (Icons.label_rounded, 'Label'),
  (Icons.star_rounded, 'Favorit'),
  (Icons.local_offer_rounded, 'Penawaran'),
  (Icons.category_rounded, 'Umum'),
];

/// Ikon yang dipakai kalau kategori belum punya ikon, atau codepoint-nya
/// tidak dikenal (mis. data lama dari versi aplikasi sebelumnya).
const kDefaultCategoryIcon = Icons.category_rounded;

/// Peta `codePoint` -> [IconData] const, dibangun sekali dari [kCategoryIcons].
final Map<int, IconData> _iconByCodePoint = {
  for (final (icon, _) in kCategoryIcons) icon.codePoint: icon,
};

/// Ubah `categories.icon_codepoint` dari database menjadi [IconData] const.
///
/// Mengembalikan [kDefaultCategoryIcon] kalau codepoint null atau tidak
/// ditemukan di [kCategoryIcons].
IconData categoryIconFromCodepoint(int? codepoint) {
  if (codepoint == null) return kDefaultCategoryIcon;
  return _iconByCodePoint[codepoint] ?? kDefaultCategoryIcon;
}

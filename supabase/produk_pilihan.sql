-- =====================================================================
--  PILIHAN PRODUK — Pedas, Manis, Es
--
--  Jalankan lewat SQL Editor di dashboard Supabase. Aman diulang.
--
--  Dulu produk hanya punya satu sakelar, `has_spicy_option`. Sekarang ada
--  tiga kelompok pilihan yang bisa dinyalakan per produk:
--
--    Pedas  Tidak Pedas · Sedang · Pedas · Ekstra Pedas
--    Manis  Tanpa Gula · Sedikit · Normal · Ekstra Gula
--    Es     Tanpa Es · Sedikit · Normal · Ekstra Es
--
--  Pilihan yang dipilih kasir tetap disimpan sebagai teks di
--  `transaction_items.notes` ("Pedas: Sedang · Manis: Sedikit · Es: Normal"),
--  jadi item struk tidak butuh kolom baru dan struk lama tetap terbaca.
--
--  ── URUTANNYA PENTING ──
--
--  Jalankan SEBELUM APK yang membawa migrasi v28 dipasang. APK itu mengirim
--  dua kolom baru ini; kalau kolomnya belum ada, server menolak kiriman
--  produk dan sinkron produk gagal.
-- =====================================================================

alter table public.products
  add column if not exists has_sweet_option boolean not null default false,
  add column if not exists has_ice_option   boolean not null default false;

-- =====================================================================
--  PEMERIKSAAN — hasil yang benar: 3 baris.
--
--       select column_name from information_schema.columns
--       where table_schema = 'public' and table_name = 'products'
--         and column_name like 'has_%_option';
-- =====================================================================

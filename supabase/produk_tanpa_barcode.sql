-- =====================================================================
--  PRODUK TANPA BARCODE
--
--  Jalankan lewat SQL Editor di dashboard Supabase. Aman diulang.
--
--  Owner meminta barcode dihapus. Barcode hanya diketik manual (tidak ada
--  pemindai), tidak dipakai pencarian, dan tidak ada produk yang mengisinya.
--
--  ── URUTANNYA PENTING ──
--
--  Jalankan SESUDAH semua HP memakai APK yang sudah tidak mengirim kolom
--  ini (migrasi aplikasi v29). HP dengan APK lama masih mengirim `barcode`,
--  dan server akan menolak kiriman produknya karena kolomnya sudah tidak ada.
-- =====================================================================

alter table public.products drop column if exists barcode;

-- =====================================================================
--  PEMERIKSAAN — hasil yang benar: KOSONG (0 baris).
--
--       select column_name from information_schema.columns
--       where table_schema = 'public' and table_name = 'products'
--         and column_name = 'barcode';
-- =====================================================================

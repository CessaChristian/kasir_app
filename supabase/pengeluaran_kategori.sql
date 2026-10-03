-- =====================================================================
--  KATEGORI BIAYA & JUMLAH PENGELUARAN
--
--  Jalankan lewat SQL Editor di dashboard Supabase. Aman diulang.
--
--  Desain baru mencatat pengeluaran dengan kategori dan jumlah:
--    "Beli Es Batu (2x) · Bahan Baku · Rp 20.000"
--
--    category  asset · bahan_baku · operasional_kedai
--              Di berkas ini masih boleh kosong; pengeluaran_kategori_wajib.sql
--              (dijalankan sesudahnya) mengisi data lama dengan bahan_baku dan
--              menjadikannya wajib — tidak ada "Lainnya".
--    qty       Jumlah barang, minimal 1. `amount` tetap menyimpan TOTAL
--              (harga x jumlah), jadi semua laporan tidak berubah.
--
--  ── URUTANNYA PENTING ──
--
--  Jalankan SEBELUM APK yang membawa migrasi v32 dipasang. APK itu mengirim
--  dua kolom baru ini; kalau kolomnya belum ada, server menolak kiriman
--  pengeluaran dan sinkron pengeluaran gagal.
-- =====================================================================

alter table public.expenses
  add column if not exists category text,
  add column if not exists qty      integer not null default 1;

-- Pagar nilai — dipasang terpisah supaya aman diulang.
alter table public.expenses drop constraint if exists expenses_category_check;
alter table public.expenses add constraint expenses_category_check
  check (category in ('asset', 'bahan_baku', 'operasional_kedai'));

alter table public.expenses drop constraint if exists expenses_qty_check;
alter table public.expenses add constraint expenses_qty_check
  check (qty >= 1);

-- =====================================================================
--  PEMERIKSAAN — hasil yang benar: 2 baris (category, qty).
--
--       select column_name from information_schema.columns
--       where table_schema = 'public' and table_name = 'expenses'
--         and column_name in ('category', 'qty');
-- =====================================================================

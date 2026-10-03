-- =====================================================================
--  KATEGORI PENGELUARAN JADI WAJIB — data lama masuk "Bahan Baku"
--
--  Jalankan lewat SQL Editor di dashboard Supabase SETELAH
--  pengeluaran_kategori.sql. Aman diulang.
--
--  Keputusan owner (2026-10-04): kategori hanya tiga — Asset, Bahan Baku,
--  Operasional Kedai — tanpa "Lainnya". Pengeluaran lama yang belum punya
--  kategori dimasukkan ke Bahan Baku, tidak dihapus, supaya total dan
--  laporan lama tetap utuh.
--
--  ── KENAPA updated_at DIGESER ──
--
--  HP hanya menerima baris server yang `updated_at`-nya lebih baru minimal
--  satu detik dari salinannya sendiri. Tanpa geseran ini, HP yang sudah
--  menyimpan pengeluaran lama mengabaikan kategori barunya. Cara yang sama
--  dipakai kategori_terhapus.sql.
-- =====================================================================

update public.expenses
set category   = 'bahan_baku',
    updated_at = greatest(now(), updated_at) + interval '1 second'
where category is null;

alter table public.expenses
  alter column category set default 'bahan_baku',
  alter column category set not null;

-- =====================================================================
--  PEMERIKSAAN — hasil yang benar: 0.
--
--       select count(*) from public.expenses where category is null;
--
--  Dan kolomnya wajib — hasil yang benar: NO.
--
--       select is_nullable from information_schema.columns
--       where table_schema = 'public' and table_name = 'expenses'
--         and column_name = 'category';
-- =====================================================================

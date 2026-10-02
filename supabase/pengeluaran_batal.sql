-- =====================================================================
--  PEMBATALAN PENGELUARAN — sama seperti transaksi
--
--  Jalankan lewat SQL Editor di dashboard Supabase. Aman diulang.
--
--  Pengeluaran tidak pernah DIHAPUS dan tidak bisa DIEDIT, hanya
--  DIBATALKAN, lalu dicatat ulang kalau perlu. Dulu kasir bisa menghapus
--  atau mengubah jumlah pengeluaran tanpa jejak.
--
--    deleted_at            kapan dibatalkan
--    cancelled_by_user_id  siapa yang membatalkan
--    cancel_reason         alasannya
--
--  Kasir hanya bisa membatalkan pengeluarannya sendiri di shift yang sedang
--  berjalan, dengan PIN owner. Pengeluaran batal tetap tampil berlabel
--  DIBATALKAN dan tidak dihitung di total. Disimpan selamanya.
--
--  ── URUTANNYA ──
--
--  1. Jalankan berkas INI (kolom baru).
--  2. Jalankan ulang `supabase/buang_sampah.sql` — fungsinya kini tidak lagi
--     membuang pengeluaran.
--  3. Pasang APK yang membawa migrasi aplikasi v31.
--  4. SESUDAH semua HP memakai APK itu, jalankan
--     `supabase/pengeluaran_tanpa_updated_by.sql`.
-- =====================================================================

alter table public.expenses
  add column if not exists cancelled_by_user_id uuid references public.users(id),
  add column if not exists cancel_reason        text;

-- =====================================================================
--  PEMERIKSAAN — hasil yang benar: 2 baris.
--
--       select column_name from information_schema.columns
--       where table_schema = 'public' and table_name = 'expenses'
--         and column_name in ('cancelled_by_user_id', 'cancel_reason');
--
--  Fungsi buang_sampah tidak lagi menyebut pengeluaran — hasil yang benar:
--  false.
--
--       select prosrc ilike '%delete from public.expenses%'
--       from pg_proc where proname = 'buang_sampah';
-- =====================================================================

-- =====================================================================
--  PEMBATALAN TRANSAKSI — dicatat dan disimpan selamanya
--
--  Jalankan lewat SQL Editor di dashboard Supabase. Aman diulang.
--
--  Transaksi tidak pernah DIHAPUS, hanya DIBATALKAN. Dulu transaksi yang
--  dihapus hilang dari semua tampilan tanpa jejak — owner tidak bisa tahu
--  siapa menghapus apa, kapan, dan kenapa. Sekarang:
--
--    deleted_at            kapan dibatalkan (arti barunya untuk transaksi)
--    cancelled_by_user_id  siapa yang membatalkan
--    cancel_reason         alasannya
--
--  Kasir hanya bisa membatalkan transaksinya sendiri di shift yang sedang
--  berjalan, dan wajib memasukkan PIN owner. Owner bisa membatalkan apa pun.
--  Transaksi batal tetap tampil di Riwayat dengan label DIBATALKAN, tapi
--  tidak dihitung di total mana pun.
--
--  ── URUTANNYA ──
--
--  1. Jalankan berkas INI (kolom baru).
--  2. Jalankan ulang `supabase/buang_sampah.sql` — fungsinya kini tidak lagi
--     membuang transaksi.
--  3. Baru pasang APK yang membawa migrasi aplikasi v30. APK itu mengirim dua
--     kolom baru ini; kalau kolomnya belum ada, kiriman transaksi ditolak.
-- =====================================================================

alter table public.transactions
  add column if not exists cancelled_by_user_id uuid references public.users(id),
  add column if not exists cancel_reason        text;

-- =====================================================================
--  PEMERIKSAAN — hasil yang benar: 2 baris.
--
--       select column_name from information_schema.columns
--       where table_schema = 'public' and table_name = 'transactions'
--         and column_name in ('cancelled_by_user_id', 'cancel_reason');
--
--  Fungsi buang_sampah tidak lagi menyebut transaksi — hasil yang benar:
--  false.
--
--       select prosrc ilike '%delete from public.transactions%'
--       from pg_proc where proname = 'buang_sampah';
-- =====================================================================

-- =====================================================================
--  PENGELUARAN OWNER — boleh tanpa shift
--
--  Jalankan lewat SQL Editor di dashboard Supabase. Aman diulang.
--
--  Keputusan owner (2026-10-04): owner boleh mencatat pengeluaran. Owner
--  tidak menjalankan shift, jadi pengeluarannya tidak menempel ke shift mana
--  pun — cukup masuk pengelompokan per tanggal di halaman Pengeluaran.
--  Pengeluaran kasir TETAP wajib menempel ke shift (ditegakkan aplikasi).
--
--  ── URUTANNYA PENTING ──
--
--  1. Jalankan berkas ini DULU. Aman untuk APK lama: mereka selalu mengirim
--     shift_id.
--  2. Pasang APK baru (skema v33) di SEMUA HP.
--  3. Baru setelah itu owner boleh mencatat pengeluaran. APK lama gagal
--     menyinkronkan pengeluaran yang tidak punya shift.
-- =====================================================================

alter table public.expenses alter column shift_id drop not null;

-- =====================================================================
--  PEMERIKSAAN — hasil yang benar: YES.
--
--       select is_nullable from information_schema.columns
--       where table_schema = 'public' and table_name = 'expenses'
--         and column_name = 'shift_id';
-- =====================================================================

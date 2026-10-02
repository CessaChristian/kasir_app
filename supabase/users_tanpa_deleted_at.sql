-- =====================================================================
--  USERS TANPA deleted_at
--
--  Jalankan lewat SQL Editor di dashboard Supabase. Aman diulang.
--
--  Akun kasir tidak pernah dihapus — satu akun untuk satu orang. Karyawan
--  yang keluar dinonaktifkan (`is_active`), salah ketik dibetulkan lewat
--  Ganti Nama. Kolom `deleted_at` di tabel ini tidak pernah diisi dan tidak
--  punya arti lagi.
--
--  ── URUTANNYA PENTING ──
--
--  Jalankan SESUDAH semua HP memakai APK yang sudah tidak mengirim kolom
--  ini (migrasi aplikasi v26). HP dengan APK lama masih mengirim
--  `deleted_at`, dan server akan menolak kirimannya karena kolomnya sudah
--  tidak ada — sinkron tabel akun di HP itu gagal sampai APK-nya diperbarui.
-- =====================================================================

alter table public.users drop column if exists deleted_at;

-- =====================================================================
--  PEMERIKSAAN — hasil yang benar: KOSONG (0 baris).
--
--       select column_name from information_schema.columns
--       where table_schema = 'public'
--         and table_name   = 'users'
--         and column_name  = 'deleted_at';
-- =====================================================================

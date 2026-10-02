-- =====================================================================
--  PENGELUARAN TANPA updated_by_user_id
--
--  Jalankan lewat SQL Editor di dashboard Supabase. Aman diulang.
--
--  Kolom ini mencatat siapa yang terakhir MENGEDIT atau MENGHAPUS sebuah
--  pengeluaran. Fitur edit sudah dibuang dan penghapusan diganti
--  pembatalan, yang dicatat di `cancelled_by_user_id`.
--
--  ── URUTANNYA PENTING ──
--
--  Jalankan SESUDAH semua HP memakai APK yang membawa migrasi aplikasi v31.
--  HP dengan APK lama masih mengirim kolom ini, dan server akan menolak
--  kiriman pengeluarannya kalau kolomnya sudah tidak ada.
-- =====================================================================

alter table public.expenses drop column if exists updated_by_user_id;

-- =====================================================================
--  PEMERIKSAAN — hasil yang benar: KOSONG (0 baris).
--
--       select column_name from information_schema.columns
--       where table_schema = 'public' and table_name = 'expenses'
--         and column_name = 'updated_by_user_id';
-- =====================================================================

-- =====================================================================
--  KATEGORI BISA DISEMBUNYIKAN DARI KASIR + IZIN KELOLA KATEGORI
--
--  Jalankan lewat SQL Editor di dashboard Supabase SEBELUM memasang APK
--  dengan basis data v36. Aman diulang.
--
--  ── categories.tampil_di_kasir ──
--
--  false = tombol kategorinya tidak muncul di halaman Kasir. Produknya
--  TETAP tampil di "Semua" dan pencarian — yang disembunyikan cuma
--  tombolnya (keputusan owner 2026-10-13). Kategori lama otomatis tampil.
--
--  HP lama (v35) yang mengirim kategori tanpa kolom ini tidak mengubah
--  nilainya: upsert hanya menulis kolom yang dikirim.
--
--  ── manage_categories ──
--
--  Izin baru "Kelola Kategori" di Hak Akses. Bawaannya MATI untuk kasir
--  (tidak masuk izin bawaan kasir baru). Owner selalu boleh.
--
--  PERHATIAN: begitu Hak Akses disimpan dari HP v36, akan ada baris
--  user_permissions dengan kode ini. HP yang masih v35 belum mengenal kodenya
--  dan menolak baris itu, jadi sinkron izinnya macet. Perbarui SEMUA HP ke
--  APK v36 sebelum mengubah Hak Akses.
-- =====================================================================

alter table public.categories
  add column if not exists tampil_di_kasir boolean not null default true;

insert into public.permissions (code, name, description) values
  ('manage_categories', 'Kelola Kategori', 'Menambah, menghapus, dan mengatur kategori yang tampil di Kasir')
on conflict (code) do update
  set name = excluded.name,
      description = excluded.description;

-- =====================================================================
--  PEMERIKSAAN SESUDAH DIJALANKAN
--
--    select column_name, data_type, column_default
--      from information_schema.columns
--     where table_name = 'categories' and column_name = 'tampil_di_kasir';
--    -- harus 1 baris: boolean, default true
--
--    select code, name from public.permissions where code = 'manage_categories';
--    -- harus 1 baris
-- =====================================================================

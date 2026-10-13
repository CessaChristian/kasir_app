-- =====================================================================
--  KAS AWAL SHIFT
--
--  Jalankan lewat SQL Editor di dashboard Supabase SEBELUM memasang APK
--  dengan basis data v37. Aman diulang.
--
--  ── MASALAH YANG DIPECAHKAN ──
--
--  Shift dulu dibuka otomatis saat kasir login. Sekarang (keputusan owner
--  2026-10-13, sesuai desain) kasir MEMBUKA shift sendiri sambil mencatat
--  uang tunai di laci. Angka itu dipakai menghitung uang yang seharusnya ada
--  di laci: kas awal + penjualan tunai − pengeluaran.
--
--  Kosong = shift dari sebelum perubahan ini (tidak ada kas awal tercatat).
--  Boleh 0: laci memang bisa kosong saat buka.
--
--  HP lama (v36) yang mengirim shift tanpa kolom ini tidak mengubah
--  nilainya: upsert hanya menulis kolom yang dikirim.
-- =====================================================================

alter table public.shifts add column if not exists kas_awal bigint;

alter table public.shifts drop constraint if exists shifts_kas_awal_tidak_negatif;
alter table public.shifts
  add constraint shifts_kas_awal_tidak_negatif
  check (kas_awal is null or kas_awal >= 0);

-- =====================================================================
--  PEMERIKSAAN SESUDAH DIJALANKAN
--
--    select column_name, data_type from information_schema.columns
--     where table_name = 'shifts' and column_name = 'kas_awal';
--    -- harus 1 baris: bigint
-- =====================================================================

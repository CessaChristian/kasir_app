-- =====================================================================
--  JADWAL BUANG SAMPAH — tiap hari jam 00.00 WIB
--
--  Jalankan lewat SQL Editor di dashboard Supabase. Aman diulang: membuat
--  jadwal dengan nama yang sama MENIMPA jadwal lama, bukan menambah.
--
--  Memanggil `public.buang_sampah()` dengan rem bawaannya — 30 hari sejak
--  dihapus, DAN semua HP aktif sudah "centang biru". Lihat
--  `supabase/buang_sampah.sql`. JANGAN ganti jadi `buang_sampah('0 seconds')`
--  di sini: itu khusus untuk mencoba dari dashboard.
--
--  Jadwal pg_cron memakai jam UTC. 17.00 UTC = 00.00 WIB.
--
--  Jadwal berjalan sebagai pemilik database, jadi tetap boleh memanggil
--  fungsinya walau hak EXECUTE sudah dicabut dari HP.
-- =====================================================================

-- ---------------------------------------------------------------------
--  0. Nyalakan pg_cron SEKALI, lewat dashboard:
--     Database -> Extensions -> cari "pg_cron" -> Enable.
--
--  Periksa sudah menyala — hasil yang benar: 1 baris.
--
--       select extname, extversion from pg_extension where extname = 'pg_cron';
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
--  1. Jadwalnya
-- ---------------------------------------------------------------------
select cron.schedule(
  'buang-sampah-harian',
  '0 17 * * *',
  $$select * from public.buang_sampah()$$
);

-- =====================================================================
--  PEMERIKSAAN
--
--  Jadwal terdaftar — hasil yang benar: 1 baris, active = true.
--
--       select jobid, jobname, schedule, command, active
--       from cron.job where jobname = 'buang-sampah-harian';
--
--  Riwayat jalannya — status 'succeeded' berarti berhasil; kalau
--  'failed', pesan galatnya ada di return_message.
--
--       select start_time, end_time, status, return_message
--       from cron.job_run_details
--       where jobid = (select jobid from cron.job
--                      where jobname = 'buang-sampah-harian')
--       order by start_time desc limit 10;
--
--  MENGHENTIKAN jadwal:
--
--       select cron.unschedule('buang-sampah-harian');
-- =====================================================================

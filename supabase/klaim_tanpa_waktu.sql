-- =====================================================================
--  KLAIM BILL TANPA WAKTU DIANGGAP HANGUS (review R7, 3 Nov 2026)
--
--  Jalankan lewat SQL Editor di dashboard Supabase SESUDAH
--  klaim_lima_menit.sql. Aman diulang. APK lama tetap jalan.
--
--  ── YANG BERUBAH ──
--
--  klaim_pada baru ada sejak open_bill_aman.sql. Klaim yang dipasang
--  SEBELUM itu tidak punya waktu, dan dulu dianggap berlaku selamanya:
--  kalau HP yang membayar mati, bill-nya terkunci selamanya (tidak bisa
--  dibayar, diubah, dihapus) dan shift-nya tidak bisa ditutup.
--
--  → Klaim tanpa waktu dianggap sudah hangus. Klaim baru selalu punya
--    waktu: klaim_bill mengisi klaim_pada = now().
--
--  Pemeriksaan 3 Nov 2026: belum ada bill seperti itu di server (0
--  baris) — ini pengaman.
--
--  Harus sama dengan `sisaKlaimDariBaris` di
--  lib/features/open_bill/repositories/open_bill_repository.dart.
-- =====================================================================

create or replace function public.klaim_berlaku(p_tx uuid, p_pada timestamptz)
returns boolean
language sql
stable
as $$
  select p_tx is not null
     and p_pada is not null
     and p_pada > now() - interval '5 minutes';
$$;

revoke all on function public.klaim_berlaku(uuid, timestamptz)
  from public, anon;
grant execute on function public.klaim_berlaku(uuid, timestamptz)
  to authenticated;

-- =====================================================================
--  PEMERIKSAAN SESUDAH DIJALANKAN
--
--    select public.klaim_berlaku(gen_random_uuid(), null);
--    -- false
-- =====================================================================

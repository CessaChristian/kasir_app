-- =====================================================================
--  KLAIM PEMBAYARAN OPEN BILL HANGUS SESUDAH 5 MENIT
--  (review R5, keputusan owner 1 Nov 2026)
--
--  Jalankan lewat SQL Editor di dashboard Supabase SESUDAH
--  open_bill_aman.sql. Aman diulang. APK lama tetap jalan.
--
--  ── YANG BERUBAH ──
--
--  Klaim dipasang saat kasir mengetuk Bayar dan biasanya lepas dalam
--  hitungan detik (transaksinya tersimpan). Klaim yang tertinggal hanya
--  terjadi kalau HP yang membayar mati di tengah jalan; selama itu bill
--  tidak bisa diubah, dibayar, atau dihapus HP lain. Batasnya dipendekkan
--  dari 15 menit ke 5 menit supaya bill seperti itu cepat bisa dipakai
--  lagi.
--
--  Harga yang diterima owner: HP yang transaksinya SUDAH tersimpan tapi
--  internetnya putus punya 5 menit untuk mengabari server. Lewat dari itu,
--  HP lain bisa membayar bill yang sama, dan pelunasan HP pertama yang
--  datang belakangan ditolak (bill sudah diambil transaksi lain) —
--  transaksinya tetap tercatat di HP itu.
--
--  Harus sama dengan `batasKlaim` di
--  lib/features/open_bill/repositories/open_bill_repository.dart.
-- =====================================================================

create or replace function public.klaim_berlaku(p_tx uuid, p_pada timestamptz)
returns boolean
language sql
stable
as $$
  select p_tx is not null
     and (p_pada is null or p_pada > now() - interval '5 minutes');
$$;

revoke all on function public.klaim_berlaku(uuid, timestamptz)
  from public, anon;
grant execute on function public.klaim_berlaku(uuid, timestamptz)
  to authenticated;

-- =====================================================================
--  PEMERIKSAAN SESUDAH DIJALANKAN
--
--    select prosrc like '%5 minutes%' from pg_proc
--     where proname = 'klaim_berlaku';
--    -- true
-- =====================================================================

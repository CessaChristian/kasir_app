-- =====================================================================
--  JUMLAH DATA GAGAL TERKIRIM PER PERANGKAT (revisi QA kedua S10, 30 Okt 2026)
--
--  Jalankan lewat SQL Editor di dashboard Supabase SESUDAH
--  perangkat_tarik.sql. Aman diulang. APK lama tetap jalan: parameter
--  barunya punya nilai bawaan.
--
--  ── MASALAH YANG DIPECAHKAN ──
--
--  Baris HP yang terus ditolak server (mis. versi APK lama) dulu hanya
--  terlihat sebagai "sinkron sebagian" di HP itu sendiri — biasanya HP
--  kasir, yang tidak dilihat owner. Datanya hanya ada di HP itu.
--
--  Sekarang tiap HP melaporkan jumlahnya lewat perangkat_hadir, dan owner
--  melihatnya di Daftar Perangkat serta strip "HP perlu dicek" di
--  Dashboard.
-- =====================================================================

alter table public.perangkat
  add column if not exists jumlah_gagal_kirim integer not null default 0;

-- Versi tiga parameter dibuang: dua versi berdampingan membuat panggilan
-- dengan parameter bernama jadi ambigu dan ditolak Postgres.
drop function if exists public.perangkat_hadir(uuid, boolean, integer);

create or replace function public.perangkat_hadir(
  p_shift_id     uuid    default null,
  p_tarik_bersih boolean default false,
  p_tertahan     integer default null,
  p_gagal_kirim  integer default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_shift uuid;
begin
  select s.id into v_shift
  from public.shifts s
  where s.id = p_shift_id and s.end_at is null and s.deleted_at is null;

  update public.perangkat
     set terakhir_aktif     = now(),
         shift_id           = v_shift,
         terakhir_tarik     = case when p_tarik_bersih then now()
                                   else terakhir_tarik end,
         -- Null = tidak dilaporkan (kabar dari sentuhan, APK lama).
         jumlah_tertahan    = greatest(coalesce(p_tertahan, jumlah_tertahan), 0),
         jumlah_gagal_kirim = greatest(
                                coalesce(p_gagal_kirim, jumlah_gagal_kirim), 0)
   where id = auth.uid();
end $$;

revoke all on function public.perangkat_hadir(uuid, boolean, integer, integer)
  from public, anon;
grant execute on function public.perangkat_hadir(uuid, boolean, integer, integer)
  to authenticated;

-- =====================================================================
--  PEMERIKSAAN SESUDAH DIJALANKAN
--
--    select pg_get_function_identity_arguments(oid)
--      from pg_proc where proname = 'perangkat_hadir';
--    -- 1 baris: p_shift_id uuid, p_tarik_bersih boolean,
--    --          p_tertahan integer, p_gagal_kirim integer
-- =====================================================================

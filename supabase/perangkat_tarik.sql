-- =====================================================================
--  PERANGKAT_TARIK  —  pisahkan "HP masih dipakai" dari "HP sudah
--                      menerima semua data"
--
--  Jalankan lewat SQL Editor di dashboard Supabase. Aman diulang.
--  Jalankan SEBELUM memasang APK yang membawa perubahan ini. APK lama
--  tetap jalan: parameter barunya punya nilai bawaan.
--
--  ── MASALAHNYA ──
--
--  `terakhir_aktif` dulu hanya diisi sesudah sinkron yang berhasil penuh,
--  dan buang sampah ("centang biru", supabase/buang_sampah.sql) membacanya
--  sebagai "HP ini sudah menerima semua data sampai jam sekian".
--
--  Sekarang kolom itu juga diisi saat sinkron gagal, saat ada baris yang
--  tertahan di HP, dan dari sentuhan layar selama keranjang berisi — semua
--  benar untuk urusan "HP masih dipakai" (sesi diam, pemegang shift), tapi
--  salah untuk buang sampah. HP yang tarikannya bermasalah terlihat sudah
--  "centang biru", dan setelah 30 hari server membuang produk/kategori
--  terhapus yang kabar hapusnya belum pernah sampai ke HP itu: produk lama
--  tetap muncul di sana selamanya. Halaman Perangkat pun menampilkannya
--  sehat.
--
--  ── PERBAIKANNYA ──
--
--    terakhir_aktif   tetap: kapan HP terakhir memberi kabar
--    terakhir_tarik   BARU: kapan HP terakhir SELESAI MENARIK dengan bersih
--                     — tanpa galat dan tanpa baris tertahan
--    jumlah_tertahan  BARU: baris server yang ditolak database HP itu
--
--  Buang sampah baru beralih ke `terakhir_tarik` di berkas berikutnya
--  (supabase/buang_sampah_tarik.sql), SESUDAH semua HP memakai APK baru.
-- =====================================================================

alter table public.perangkat
  add column if not exists terakhir_tarik timestamptz;
alter table public.perangkat
  add column if not exists jumlah_tertahan integer not null default 0;

-- Versi satu parameter DIBUANG lebih dulu: dua fungsi bernama sama membuat
-- pemanggilan `perangkat_hadir(p_shift_id)` dari APK lama jadi ambigu dan
-- ditolak Postgres.
drop function if exists public.perangkat_hadir(uuid);

create or replace function public.perangkat_hadir(
  p_shift_id    uuid    default null,
  p_tarik_bersih boolean default false,
  p_tertahan    integer default null
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
     set terakhir_aktif  = now(),
         shift_id        = v_shift,
         -- Hanya tarikan yang bersih yang memajukannya. Kabar dari sentuhan
         -- layar atau sinkron yang gagal tidak menyentuhnya.
         terakhir_tarik  = case when p_tarik_bersih then now()
                                else terakhir_tarik end,
         -- Null = tidak dilaporkan (kabar dari sentuhan): nilai lama dipakai.
         jumlah_tertahan = greatest(coalesce(p_tertahan, jumlah_tertahan), 0)
   where id = auth.uid();
end $$;

revoke all on function public.perangkat_hadir(uuid, boolean, integer)
  from public, anon;
grant execute on function public.perangkat_hadir(uuid, boolean, integer)
  to authenticated;

-- =====================================================================
--  PEMERIKSAAN SESUDAH DIJALANKAN
--
--    select column_name from information_schema.columns
--     where table_schema = 'public' and table_name = 'perangkat'
--       and column_name in ('terakhir_tarik', 'jumlah_tertahan');
--    -- harus 2 baris
--
--    select pg_get_function_identity_arguments(oid)
--      from pg_proc where proname = 'perangkat_hadir';
--    -- harus 1 baris: p_shift_id uuid, p_tarik_bersih boolean,
--    --                p_tertahan integer
-- =====================================================================

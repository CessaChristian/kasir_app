-- =====================================================================
--  SATU AKUN KASIR = SATU HP (keputusan owner, 12 Nov 2026)
--
--  Jalankan lewat SQL Editor di dashboard Supabase SESUDAH catatan_error.sql.
--  Aman diulang. APK lama tetap jalan: parameter baru perangkat_hadir punya
--  nilai bawaan, dan jawaban barunya diabaikan APK lama.
--
--  ── MASALAH YANG DIPECAHKAN ──
--
--  Dulu kasir dikeluarkan sesudah 15 menit layar tidak disentuh, supaya HP
--  yang ditinggal melepas shift-nya dan HP lain bisa menutup shift. Owner:
--  aturan itu meribetkan kasir saat jam operasional. Gantinya:
--
--    1. Akun kasir dipegang SATU HP. HP lain yang mencoba masuk (online)
--       ditolak — `pegang_akun`.
--    2. HP yang rusak/hilang/lupa keluar dilepas owner dengan PIN owner —
--       `lepas_akun`.
--    3. Dua HP bisa lolos memegang akun yang sama kalau salah satunya masuk
--       saat offline. Begitu keduanya melapor, yang MULAI MEMEGANG LEBIH
--       DULU menang; yang lain dijawab 'kalah' dan keluar sendiri sesudah
--       datanya terkirim — `perangkat_hadir`.
--    4. Pemegang shift tidak lagi "basi" sesudah 15 menit diam: HP yang
--       ditinggal tetap memegang shift-nya sampai keluar atau dilepas owner.
-- =====================================================================

-- ---------------------------------------------------------------------
--  1. Kolomnya
--
--  `on delete set null`, bukan cascade (lihat perangkat_shift.sql).
--  akun_dilepas: akun yang terakhir dilepas owner dari HP ini. HP yang
--  dilepas saat offline masih mengira memegang akunnya; tanpa tanda ini,
--  jam mulai-pegangnya yang lebih awal membuat ia MENANG lagi atas HP yang
--  sah memegang akun itu sesudah dilepas.
-- ---------------------------------------------------------------------
alter table public.perangkat
  add column if not exists akun_id uuid
    references public.users(id) on delete set null,
  add column if not exists akun_sejak timestamptz,
  add column if not exists akun_dilepas uuid;

create index if not exists idx_perangkat_akun
  on public.perangkat (akun_id) where akun_id is not null;

-- ---------------------------------------------------------------------
--  2. Siapa pemenang sebuah akun — dipakai ketiga fungsi di bawah.
--
--  Pemegang = perangkat AKTIF yang tercatat memegang akun itu. Paling awal
--  mulai memegang menang; seri dipecah dengan id supaya jawabannya pasti
--  sama di semua HP.
-- ---------------------------------------------------------------------
create or replace function public.pemegang_akun_lain(
  p_akun  uuid,
  p_sejak timestamptz
)
returns table (nama text, sejak timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  select p.nama, p.akun_sejak
  from public.perangkat p
  where p.akun_id = p_akun
    and p.id <> auth.uid()
    and p.status = 'aktif'
    and (p_sejak is null
         or p.akun_sejak < p_sejak
         or (p.akun_sejak = p_sejak and p.id < auth.uid()))
  order by p.akun_sejak, p.id
  limit 1;
$$;

revoke all on function public.pemegang_akun_lain(uuid, timestamptz)
  from public, anon, authenticated;

-- Jam mulai-pegang dari HP dipakai apa adanya, dengan dua batas: tidak
-- boleh di masa depan, dan tidak boleh lebih dari 30 hari lalu — HP yang
-- jamnya mundur ke tahun 1970 tidak boleh menang selamanya.
create or replace function public.sejak_wajar(p_sejak timestamptz)
returns timestamptz
language sql
stable
set search_path = public
as $$
  select greatest(least(coalesce(p_sejak, now()), now()),
                  now() - interval '30 days');
$$;

revoke all on function public.sejak_wajar(timestamptz)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------
--  3. pegang_akun — dipanggil saat kasir masuk dalam keadaan online.
--
--  Jawaban (jsonb):
--    {"status":"ok"}                               → boleh masuk
--    {"status":"dipegang","nama":"HP Kasir 1"}     → ditolak
--  Akun owner tidak dikunci (owner boleh di beberapa HP).
-- ---------------------------------------------------------------------
create or replace function public.pegang_akun(
  p_akun  uuid,
  p_sejak timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sejak timestamptz := public.sejak_wajar(p_sejak);
  v_nama  text;
begin
  if not exists (
    select 1 from public.perangkat where id = auth.uid() and status = 'aktif'
  ) then
    raise exception 'perangkat ini tidak berhak' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.users
    where id = p_akun and role = 'cashier' and deleted_at is null
  ) then
    return jsonb_build_object('status', 'ok');
  end if;

  -- Siapa pun yang sudah memegang akun ini menolak masuk yang baru —
  -- di sini tidak dibandingkan jamnya: masuk online yang baru selalu kalah
  -- dari pemegang yang sudah ada.
  select p.nama into v_nama
  from public.perangkat p
  where p.akun_id = p_akun and p.id <> auth.uid() and p.status = 'aktif'
  order by p.akun_sejak, p.id
  limit 1;
  if v_nama is not null then
    return jsonb_build_object('status', 'dipegang', 'nama', v_nama);
  end if;

  update public.perangkat
     set akun_id = p_akun, akun_sejak = v_sejak, akun_dilepas = null
   where id = auth.uid();
  return jsonb_build_object('status', 'ok');
end $$;

revoke all on function public.pegang_akun(uuid, timestamptz) from public, anon;
grant execute on function public.pegang_akun(uuid, timestamptz) to authenticated;

-- ---------------------------------------------------------------------
--  4. perangkat_hadir — sekarang ikut melaporkan akun yang dipegang dan
--     menjawab:
--       'aman'    → lanjut
--       'kalah'   → ada HP lain yang lebih dulu memegang akun ini
--       'dilepas' → owner melepas akun ini dari HP ini
--
--  Versi lima parameter dibuang (lihat perangkat_jam.sql: dua versi
--  berdampingan membuat panggilan bernama ambigu). Jenis jawabannya berubah
--  dari void ke text, jadi harus drop dulu.
-- ---------------------------------------------------------------------
drop function if exists public.perangkat_hadir(uuid, boolean, integer, integer, integer);
drop function if exists public.perangkat_hadir(uuid, boolean, integer, integer, integer, uuid, timestamptz);

create or replace function public.perangkat_hadir(
  p_shift_id     uuid        default null,
  p_tarik_bersih boolean     default false,
  p_tertahan     integer     default null,
  p_gagal_kirim  integer     default null,
  p_selisih_jam  integer     default null,
  p_akun         uuid        default null,
  p_akun_sejak   timestamptz default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_shift   uuid;
  v_dilepas uuid;
  v_sejak   timestamptz := public.sejak_wajar(p_akun_sejak);
  v_jawab   text := 'aman';
begin
  select s.id into v_shift
  from public.shifts s
  where s.id = p_shift_id and s.end_at is null and s.deleted_at is null;

  select akun_dilepas into v_dilepas
  from public.perangkat where id = auth.uid();

  if p_akun is not null and v_dilepas = p_akun then
    v_jawab := 'dilepas';
  elsif p_akun is not null and exists (
    select 1 from public.users
    where id = p_akun and role = 'cashier' and deleted_at is null
  ) and exists (select 1 from public.pemegang_akun_lain(p_akun, v_sejak)) then
    v_jawab := 'kalah';
  end if;

  update public.perangkat
     set terakhir_aktif     = now(),
         -- HP yang kalah/dilepas sebentar lagi keluar: shift dan akunnya
         -- tidak dicatat, supaya tidak menghalangi pemegang yang sah.
         shift_id           = case when v_jawab = 'aman' then v_shift end,
         akun_id            = case when v_jawab = 'aman' then p_akun end,
         akun_sejak         = case when v_jawab = 'aman' and p_akun is not null
                                   then v_sejak end,
         -- 'dilepas' cukup dijawab sekali: sesudahnya HP ini keluar dan
         -- melapor tanpa akun.
         akun_dilepas       = case when p_akun is null then null
                                   else akun_dilepas end,
         terakhir_tarik     = case when p_tarik_bersih then now()
                                   else terakhir_tarik end,
         jumlah_tertahan    = greatest(coalesce(p_tertahan, jumlah_tertahan), 0),
         jumlah_gagal_kirim = greatest(
                                coalesce(p_gagal_kirim, jumlah_gagal_kirim), 0),
         selisih_jam_detik  = coalesce(p_selisih_jam, selisih_jam_detik)
   where id = auth.uid();
  return v_jawab;
end $$;

revoke all on function public.perangkat_hadir(
  uuid, boolean, integer, integer, integer, uuid, timestamptz) from public, anon;
grant execute on function public.perangkat_hadir(
  uuid, boolean, integer, integer, integer, uuid, timestamptz) to authenticated;

-- ---------------------------------------------------------------------
--  5. lepas_akun — owner melepas akun dari sebuah HP (HP rusak, hilang,
--     atau kasir lupa keluar). Wajib PIN owner, sama seperti Cabut.
--     Jawaban: 'ok' atau 'pin_salah'.
-- ---------------------------------------------------------------------
create or replace function public.lepas_akun(p_id uuid, p_pin text)
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.perangkat where id = auth.uid() and status = 'aktif'
  ) then
    raise exception 'perangkat ini tidak berhak' using errcode = '42501';
  end if;

  if not public.pin_owner_cocok(p_pin) then
    return 'pin_salah';
  end if;

  update public.perangkat
     set akun_dilepas = coalesce(akun_id, akun_dilepas),
         akun_id      = null,
         akun_sejak   = null,
         shift_id     = null
   where id = p_id;
  return 'ok';
end $$;

revoke all on function public.lepas_akun(uuid, text) from public, anon;
grant execute on function public.lepas_akun(uuid, text) to authenticated;

-- ---------------------------------------------------------------------
--  6. Pemegang shift tidak basi lagi (menggantikan batas 15 menit di
--     shift_pemegang_basi.sql). HP yang ditinggal tetap memegang shift-nya
--     sampai kasirnya keluar atau owner melepasnya.
-- ---------------------------------------------------------------------
create or replace function public.shift_dipegang_perangkat_lain(p_shift_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.perangkat
    where shift_id = p_shift_id
      and id <> auth.uid()
      and status = 'aktif'
  );
$$;

revoke all on function public.shift_dipegang_perangkat_lain(uuid) from public, anon;
grant execute on function public.shift_dipegang_perangkat_lain(uuid) to authenticated;

create or replace function public.pemegang_shift_lain(p_shift_id uuid)
returns table (nama text, diam_detik integer)
language sql
stable
security definer
set search_path = public
as $$
  select p.nama,
         greatest(0, extract(epoch from now() - p.terakhir_aktif))::integer
  from public.perangkat p
  where p.shift_id = p_shift_id
    and p.id <> auth.uid()
    and p.status = 'aktif'
  order by p.terakhir_aktif desc;
$$;

revoke all on function public.pemegang_shift_lain(uuid) from public, anon;
grant execute on function public.pemegang_shift_lain(uuid) to authenticated;

-- =====================================================================
--  PEMERIKSAAN SESUDAH DIJALANKAN
--
--    select proname, pg_get_function_identity_arguments(oid)
--      from pg_proc
--     where proname in ('perangkat_hadir','pegang_akun','lepas_akun');
--    -- 3 baris; perangkat_hadir dengan p_akun uuid, p_akun_sejak timestamptz
-- =====================================================================

-- =====================================================================
--  CABUT / PULIHKAN / LUPAKAN PERANGKAT BUTUH PIN OWNER (audit 6 Nov 2026
--  nomor 1)
--
--  Jalankan lewat SQL Editor di dashboard Supabase SESUDAH
--  kredensial_ketat.sql. Aman diulang. Butuh APK baru: APK lama memanggil
--  versi tanpa PIN, yang di sini DIBUANG — dari APK lama, Cabut/Pulihkan/
--  Lupakan gagal sampai aplikasinya diperbarui.
--
--  ── MASALAH YANG DIPECAHKAN ──
--
--  Server hanya tahu "HP ini aktif", bukan siapa yang sedang masuk. Syarat
--  "hanya owner" cuma ada di aplikasi, jadi HP kasir yang aplikasinya diakali
--  bisa mencabut lalu menghapus HP owner, atau memulihkan HP yang dicabut.
--
--  ── PERBAIKANNYA ──
--
--  Ketiga aksi wajib membawa PIN owner, dan PIN itu dicocokkan di server
--  dengan hash PIN owner. Owner tetap bisa melakukannya dari HP mana pun.
--  PIN salah dijawab 'pin_salah' (bukan galat), supaya aplikasi bisa
--  memintanya lagi.
-- =====================================================================

drop function if exists public.ubah_status_perangkat(uuid, boolean);
drop function if exists public.lupakan_perangkat(uuid);

create or replace function public.pin_owner_cocok(p_pin text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select public.cocok_pin(p_pin, salt, pin_hash)
      from public.users
     where role = 'owner' and deleted_at is null
     order by created_at
     limit 1
  ), false);
$$;

revoke all on function public.pin_owner_cocok(text)
  from public, anon, authenticated;

create or replace function public.ubah_status_perangkat(
  p_id    uuid,
  p_aktif boolean,
  p_pin   text
)
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

  if p_id = auth.uid() then
    raise exception 'tidak boleh mengubah status sendiri' using errcode = '42501';
  end if;

  if not public.pin_owner_cocok(p_pin) then
    return 'pin_salah';
  end if;

  update public.perangkat
     set status = case when p_aktif then 'aktif' else 'dicabut' end
   where id = p_id;
  return 'ok';
end $$;

revoke all on function public.ubah_status_perangkat(uuid, boolean, text)
  from public, anon;
grant execute on function public.ubah_status_perangkat(uuid, boolean, text)
  to authenticated;

create or replace function public.lupakan_perangkat(p_id uuid, p_pin text)
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.perangkat
    where id = auth.uid() and status = 'aktif'
  ) then
    raise exception 'perangkat ini tidak berhak' using errcode = '42501';
  end if;

  if p_id = auth.uid() then
    raise exception 'tidak boleh melupakan diri sendiri' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.perangkat where id = p_id and status = 'dicabut'
  ) then
    raise exception 'cabut dulu sebelum dilupakan' using errcode = '42501';
  end if;

  if not public.pin_owner_cocok(p_pin) then
    return 'pin_salah';
  end if;

  delete from public.perangkat where id = p_id;
  delete from auth.users where id = p_id and is_anonymous = true;
  return 'ok';
end $$;

revoke all on function public.lupakan_perangkat(uuid, text) from public, anon;
grant execute on function public.lupakan_perangkat(uuid, text) to authenticated;

-- =====================================================================
--  PEMERIKSAAN SESUDAH DIJALANKAN
--
--    select proname, pg_get_function_identity_arguments(oid)
--      from pg_proc
--     where proname in ('ubah_status_perangkat', 'lupakan_perangkat');
--    -- 2 baris, keduanya dengan p_pin text
-- =====================================================================

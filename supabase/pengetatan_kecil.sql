-- =====================================================================
--  PENGETATAN KECIL (revisi QA kedua K12 & K13, 30 Okt 2026)
--
--  Jalankan lewat SQL Editor di dashboard Supabase SESUDAH shift_gabung.sql,
--  shift_pemegang_basi.sql, dan perangkat_tebak_aman.sql. Aman diulang.
--  Tidak perlu APK baru.
--
--  K12. `shifts.digabung_ke` bisa diisi kiriman HP: shift yang masih
--       berjalan ditandai "sudah digabung" dan membeku. Sekarang kolom itu
--       hanya diisi trigger penggabungan. Ubahan LANGSUNG lewat SQL Editor
--       tetap boleh — owner kadang perlu membetulkan data dari server.
--
--  K13. pemegang_shift_lain bisa dipanggil HP yang dicabut (nama HP lain
--       terbaca), dan nama HP tidak dibatasi panjangnya. Sekarang fungsinya
--       hanya untuk HP aktif, dan nama dipotong 30 karakter — sama dengan
--       batas di layar Ganti Nama.
-- =====================================================================

-- ---------------------------------------------------------------------
--  Kiriman lewat API aplikasi (PostgREST membawa klaim JWT), bukan dari
--  SQL Editor.
-- ---------------------------------------------------------------------
create or replace function public.dari_api()
returns boolean
language sql
stable
as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), ''),
                  nullif(current_setting('request.jwt.claim.sub', true), ''))
         is not null;
$$;

revoke all on function public.dari_api() from public, anon;
grant execute on function public.dari_api() to authenticated;

-- ---------------------------------------------------------------------
--  K12 — gabung_shift dari shift_gabung.sql, ditambah penjaga digabung_ke.
-- ---------------------------------------------------------------------
create or replace function public.gabung_shift()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tujuan uuid;
  v_cap    timestamptz;
begin
  if tg_op = 'UPDATE' then
    -- 3. Yang sudah digabung tetap digabung. Versi server dipertahankan
    --    dan dimajukan supaya HP pengirim menariknya.
    --    Capnya melewati kiriman itu juga: kalau tidak, salinan HP pengirim
    --    tetap lebih baru dan kabar penggabungannya tidak pernah ditarik.
    if old.digabung_ke is not null then
      v_cap := greatest(new.updated_at, old.updated_at, now())
               + interval '1 second';
      new := old;
      new.updated_at := v_cap;
    end if;
    -- K12: kiriman HP tidak boleh menandai shift sebagai sudah digabung —
    -- shift-nya beku. Ubahan langsung lewat SQL Editor tetap boleh.
    if new.digabung_ke is distinct from old.digabung_ke
       and public.dari_api() then
      new.digabung_ke := old.digabung_ke;
    end if;
    return new;
  end if;

  -- K12: digabung_ke hanya diisi trigger ini sendiri, di bawah.
  if public.dari_api() then
    new.digabung_ke := null;
  end if;

  -- `upsert` menjalankan trigger INSERT juga untuk baris yang SUDAH ada
  -- (lalu beralih ke UPDATE). Yang digabung hanya kedatangan pertama.
  if exists (select 1 from public.shifts where id = new.id) then
    return new;
  end if;

  -- Dua HP yang tiba bersamaan tidak boleh sama-sama merasa "pertama".
  perform pg_advisory_xact_lock(hashtext('gabung_shift:' || new.user_id));

  select s.id into v_tujuan
    from public.shifts s
   where s.user_id = new.user_id
     and s.deleted_at is null
     and s.digabung_ke is null
     and s.start_at < coalesce(new.end_at, 'infinity')
     and new.start_at < coalesce(s.end_at, 'infinity')
   order by s.server_urut, s.id
   limit 1;

  if v_tujuan is not null then
    new.digabung_ke := v_tujuan;
    new.deleted_at := coalesce(new.deleted_at, now());
    new.updated_at := greatest(new.updated_at, now()) + interval '1 second';
  end if;
  return new;
end $$;

revoke all on function public.gabung_shift() from public, anon, authenticated;

-- ---------------------------------------------------------------------
--  K13 — pemegang shift hanya untuk HP aktif.
-- ---------------------------------------------------------------------
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
  where public.perangkat_aktif()
    and p.shift_id = p_shift_id
    and p.id <> auth.uid()
    and p.status = 'aktif'
    and p.terakhir_aktif > now() - interval '15 minutes'
  order by p.terakhir_aktif desc;
$$;

revoke all on function public.pemegang_shift_lain(uuid) from public, anon;
grant execute on function public.pemegang_shift_lain(uuid) to authenticated;

-- ---------------------------------------------------------------------
--  K13 — nama HP paling panjang 30 karakter, dari jalan mana pun
--  (daftarkan_perangkat, ubah_nama_perangkat, atau kiriman lain).
-- ---------------------------------------------------------------------
create or replace function public.potong_nama_perangkat()
returns trigger
language plpgsql
as $$
begin
  new.nama := left(btrim(new.nama), 30);
  return new;
end $$;

revoke all on function public.potong_nama_perangkat()
  from public, anon, authenticated;

drop trigger if exists trg_perangkat_potong_nama on public.perangkat;
create trigger trg_perangkat_potong_nama
  before insert or update of nama on public.perangkat
  for each row execute function public.potong_nama_perangkat();

update public.perangkat set nama = left(btrim(nama), 30)
 where length(nama) > 30;

-- =====================================================================
--  PEMERIKSAAN SESUDAH DIJALANKAN
--
--    select tgname from pg_trigger where tgname = 'trg_perangkat_potong_nama';
--    -- 1 baris
-- =====================================================================

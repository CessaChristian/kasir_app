-- =====================================================================
--  KREDENSIAL KETAT (audit 6 Nov 2026 nomor 3, 5 & 6)
--
--  Jalankan lewat SQL Editor di dashboard Supabase SESUDAH
--  kredensial_owner.sql. Aman diulang. Butuh APK yang sama barunya: APK
--  lama masih mengirim kolom kunci recovery, dan kirimannya cukup diabaikan.
--
--  ── MASALAH YANG DIPECAHKAN ──
--
--  3. Hash PIN format lama (SHA-256 sekali) masih diterima. Bisa dibongkar
--     dalam hitungan detik dari salinan database HP.
--  5. Hash yang bagian isinya kosong (`pbkdf2:1:`) atau jumlah putarannya
--     ngawur bisa masuk tabel users lewat sinkron. Di HP, hash kosong dulu
--     menerima PIN apa pun.
--  6. Kolom kunci kode recovery (jumlah salah, terkunci sampai) ikut
--     sinkron. HP yang diakali bisa mengisi "terkunci sampai 2099" dan
--     semua HP menolak recovery owner.
--
--  ── PERBAIKANNYA ──
--
--  - cocok_pin hanya menerima PBKDF2 32 byte dengan 100.000–1.000.000
--    putaran — sama dengan CryptoUtils di aplikasi.
--  - CHECK di kolom pin_hash dan recovery_hash dengan aturan yang sama.
--  - Kolom kunci recovery jadi milik tiap HP: server tidak menyimpan
--    kiriman HP untuk kolom itu (sama seperti kunci salah PIN).
-- =====================================================================

-- ---------------------------------------------------------------------
--  0. Periksa data lama. Kalau ada baris, perbaiki dulu (minta akun itu
--     ganti PIN) sebelum lanjut — langkah 2 akan menolak.
-- ---------------------------------------------------------------------
--    select id, username, left(pin_hash, 14), left(recovery_hash, 14)
--      from public.users
--     where not public.hash_kredensial_sah(pin_hash)
--        or (recovery_hash is not null
--            and not public.hash_kredensial_sah(recovery_hash));

create or replace function public.hash_kredensial_sah(p_hash text)
returns boolean
language sql
immutable
as $$
  select p_hash ~ '^pbkdf2:[0-9]{6,7}:[A-Za-z0-9+/]{43}=$'
     and split_part(p_hash, ':', 2)::int between 100000 and 1000000;
$$;

-- ---------------------------------------------------------------------
--  1. Pemeriksa PIN / kode recovery di server
-- ---------------------------------------------------------------------
create or replace function public.cocok_pin(p_nilai text, p_garam text, p_hash text)
returns boolean
language plpgsql
immutable
set search_path = public, extensions
as $$
declare
  putaran int;
  harap   bytea;
  kunci   bytea;
  u       bytea;
  t       bit(256);
begin
  if p_nilai is null or p_garam is null or p_hash is null
     or not public.hash_kredensial_sah(p_hash) then
    return false;
  end if;
  kunci := convert_to(p_nilai, 'UTF8');
  putaran := split_part(p_hash, ':', 2)::int;
  harap := decode(split_part(p_hash, ':', 3), 'base64');
  -- PBKDF2-HMAC-SHA256, satu blok 32 byte.
  u := extensions.hmac(convert_to(p_garam, 'UTF8') || '\x00000001'::bytea, kunci, 'sha256');
  t := ('x' || encode(u, 'hex'))::bit(256);
  for i in 2..putaran loop
    u := extensions.hmac(u, kunci, 'sha256');
    t := t # ('x' || encode(u, 'hex'))::bit(256);
  end loop;
  return t = ('x' || encode(harap, 'hex'))::bit(256);
end;
$$;

revoke all on function public.cocok_pin(text, text, text)
  from public, anon, authenticated;
revoke all on function public.hash_kredensial_sah(text)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------
--  2. Kolom hash wajib sah
-- ---------------------------------------------------------------------
alter table public.users drop constraint if exists users_pin_hash_sah;
alter table public.users
  add constraint users_pin_hash_sah
  check (public.hash_kredensial_sah(pin_hash));

alter table public.users drop constraint if exists users_recovery_hash_sah;
alter table public.users
  add constraint users_recovery_hash_sah
  check (recovery_hash is null or public.hash_kredensial_sah(recovery_hash));

-- ---------------------------------------------------------------------
--  3. Kunci kode recovery milik tiap HP
-- ---------------------------------------------------------------------
create or replace function public.abaikan_kunci_recovery()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' then
    new.recovery_attempts := 0;
    new.recovery_locked_until := null;
  else
    new.recovery_attempts := old.recovery_attempts;
    new.recovery_locked_until := old.recovery_locked_until;
  end if;
  return new;
end $$;

drop trigger if exists trg_users_abaikan_kunci_recovery on public.users;
create trigger trg_users_abaikan_kunci_recovery
  before insert or update on public.users
  for each row execute function public.abaikan_kunci_recovery();

revoke all on function public.abaikan_kunci_recovery()
  from public, anon, authenticated;

-- Kunci yang mungkin sudah tertanam dilepas sekali.
update public.users
   set recovery_attempts = 0, recovery_locked_until = null
 where recovery_attempts <> 0 or recovery_locked_until is not null;

-- =====================================================================
--  PEMERIKSAAN SESUDAH DIJALANKAN
--
--    select public.cocok_pin('123456', 'g', 'pbkdf2:1:');          -- false
--    select conname from pg_constraint
--     where conname in ('users_pin_hash_sah', 'users_recovery_hash_sah');
--    -- 2 baris
-- =====================================================================

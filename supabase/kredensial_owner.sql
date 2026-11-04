-- =====================================================================
--  KREDENSIAL OWNER HANYA BISA DIGANTI DENGAN BUKTI (review A1, 4 Nov 2026)
--
--  Jalankan lewat SQL Editor di dashboard Supabase SESUDAH kunci_kolom.sql
--  dan perangkat.sql (butuh pgcrypto). Aman diulang.
--
--  ── MASALAH YANG DIPECAHKAN ──
--
--  Server hanya tahu "HP ini terdaftar", bukan siapa yang memegangnya. HP
--  terdaftar mana pun boleh mengubah baris users — termasuk PIN dan kode
--  recovery OWNER. Kasir yang mengakali aplikasinya bisa mengirim
--  "PIN owner = 111111", semua HP ikut memakainya saat sinkron, kasir masuk
--  sebagai owner, dan owner asli terkunci tanpa kode recovery.
--
--  → PIN, garam, kode recovery, status aktif, nama, dan tanda hapus akun
--    OWNER hanya berubah lewat ubah_kredensial_owner, yang memeriksa
--    sendiri PIN lama atau kode recovery-nya. Perubahan lewat jalur lain
--    dikembalikan (seperti kunci_kolom.sql) dan updated_at dinaikkan,
--    supaya semua HP menarik nilai yang benar.
--
--  Akun owner kedua sudah ditolak sejak kunci_kolom.sql (tolak_owner_kedua).
--
--  ── KONSEKUENSI ──
--    Reset PIN owner dengan kode recovery, dan "Buat kode recovery baru",
--    butuh internet. Login tetap bisa offline.
--    APK lama yang mereset PIN owner tanpa internet: perubahannya
--    dikembalikan server saat sinkron.
-- =====================================================================

-- PIN / kode recovery cocok dengan hash-nya — sama persis dengan
-- CryptoUtils.verifyPin / HashUtils.verifyWithSalt di aplikasi
-- (PBKDF2-HMAC-SHA256 "pbkdf2:<putaran>:<base64>", atau SHA-256 format lama).
create or replace function public.cocok_pin(p_nilai text, p_garam text, p_hash text)
returns boolean
language plpgsql
immutable
set search_path = public, extensions
as $$
declare
  isi     text;
  putaran int;
  harap   bytea;
  kunci   bytea := convert_to(p_nilai, 'UTF8');
  u       bytea;
  t       bit(256);
begin
  if p_nilai is null or p_garam is null or p_hash is null then
    return false;
  end if;
  if p_hash not like 'pbkdf2:%' then
    -- Format lama: SHA-256(pin + garam), heksadesimal.
    return encode(extensions.digest(p_nilai || p_garam, 'sha256'), 'hex') = p_hash;
  end if;
  isi := substr(p_hash, 8);
  putaran := split_part(isi, ':', 1)::int;
  harap := decode(split_part(isi, ':', 2), 'base64');
  if putaran is null or putaran <= 0 or length(harap) <> 32 then
    return false;
  end if;
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

-- ---------------------------------------------------------------------
--  Penjaga baris owner
-- ---------------------------------------------------------------------
create or replace function public.jaga_akun_owner()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  dikoreksi boolean := false;
begin
  if old.role <> 'owner'
     or coalesce(current_setting('teras.ubah_kredensial', true), '') = 'ya' then
    return new;
  end if;
  if new.pin_hash is distinct from old.pin_hash
     or new.salt is distinct from old.salt
     or new.recovery_hash is distinct from old.recovery_hash
     or new.recovery_salt is distinct from old.recovery_salt
     or new.is_active is distinct from old.is_active
     or new.username is distinct from old.username
     or new.deleted_at is distinct from old.deleted_at then
    new.pin_hash := old.pin_hash;
    new.salt := old.salt;
    new.recovery_hash := old.recovery_hash;
    new.recovery_salt := old.recovery_salt;
    new.is_active := old.is_active;
    new.username := old.username;
    new.deleted_at := old.deleted_at;
    dikoreksi := true;
  end if;
  if dikoreksi then
    new.updated_at :=
      greatest(new.updated_at, old.updated_at, now()) + interval '1 second';
  end if;
  return new;
end $$;

drop trigger if exists trg_users_jaga_owner on public.users;
create trigger trg_users_jaga_owner
  before update on public.users
  for each row execute function public.jaga_akun_owner();

revoke all on function public.jaga_akun_owner()
  from public, anon, authenticated;

-- ---------------------------------------------------------------------
--  Satu-satunya jalan mengganti kredensial owner.
--
--  p_jenis 'pin'      : p_bukti = PIN owner saat ini.
--  p_jenis 'recovery' : p_bukti = kode recovery (tanpa strip, huruf besar).
--  Kolom baru yang null tidak diubah.
--
--  Jawaban: 'ok' | 'salah' | 'belum_ada' (baris owner belum sampai ke
--  server — dibuat offline; aplikasinya boleh lanjut, barisnya nanti
--  dikirim sebagai baris baru).
--
--  Hak pemanggil (security invoker): hanya HP yang terdaftar & aktif yang
--  bisa membaca dan mengubah baris users (rls.sql).
-- ---------------------------------------------------------------------
create or replace function public.ubah_kredensial_owner(
  p_bukti text,
  p_jenis text,
  p_pin_hash text default null,
  p_salt text default null,
  p_recovery_hash text default null,
  p_recovery_salt text default null
)
returns text
language plpgsql
security invoker
set search_path = public
as $$
declare
  o public.users;
  cocok boolean;
begin
  select * into o from public.users
   where role = 'owner' and deleted_at is null
   order by created_at
   limit 1
   for update;
  if not found then
    return 'belum_ada';
  end if;

  cocok := case p_jenis
    when 'pin' then public.cocok_pin(p_bukti, o.salt, o.pin_hash)
    when 'recovery' then public.cocok_pin(p_bukti, o.recovery_salt, o.recovery_hash)
    else false
  end;
  if not coalesce(cocok, false) then
    return 'salah';
  end if;
  if (p_pin_hash is null) <> (p_salt is null)
     or (p_recovery_hash is null) <> (p_recovery_salt is null) then
    raise exception 'hash dan garam harus berpasangan' using errcode = '22023';
  end if;

  perform set_config('teras.ubah_kredensial', 'ya', true);
  update public.users
     set pin_hash = coalesce(p_pin_hash, pin_hash),
         salt = coalesce(p_salt, salt),
         recovery_hash = coalesce(p_recovery_hash, recovery_hash),
         recovery_salt = coalesce(p_recovery_salt, recovery_salt),
         updated_at = greatest(updated_at, now())
   where id = o.id;
  perform set_config('teras.ubah_kredensial', '', true);
  return 'ok';
end $$;

revoke all on function public.ubah_kredensial_owner(text, text, text, text, text, text)
  from public, anon;
grant execute on function public.ubah_kredensial_owner(text, text, text, text, text, text)
  to authenticated;

-- =====================================================================
--  PEMERIKSAAN SESUDAH DIJALANKAN
--
--    select count(*) from pg_trigger where tgname = 'trg_users_jaga_owner';
--    -- 1
--    select public.ubah_kredensial_owner('000000', 'pin');
--    -- salah   (dari SQL Editor; kecuali PIN owner memang 000000)
-- =====================================================================

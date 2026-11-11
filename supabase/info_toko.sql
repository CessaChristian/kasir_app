-- =====================================================================
--  INFO OUTLET DI NOTA (permintaan owner, 11 Nov 2026)
--
--  Jalankan SEKALI lewat SQL Editor di dashboard Supabase. Di server yang
--  sudah berjalan cukup berkas ini saja; saat membangun dari nol, urutannya
--  sebelum `rls.sql` (lihat URUTAN.md). Aman diulang.
--
--  Sebaiknya dijalankan SEBELUM memasang APK dengan basis data v43. APK itu
--  tetap jalan tanpa berkas ini (nota memakai alamat bawaan aplikasi), tapi
--  perubahan Info Outlet baru sampai ke HP lain sesudah berkas ini ada.
--
--  ── MASALAH YANG DIPECAHKAN ──
--
--  Alamat, nomor HP, dan WiFi di nota tertanam di aplikasi: menggantinya
--  berarti membuat APK baru. Owner ingin menggantinya sendiri dari Profil.
--
--  ── ISINYA ──
--
--  Tabel `info_toko` berisi TEPAT SATU baris (id tetap). Ikut sinkron seperti
--  tabel data lain: perubahan terbaru menang, urutan kedatangan dicap server,
--  hanya perangkat terdaftar & aktif yang boleh membaca/mengubah, tanpa
--  DELETE. Nama toko sengaja tidak ada di sini (keputusan owner: tetap).
--
--  Baris awal berisi nilai yang selama ini tercetak, jadi nota tidak berubah
--  sesudah berkas ini dijalankan. Capnya sengaja tua (1 Jan 2026): perubahan
--  owner dari HP mana pun, kapan pun dibuatnya, selalu menang atas baris awal.
-- =====================================================================

create table if not exists public.info_toko (
  id          uuid primary key
              default '00000000-0000-0000-0000-000000000001'
              check (id = '00000000-0000-0000-0000-000000000001'),
  alamat      text not null check (length(btrim(alamat)) between 1 and 64),
  no_hp       text not null check (length(btrim(no_hp)) between 1 and 20),
  -- Kosong = baris WiFi tidak dicetak.
  wifi_nama   text not null default '' check (length(wifi_nama) <= 32),
  wifi_sandi  text not null default '' check (length(wifi_sandi) <= 32),
  updated_at  timestamptz not null default now(),
  server_urut timestamptz not null default clock_timestamp()
);

insert into public.info_toko (alamat, no_hp, wifi_nama, wifi_sandi, updated_at)
values ('Jl. Kemiri Candi', '087859665084', 'TERAS INN', 'terasinspirasi',
        '2026-01-01 00:00:00+07')
on conflict (id) do nothing;

create index if not exists idx_info_toko_server_urut
  on public.info_toko (server_urut);

-- ---------------------------------------------------------------------
--  Akses — sama dengan tabel data lain (perangkat_tegakkan.sql, rls.sql).
-- ---------------------------------------------------------------------
alter table public.info_toko enable row level security;

drop policy if exists baca_info_toko   on public.info_toko;
drop policy if exists tambah_info_toko on public.info_toko;
drop policy if exists ubah_info_toko   on public.info_toko;

create policy baca_info_toko on public.info_toko
  for select to authenticated
  using (public.perangkat_aktif());

create policy tambah_info_toko on public.info_toko
  for insert to authenticated
  with check (public.perangkat_aktif());

create policy ubah_info_toko on public.info_toko
  for update to authenticated
  using (public.perangkat_aktif())
  with check (public.perangkat_aktif());

revoke all on public.info_toko from anon;
revoke delete, truncate, trigger, references on public.info_toko
  from authenticated;
grant select, insert, update on public.info_toko to authenticated;

-- ---------------------------------------------------------------------
--  Penjaga sinkron yang sama dengan tabel lain: cap asli kiriman
--  (versi_asli.sql), versi terbaru menang (tolak_versi_lama.sql), urutan
--  kedatangan (sync_urutan.sql).
-- ---------------------------------------------------------------------
drop trigger if exists trg_info_toko_aa_cap_asli on public.info_toko;
create trigger trg_info_toko_aa_cap_asli
  before insert on public.info_toko
  for each row execute function public.catat_cap_asli();

drop trigger if exists trg_info_toko_jaga_versi on public.info_toko;
create trigger trg_info_toko_jaga_versi
  before insert or update on public.info_toko
  for each row execute function public.jaga_versi_terbaru();

drop trigger if exists trg_info_toko_server_urut on public.info_toko;
create trigger trg_info_toko_server_urut
  before insert or update on public.info_toko
  for each row execute function public.stempel_server_urut();

-- =====================================================================
--  PEMERIKSAAN SESUDAH DIJALANKAN
--
--    select alamat, no_hp, wifi_nama from public.info_toko;
--    -- harus 1 baris
--
--    select policyname, cmd from pg_policies where tablename = 'info_toko';
--    -- harus 3 baris: SELECT, INSERT, UPDATE (tanpa DELETE)
--
--    select tgname from pg_trigger
--     where tgrelid = 'public.info_toko'::regclass and not tgisinternal;
--    -- harus 3 baris: aa_cap_asli, jaga_versi, server_urut
-- =====================================================================

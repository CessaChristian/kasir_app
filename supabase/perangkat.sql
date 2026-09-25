-- =====================================================================
--  DAFTAR PERANGKAT
--
--  Jalankan SEKALI lewat SQL Editor di dashboard Supabase.
--  Aman dijalankan ulang: semuanya memakai `if not exists` / `or replace`.
--
--  ── APA YANG DIPECAHKAN ──
--
--  Tiket yang dipegang HP tidak pernah ditanyakan ulang ke server: server
--  cuma memeriksa tanda tangannya asli dan belum kedaluwarsa. Akibatnya
--  mencabut sebuah HP baru terasa setelah tiketnya habis — sampai 60 menit.
--
--  Tabel ini yang membuat pencabutan berlaku SEKETIKA: server membaca daftar
--  ini di setiap permintaan, jadi begitu statusnya berubah, permintaan
--  berikutnya langsung ditolak.
--
--  CATATAN: penegakannya belum dinyalakan oleh berkas ini. Lihat bagian 6.
-- =====================================================================

-- ---------------------------------------------------------------------
--  1. Tempat menyimpan sidik jari kunci pemasangan
--
--  Kuncinya TIDAK disimpan apa adanya. Yang tersimpan hasil pengacakannya,
--  jadi isi tabel ini bocor pun kuncinya tetap tidak terbaca.
--
--  Tabel ini sengaja tanpa policy apa pun: artinya tidak ada satu pun
--  perangkat yang bisa membacanya. Yang boleh menyentuhnya hanya fungsi di
--  bawah, yang berjalan dengan hak pemiliknya sendiri.
-- ---------------------------------------------------------------------
create extension if not exists pgcrypto with schema extensions;

create table if not exists public.rahasia (
  nama  text primary key,
  nilai text not null
);
alter table public.rahasia enable row level security;

-- ---------------------------------------------------------------------
--  1b. Menyimpan kunci pemasangan
--
--  SENGAJA tidak diisi di berkas ini: repositori ini PUBLIK, dan menuliskan
--  kuncinya di sini sama saja mengumumkannya. Jalankan perintah di bawah
--  secara terpisah lewat SQL Editor, dengan kunci yang sebenarnya.
--
--    insert into public.rahasia (nama, nilai)
--    values ('kunci_pemasangan',
--            extensions.crypt('GANTI-DENGAN-KUNCI-ASLI', extensions.gen_salt('bf')))
--    on conflict (nama) do update set nilai = excluded.nilai;
--
--  Perintah yang sama dipakai untuk MENGGANTI kunci kapan pun. Perangkat
--  yang sudah terdaftar tidak terpengaruh — kunci hanya dipakai saat
--  mendaftar.
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
--  2. Daftar perangkat
-- ---------------------------------------------------------------------
create table if not exists public.perangkat (
  id             uuid primary key references auth.users(id) on delete cascade,
  nama           text        not null default 'Perangkat',
  status         text        not null default 'aktif'
                             check (status in ('aktif', 'dicabut')),
  terakhir_aktif timestamptz not null default now(),
  dibuat_pada    timestamptz not null default now()
);
alter table public.perangkat enable row level security;

drop policy if exists baca_perangkat on public.perangkat;
create policy baca_perangkat on public.perangkat
  for select to authenticated using (true);

--  TIDAK ADA policy INSERT, UPDATE, maupun DELETE.
--
--  Semua perubahan lewat fungsi di bawah, supaya syaratnya tidak bisa
--  dilangkahi — dan supaya syarat "ganti nama" bisa berbeda dari syarat
--  "ubah status". Percobaan pertama memakai satu policy `id <> auth.uid()`
--  untuk keduanya, dan akibatnya pemilik tidak bisa mengganti nama HP-nya
--  sendiri: aturan yang dimaksudkan menjaga status ikut memblokir hal yang
--  sama sekali tidak berbahaya.
drop policy if exists ubah_perangkat_lain on public.perangkat;

-- ---------------------------------------------------------------------
--  3. Mendaftarkan perangkat — butuh kunci pemasangan
-- ---------------------------------------------------------------------
create or replace function public.daftarkan_perangkat(
  p_kunci text,
  p_nama  text
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not exists (
    select 1 from public.rahasia
    where nama = 'kunci_pemasangan' and nilai = crypt(p_kunci, nilai)
  ) then
    raise exception 'kunci pemasangan salah' using errcode = '28000';
  end if;

  insert into public.perangkat (id, nama)
  values (auth.uid(), coalesce(nullif(btrim(p_nama), ''), 'Perangkat'))
  on conflict (id) do update
    set status = 'aktif', terakhir_aktif = now();
end $$;

revoke all on function public.daftarkan_perangkat(text, text) from public;
grant execute on function public.daftarkan_perangkat(text, text) to authenticated;

-- ---------------------------------------------------------------------
--  4. Penanda "aku masih dipakai"
--
--  Sengaja HANYA memperbarui, tidak pernah menyisipkan. Kalau ia juga bisa
--  menyisipkan, perangkat yang barisnya sudah dilupakan pemilik akan
--  mendaftarkan dirinya kembali diam-diam — dan pencabutan jadi sia-sia.
-- ---------------------------------------------------------------------
create or replace function public.perangkat_hadir()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.perangkat
     set terakhir_aktif = now()
   where id = auth.uid();
end $$;

revoke all on function public.perangkat_hadir() from public;
grant execute on function public.perangkat_hadir() to authenticated;

-- ---------------------------------------------------------------------
--  4b. Mengganti nama perangkat — termasuk perangkat sendiri
--
--  Nama cuma label untuk manusia; menggantinya tidak memberi akses apa pun.
--  Maka perangkat sendiri BOLEH diganti namanya — justru itu yang paling
--  sering dilakukan pemilik saat pertama menata daftarnya.
-- ---------------------------------------------------------------------
create or replace function public.ubah_nama_perangkat(p_id uuid, p_nama text)
returns void
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

  update public.perangkat
     set nama = coalesce(nullif(btrim(p_nama), ''), nama)
   where id = p_id;
end $$;

revoke all on function public.ubah_nama_perangkat(uuid, text) from public;
grant execute on function public.ubah_nama_perangkat(uuid, text) to authenticated;

-- ---------------------------------------------------------------------
--  4c. Mencabut / memulihkan perangkat LAIN
--
--  Di sinilah larangan "bukan diri sendiri" berlaku, dan hanya di sini.
--  Tanpa itu, HP yang dicabut tinggal memulihkan dirinya sendiri dan seluruh
--  pencabutan jadi percuma.
-- ---------------------------------------------------------------------
create or replace function public.ubah_status_perangkat(
  p_id    uuid,
  p_aktif boolean
)
returns void
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

  update public.perangkat
     set status = case when p_aktif then 'aktif' else 'dicabut' end
   where id = p_id;
end $$;

revoke all on function public.ubah_status_perangkat(uuid, boolean) from public;
grant execute on function public.ubah_status_perangkat(uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------
--  5. Melupakan perangkat — beserta identitasnya
--
--  Syaratnya berlapis, dan tiap lapis menutup satu jalan:
--    - pemanggilnya harus perangkat yang AKTIF  -> yang dicabut tak berdaya
--    - tidak boleh dirinya sendiri              -> tak bisa kabur
--    - targetnya harus sudah DICABUT            -> tak bisa menghapus yang
--      masih dipakai, jadi tidak ada penghapusan karena salah pencet
--    - identitas yang dihapus harus anonim      -> akun sungguhan seperti
--      owner@ tidak akan pernah bisa tersentuh
-- ---------------------------------------------------------------------
create or replace function public.lupakan_perangkat(p_id uuid)
returns void
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

  delete from public.perangkat where id = p_id;
  delete from auth.users where id = p_id and is_anonymous = true;
end $$;

revoke all on function public.lupakan_perangkat(uuid) from public;
grant execute on function public.lupakan_perangkat(uuid) to authenticated;

-- =====================================================================
--  6. PENEGAKAN — SENGAJA BELUM DINYALAKAN DI SINI
--
--  Menyalakannya berarti menambah syarat "perangkat harus aktif" ke policy
--  seluruh tabel data. Itu langkah yang bisa mengunci SEMUA HP sekaligus
--  kalau dijalankan sebelum setiap HP sempat terdaftar.
--
--  Urutan amannya:
--    1. jalankan berkas ini
--    2. pasang aplikasi versi baru di semua HP
--    3. BUKA halaman Perangkat, pastikan SEMUA HP muncul dan aktif  <- gerbang
--    4. baru jalankan supabase/perangkat_tegakkan.sql
--
--  Langkah 3 itu gerbangnya, dan alasannya nyata: pembersih berkas foto
--  dulu membuang foto yang sedang dipilih pengguna justru karena aturannya
--  dijalankan sebelum datanya sempat terdaftar.
-- =====================================================================

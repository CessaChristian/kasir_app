-- =====================================================================
--  NOMOR NOTA PENDEK — NOMOR KASIR & KODE PERANGKAT
--
--  Jalankan lewat SQL Editor di dashboard Supabase SEBELUM memasang APK
--  yang menerbitkan nota `CS/01/171026/A-0001`. Aman diulang.
--
--  ── MASALAH YANG DIPECAHKAN ──
--
--  Nomor nota lama `TRX/17/10/26/K7QX-0012` panjang, dan kode perangkatnya
--  4 huruf acak yang hanya tersimpan di HP — tidak bisa dicocokkan ke HP
--  mana pun dari data. Keputusan owner 2026-10-17:
--
--      CS / <nomor kasir> / <tanggal buka shift ddMMyy> / <kode HP>-<urut>
--
--  Id (UUID) tetap dipakai sistem dan TIDAK diganti: perangkat.id adalah id
--  login Supabase Auth, dan users.id dirujuk hampir semua tabel. UUID juga
--  yang membuat HP bisa mencatat data saat offline. Yang ditambahkan hanya
--  nomor pendek untuk dibaca manusia.
--
--  ── KOLOM BARU ──
--
--    users.nomor_kasir   owner = 0, kasir 1, 2, 3, ... urut dibuat. Kasir
--                        yang dihapus TETAP memegang nomornya — tidak
--                        dipakai ulang, supaya nota lama tidak tertukar
--                        orang.
--    perangkat.kode      A, B, ..., Z, AA, AB, ... urut didaftarkan. Juga
--                        tidak dipakai ulang walau perangkatnya dilupakan.
-- =====================================================================

alter table public.users     add column if not exists nomor_kasir integer;
alter table public.perangkat add column if not exists kode text;

create unique index if not exists users_nomor_kasir_unik
  on public.users (nomor_kasir);
create unique index if not exists perangkat_kode_unik
  on public.perangkat (kode);

-- ---------------------------------------------------------------------
--  Kode ke-n: 1 → A, 26 → Z, 27 → AA, 28 → AB, ...
-- ---------------------------------------------------------------------
create or replace function public.kode_perangkat_ke(n integer)
returns text
language plpgsql
immutable
as $$
declare
  hasil text := '';
  sisa  integer := n;
begin
  while sisa > 0 loop
    sisa  := sisa - 1;
    hasil := chr(65 + sisa % 26) || hasil;
    sisa  := sisa / 26;
  end loop;
  return hasil;
end $$;

-- ---------------------------------------------------------------------
--  Penanda kode terakhir yang pernah dibagikan. Disimpan terpisah supaya
--  kode perangkat yang DILUPAKAN (barisnya dihapus) tidak dibagikan lagi.
-- ---------------------------------------------------------------------
create table if not exists public.nomor_terakhir (
  nama  text primary key,
  nilai integer not null
);
alter table public.nomor_terakhir enable row level security;
-- Tanpa policy: hanya fungsi security definer di bawah yang menyentuhnya.

-- ---------------------------------------------------------------------
--  Isi awal: perangkat yang sudah ada, urut didaftarkan.
-- ---------------------------------------------------------------------
with urut as (
  select id, row_number() over (order by dibuat_pada, id) as n
  from public.perangkat
  where kode is null
)
update public.perangkat p
   set kode = public.kode_perangkat_ke(
         urut.n::integer
         + coalesce((select nilai from public.nomor_terakhir
                     where nama = 'perangkat'), 0))
  from urut
 where p.id = urut.id;

insert into public.nomor_terakhir (nama, nilai)
select 'perangkat', count(*) from public.perangkat
on conflict (nama) do update
  set nilai = greatest(public.nomor_terakhir.nilai, excluded.nilai);

-- ---------------------------------------------------------------------
--  Daftarkan perangkat — sama seperti perangkat.sql, ditambah kode untuk
--  perangkat BARU. Perangkat yang mendaftar ulang dengan identitas yang
--  sama tetap memegang kodenya.
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
declare
  v_n integer;
begin
  if not exists (
    select 1 from public.rahasia
    where nama = 'kunci_pemasangan' and nilai = crypt(p_kunci, nilai)
  ) then
    raise exception 'kunci pemasangan salah' using errcode = '28000';
  end if;

  if exists (select 1 from public.perangkat where id = auth.uid()) then
    update public.perangkat
       set status = 'aktif', terakhir_aktif = now()
     where id = auth.uid();
    return;
  end if;

  -- Satu pernyataan: dua HP yang mendaftar bersamaan tidak mendapat kode
  -- yang sama (baris penanda terkunci sampai transaksi selesai).
  insert into public.nomor_terakhir (nama, nilai) values ('perangkat', 1)
  on conflict (nama) do update set nilai = public.nomor_terakhir.nilai + 1
  returning nilai into v_n;

  insert into public.perangkat (id, nama, kode)
  values (auth.uid(),
          coalesce(nullif(btrim(p_nama), ''), 'Perangkat'),
          public.kode_perangkat_ke(v_n));
end $$;

revoke all on function public.daftarkan_perangkat(text, text) from public;
grant execute on function public.daftarkan_perangkat(text, text) to authenticated;

-- ---------------------------------------------------------------------
--  Isi awal nomor kasir: owner 0, kasir urut dibuat (termasuk yang sudah
--  dihapus). updated_at dimajukan supaya semua HP menarik nomornya — HP
--  hanya menerima baris server yang ≥1 detik lebih baru dari miliknya.
-- ---------------------------------------------------------------------
update public.users
   set nomor_kasir = 0,
       updated_at  = greatest(updated_at, now()) + interval '1 second'
 where role = 'owner' and nomor_kasir is null;

with urut as (
  select id,
         row_number() over (order by created_at, id)
         + coalesce((select max(nomor_kasir) from public.users
                     where role = 'cashier'), 0) as n
  from public.users
  where role = 'cashier' and nomor_kasir is null
)
update public.users u
   set nomor_kasir = urut.n,
       updated_at  = greatest(u.updated_at, now()) + interval '1 second'
  from urut
 where u.id = urut.id;

-- ---------------------------------------------------------------------
--  Cadangan untuk HP yang belum diperbarui: kasir baru dari APK lama
--  datang tanpa nomor — server memberinya nomor berikutnya. APK baru
--  sudah mengirim nomornya sendiri, jadi ini tidak tersentuh.
--
--  updated_at dimajukan +1 detik supaya HP pengirimnya ikut menerima
--  nomor itu pada tarikan berikutnya.
-- ---------------------------------------------------------------------
create or replace function public.isi_nomor_kasir()
returns trigger
language plpgsql
as $$
begin
  if new.nomor_kasir is null then
    if new.role = 'owner' then
      new.nomor_kasir := 0;
    else
      new.nomor_kasir := coalesce(
        (select max(nomor_kasir) from public.users), 0) + 1;
    end if;
    new.updated_at := greatest(new.updated_at, now()) + interval '1 second';
  end if;
  return new;
end $$;

drop trigger if exists trg_users_nomor_kasir on public.users;
create trigger trg_users_nomor_kasir
  before insert on public.users
  for each row execute function public.isi_nomor_kasir();

-- =====================================================================
--  PEMERIKSAAN SESUDAH DIJALANKAN
--
--    select nama, kode, dibuat_pada from public.perangkat
--     order by dibuat_pada;
--    -- 3 perangkat: A, B, C sesuai urutan didaftarkan
--
--    select username, role, nomor_kasir from public.users
--     order by nomor_kasir;
--    -- owner 0, kasir 1, 2, ... tanpa yang kosong
--
--    select tgname from pg_trigger where tgname = 'trg_users_nomor_kasir';
--    -- harus 1 baris
-- =====================================================================

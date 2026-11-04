-- =====================================================================
--  PRODUK KEMBAR DARI HP OFFLINE DIGABUNG (keputusan owner, 4 Nov 2026)
--
--  Jalankan lewat SQL Editor di dashboard Supabase SESUDAH open_bill_aman.sql
--  dan kunci_kolom.sql. Aman diulang.
--
--  ── MASALAH YANG DIPECAHKAN ──
--
--  Nama kembar hanya bisa dicek di dalam satu HP. HP A dan HP B yang sama-sama
--  offline bisa membuat "Es Teh" dan menjualnya. Begitu online, daftar produk
--  berisi dua Es Teh dan penjualannya terpecah di laporan.
--
--  ── ATURANNYA ──
--
--  Yang duluan sampai ke server yang dipakai. Yang datang belakangan:
--    1. ditandai terhapus, jadi hilang sendiri dari semua HP;
--    2. dicatat di produk_gabung;
--    3. item transaksi dan open bill-nya dipindah ke produk yang dipakai.
--
--  Harga, kategori, dan pilihan level mengikuti yang duluan sampai. Fotonya
--  dipakai hanya kalau yang duluan belum punya foto. Item transaksi lama tetap
--  memakai nama dan harga saat dijual: yang pindah cuma product_id-nya.
--
--  Ganti nama offline yang berujung kembar diperlakukan sama. Kembar yang
--  SUDAH ada di server tidak disentuh: daftarnya tampil di akhir berkas ini.
--
--  ── KENAPA ADA TABEL produk_gabung ──
--
--  HP bisa baru mengirim transaksinya berhari-hari sesudah produknya digabung,
--  dan baris produk yang terhapus bisa sudah dibuang buang_sampah. Tabel ini
--  tidak pernah dibuang, jadi kiriman selambat apa pun tetap diarahkan benar.
--
--  ── URUTAN TRIGGER ──
--
--  Trigger BEFORE berjalan urut abjad. Nama-nama di bawah sengaja jatuh SESUDAH
--  jaga_versi, jaga_status_bill, dan kunci_kolom, dan SEBELUM server_urut.
--
--  updated_at selalu dinaikkan 1 detik: aplikasi membandingkan versi per detik,
--  jadi tanpa itu HP pengirim menganggap versinya sendiri sama baru.
-- =====================================================================

create table if not exists public.produk_gabung (
  id_lama uuid primary key,
  id_baru uuid not null,
  dibuat  timestamptz not null default now()
);

-- Hanya untuk fungsi di berkas ini. Tanpa policy: aplikasi tidak bisa membacanya.
alter table public.produk_gabung enable row level security;
revoke all on public.produk_gabung from public, anon, authenticated;

-- ---------------------------------------------------------------------
--  Isi open bill: [{"p": id_produk, "q": jumlah, "c": catatan}]
--  Baris yang jadi sama sesudah dipetakan dijumlahkan.
-- ---------------------------------------------------------------------
create or replace function public.peta_isi_bill(p_items jsonb)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with baris as (
    select e.urut,
           coalesce(g.id_baru::text, e.isi->>'p') as p,
           (e.isi->>'q')::numeric as q,
           e.isi->>'c' as c
      from jsonb_array_elements(p_items) with ordinality as e(isi, urut)
      left join public.produk_gabung g on g.id_lama::text = e.isi->>'p'
  ), ringkas as (
    select min(urut) as urut, p, sum(q) as q, c
      from baris
     group by p, c
  )
  select coalesce(
    jsonb_agg(
      jsonb_strip_nulls(jsonb_build_object('p', p, 'q', q, 'c', c))
      order by urut
    ),
    '[]'::jsonb
  )
  from ringkas
$$;

-- ---------------------------------------------------------------------
--  Produk masuk atau berubah nama
-- ---------------------------------------------------------------------
create or replace function public.gabung_produk_kembar()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_kunci text := lower(btrim(new.name));
  v_pakai public.products%rowtype;
begin
  if new.deleted_at is not null then
    return new;
  end if;
  -- Perubahan biasa tidak diperiksa, supaya kembar lama tidak ikut tergabung.
  if tg_op = 'UPDATE'
     and old.deleted_at is null
     and lower(btrim(old.name)) = v_kunci then
    return new;
  end if;

  -- Dua kiriman bernama sama yang bersamaan: yang kedua menunggu yang pertama.
  perform pg_advisory_xact_lock(hashtext('produk_kembar:' || v_kunci));

  select * into v_pakai
    from public.products p
   where p.id <> new.id
     and p.deleted_at is null
     and lower(btrim(p.name)) = v_kunci
   order by p.created_at, p.id
   limit 1;

  if not found then
    -- Hidup lagi dan tidak kembar: tidak lagi digabung ke mana pun.
    delete from public.produk_gabung where id_lama = new.id;
    return new;
  end if;

  insert into public.produk_gabung (id_lama, id_baru)
  values (new.id, v_pakai.id)
  on conflict (id_lama) do update set id_baru = excluded.id_baru;
  update public.produk_gabung set id_baru = v_pakai.id where id_baru = new.id;

  if v_pakai.image_path is null and new.image_path is not null then
    update public.products
       set image_path = new.image_path,
           updated_at = greatest(now(), updated_at) + interval '1 second'
     where id = v_pakai.id;
  end if;

  update public.transaction_items
     set product_id = v_pakai.id,
         updated_at = greatest(now(), updated_at) + interval '1 second'
   where product_id = new.id;

  -- Disentuh saja: pemetaannya dikerjakan trigger open_bills di bawah.
  update public.open_bills b
     set updated_at = greatest(now(), b.updated_at)
   where b.transaction_id is null
     and b.deleted_at is null
     and b.items @> jsonb_build_array(jsonb_build_object('p', new.id::text));

  new.deleted_at := now();
  new.updated_at := greatest(now(), new.updated_at) + interval '1 second';
  return new;
end $$;

drop trigger if exists trg_products_kembar on public.products;
create trigger trg_products_kembar
  before insert or update on public.products
  for each row execute function public.gabung_produk_kembar();

-- ---------------------------------------------------------------------
--  Item transaksi dari HP yang terlambat tahu
-- ---------------------------------------------------------------------
create or replace function public.arahkan_item_produk_gabung()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_baru uuid;
begin
  select id_baru into v_baru
    from public.produk_gabung
   where id_lama = new.product_id;
  if found then
    new.product_id := v_baru;
    new.updated_at := greatest(now(), new.updated_at) + interval '1 second';
  end if;
  return new;
end $$;

drop trigger if exists trg_transaction_items_produk_gabung
  on public.transaction_items;
create trigger trg_transaction_items_produk_gabung
  before insert or update on public.transaction_items
  for each row execute function public.arahkan_item_produk_gabung();

-- ---------------------------------------------------------------------
--  Open bill dari HP yang terlambat tahu
--
--  Bill yang sudah lunas/dihapus dibiarkan. Bill yang sedang dibayar juga:
--  aplikasi membandingkan isinya saat membayar, dan item transaksinya tetap
--  diarahkan trigger di atas. Isinya dipetakan begitu klaimnya dilepas.
-- ---------------------------------------------------------------------
create or replace function public.arahkan_bill_produk_gabung()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.transaction_id is not null
     or new.deleted_at is not null
     or public.klaim_berlaku(new.klaim_tx, new.klaim_pada)
     or jsonb_typeof(new.items) <> 'array' then
    return new;
  end if;
  if exists (
    select 1
      from jsonb_array_elements(new.items) as e(isi)
      join public.produk_gabung g on g.id_lama::text = e.isi->>'p'
  ) then
    new.items := public.peta_isi_bill(new.items);
    new.updated_at := greatest(now(), new.updated_at) + interval '1 second';
  end if;
  return new;
end $$;

drop trigger if exists trg_open_bills_produk_gabung on public.open_bills;
create trigger trg_open_bills_produk_gabung
  before insert or update on public.open_bills
  for each row execute function public.arahkan_bill_produk_gabung();

-- Fungsi-fungsi ini tidak untuk dipanggil langsung lewat API.
revoke all on function public.peta_isi_bill(jsonb)
  from public, anon, authenticated;
revoke all on function public.gabung_produk_kembar()
  from public, anon, authenticated;
revoke all on function public.arahkan_item_produk_gabung()
  from public, anon, authenticated;
revoke all on function public.arahkan_bill_produk_gabung()
  from public, anon, authenticated;

-- ---------------------------------------------------------------------
--  Kembar yang SUDAH ada di server. Tidak diubah; kirim hasilnya ke developer.
--  Kosong = tidak ada.
-- ---------------------------------------------------------------------
select lower(btrim(name)) as nama, count(*) as jumlah
  from public.products
 where deleted_at is null
 group by 1
having count(*) > 1
 order by 1;

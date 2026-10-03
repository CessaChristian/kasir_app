-- =====================================================================
--  KATEGORI TERHAPUS — produk tidak boleh menunjuk kategori yang dihapus
--
--  Jalankan lewat SQL Editor di dashboard Supabase. Aman diulang.
--
--  ── MASALAHNYA ──
--
--  HP kasir yang offline masih melihat kategori yang sudah dihapus owner,
--  dan bisa memasukkan produk ke situ. Begitu online, server menyimpan
--  produk AKTIF yang menunjuk kategori TERHAPUS. HP yang dipasang dari nol
--  lalu tidak bisa menyimpan produk itu tanpa menyimpan kategori terhapusnya
--  juga — dan kategori yang tidak dipakai produk mana pun tidak pernah bisa
--  dibuang `buang_sampah`.
--
--  ── PERBAIKANNYA ──
--
--  Server sendiri yang menjaga: produk yang kategorinya terhapus disimpan
--  TANPA kategori. Dua arah urutan kejadian ditutup:
--
--    A. Kategori dihapus duluan, lalu produk yang memakainya sampai
--       -> trigger di `products` melepas kategorinya saat produk masuk.
--    B. Produk sudah ada, lalu kategorinya dihapus dari HP yang belum
--       menarik produk itu -> trigger di `categories` melepas semua
--       produknya.
--
--  `updated_at` produk dinaikkan MINIMAL 1 DETIK dari nilai sebelumnya:
--  aplikasi membandingkan versi per detik, jadi tanpa itu HP pengirim bisa
--  menganggap versinya sendiri sama baru dan tetap memegang kategori lama.
-- =====================================================================

-- ---------------------------------------------------------------------
--  A. Produk masuk/berubah -> kategorinya sudah terhapus?
-- ---------------------------------------------------------------------
create or replace function public.lepas_kategori_terhapus_produk()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.category_id is not null and exists (
    select 1 from public.categories c
     where c.id = new.category_id and c.deleted_at is not null
  ) then
    new.category_id := null;
    new.updated_at  := greatest(now(), new.updated_at) + interval '1 second';
  end if;
  return new;
end $$;

drop trigger if exists trg_products_lepas_kategori_terhapus on public.products;
create trigger trg_products_lepas_kategori_terhapus
  before insert or update on public.products
  for each row execute function public.lepas_kategori_terhapus_produk();

-- ---------------------------------------------------------------------
--  B. Kategori baru saja dihapus -> lepas semua produknya
-- ---------------------------------------------------------------------
create or replace function public.lepas_produk_kategori_terhapus()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.products
     set category_id = null,
         updated_at  = greatest(now(), updated_at) + interval '1 second'
   where category_id = new.id;
  return null;
end $$;

drop trigger if exists trg_categories_lepas_produk on public.categories;
create trigger trg_categories_lepas_produk
  after update of deleted_at on public.categories
  for each row
  when (old.deleted_at is null and new.deleted_at is not null)
  execute function public.lepas_produk_kategori_terhapus();

-- Fungsi trigger tidak untuk dipanggil langsung lewat API.
revoke all on function public.lepas_kategori_terhapus_produk() from public, anon, authenticated;
revoke all on function public.lepas_produk_kategori_terhapus() from public, anon, authenticated;

-- ---------------------------------------------------------------------
--  Pembersihan sekali jalan: produk yang SEKARANG menunjuk kategori
--  terhapus. Aman diulang — sesudah sekali jalan tidak ada lagi yang cocok.
-- ---------------------------------------------------------------------
update public.products p
   set category_id = null,
       updated_at  = greatest(now(), p.updated_at) + interval '1 second'
  from public.categories c
 where c.id = p.category_id
   and c.deleted_at is not null;

-- =====================================================================
--  PEMERIKSAAN
--
--  Dua trigger terpasang — hasil yang benar: 2 baris.
--
--       select tgname from pg_trigger
--       where tgname in ('trg_products_lepas_kategori_terhapus',
--                        'trg_categories_lepas_produk');
--
--  Tidak ada lagi produk yang menunjuk kategori terhapus — hasil: 0.
--
--       select count(*) from public.products p
--       join public.categories c on c.id = p.category_id
--       where c.deleted_at is not null;
-- =====================================================================

-- =====================================================================
--  ANGKA DAN JALUR FOTO YANG WAJAR (audit nomor 9 & 10, 4 Nov 2026)
--
--  Jalankan lewat SQL Editor di dashboard Supabase SESUDAH schema.sql.
--  Aman diulang.
--
--  ── MASALAH YANG DIPECAHKAN ──
--
--  Aplikasi sudah menolak angka aneh, tapi server belum. HP yang aplikasinya
--  diakali bisa mengirim transaksi Rp -500.000, dan laporan semua HP ikut
--  kacau. Begitu juga image_path: nilai `kasir_app.sqlite` menunjuk database,
--  bukan foto.
--
--  ── DATA LAMA DIPERIKSA DULU ──
--
--  Kalau ada data lama yang melanggar, berkas ini BERHENTI dengan pesan
--  berisi jumlahnya, dan tidak ada yang berubah. Data lama tidak diubah
--  otomatis, karena itu catatan uang: pemilik yang memutuskan.
-- =====================================================================

do $$
declare
  pola constant text := '^products/[A-Za-z0-9_-]{1,64}\.(webp|jpg|jpeg|png)$';
  n_produk bigint;
  n_foto bigint;
  n_transaksi bigint;
  n_item bigint;
  n_pengeluaran bigint;
begin
  select count(*) into n_produk from public.products where price < 0;
  select count(*) into n_foto from public.products
    where image_path is not null and image_path !~ pola;
  select count(*) into n_transaksi from public.transactions
    where total < 0 or cash_received < 0 or change < 0;
  select count(*) into n_item from public.transaction_items
    where qty <= 0 or price_at_sale < 0 or subtotal < 0;
  select count(*) into n_pengeluaran from public.expenses where amount <= 0;

  if n_produk + n_foto + n_transaksi + n_item + n_pengeluaran > 0 then
    raise exception
      'Ada data lama yang melanggar, tidak ada yang diubah: produk %, foto %, transaksi %, item %, pengeluaran %',
      n_produk, n_foto, n_transaksi, n_item, n_pengeluaran;
  end if;
end $$;

alter table public.products
  drop constraint if exists products_harga_wajar,
  drop constraint if exists products_jalur_foto_sah;
alter table public.products
  add constraint products_harga_wajar check (price >= 0),
  add constraint products_jalur_foto_sah check (
    image_path is null
    or image_path ~ '^products/[A-Za-z0-9_-]{1,64}\.(webp|jpg|jpeg|png)$'
  );

alter table public.transactions
  drop constraint if exists transactions_angka_wajar;
alter table public.transactions
  add constraint transactions_angka_wajar check (
    total >= 0 and cash_received >= 0 and change >= 0
  );

alter table public.transaction_items
  drop constraint if exists transaction_items_angka_wajar;
alter table public.transaction_items
  add constraint transaction_items_angka_wajar check (
    qty > 0 and price_at_sale >= 0 and subtotal >= 0
  );

alter table public.expenses
  drop constraint if exists expenses_nominal_wajar;
alter table public.expenses
  add constraint expenses_nominal_wajar check (amount > 0);

-- =====================================================================
--  OPEN BILL
--
--  Jalankan lewat SQL Editor di dashboard Supabase SEBELUM memasang APK
--  dengan basis data v38. Aman diulang.
--
--  ── MASALAH YANG DIPECAHKAN ──
--
--  Pesanan bisa disimpan dulu sebagai "open bill" lalu dibayar belakangan
--  (keputusan owner 2026-10-14, sesuai desain). Bill milik SATU shift: semua
--  HP yang memakai shift itu melihatnya, dan shift tidak bisa ditutup selama
--  masih ada yang terbuka. Karena itu bill ikut sinkron.
--
--    open_bills.items         isi pesanan (produk, jumlah, catatan varian).
--                             Nama & harga SENGAJA tidak disimpan: diambil
--                             dari produk terbaru saat bill dibuka.
--    open_bills.transaction_id  transaksi yang melunasinya. Terbuka =
--                             transaction_id dan deleted_at kosong.
--    transactions.bill_name   salinan nama bill di struk ("Pelanggan").
--
--  ── URUTANNYA ──
--
--  1. Jalankan berkas INI.
--  2. Baru pasang APK v38. APK itu mengirim kolom `bill_name` di setiap
--     transaksi; kalau kolomnya belum ada, kiriman transaksi DITOLAK.
-- =====================================================================

alter table public.transactions add column if not exists bill_name text;

create table if not exists public.open_bills (
  id             uuid primary key default gen_random_uuid(),
  name           text        not null check (length(name) between 1 and 40),
  shift_id       uuid        not null references public.shifts(id),
  user_id        uuid        not null references public.users(id),
  items          jsonb       not null default '[]'::jsonb,
  transaction_id uuid        references public.transactions(id),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  -- Bill yang DIHAPUS kasir (hapus lunak, supaya HP lain ikut tahu).
  deleted_at     timestamptz
);

create index if not exists idx_open_bills_updated on public.open_bills(updated_at);
create index if not exists idx_open_bills_shift
  on public.open_bills(shift_id)
  where transaction_id is null and deleted_at is null;

-- ---------------------------------------------------------------------
--  Akses — sama dengan tabel data lain (perangkat_tegakkan.sql, rls.sql):
--  baca/tambah/ubah hanya untuk perangkat terdaftar & aktif, tanpa DELETE.
-- ---------------------------------------------------------------------
alter table public.open_bills enable row level security;

drop policy if exists baca_open_bills   on public.open_bills;
drop policy if exists tambah_open_bills on public.open_bills;
drop policy if exists ubah_open_bills   on public.open_bills;

create policy baca_open_bills on public.open_bills
  for select to authenticated
  using (public.perangkat_aktif());

create policy tambah_open_bills on public.open_bills
  for insert to authenticated
  with check (public.perangkat_aktif());

create policy ubah_open_bills on public.open_bills
  for update to authenticated
  using (public.perangkat_aktif())
  with check (public.perangkat_aktif());

revoke delete on public.open_bills from anon, authenticated;

-- ---------------------------------------------------------------------
--  Urutan kedatangan untuk tarikan bertahap (sync_urutan.sql). Tabel baru,
--  jadi kolomnya langsung diberi default.
-- ---------------------------------------------------------------------
alter table public.open_bills
  add column if not exists server_urut timestamptz not null
  default clock_timestamp();

create index if not exists idx_open_bills_server_urut
  on public.open_bills (server_urut);

drop trigger if exists trg_open_bills_server_urut on public.open_bills;
create trigger trg_open_bills_server_urut
  before insert or update on public.open_bills
  for each row execute function public.stempel_server_urut();

-- =====================================================================
--  PEMERIKSAAN SESUDAH DIJALANKAN
--
--    select column_name from information_schema.columns
--     where table_schema = 'public' and table_name = 'transactions'
--       and column_name = 'bill_name';
--    -- harus 1 baris
--
--    select policyname, cmd from pg_policies where tablename = 'open_bills';
--    -- harus 3 baris: SELECT, INSERT, UPDATE (tanpa DELETE)
--
--    select tgname from pg_trigger where tgname = 'trg_open_bills_server_urut';
--    -- harus 1 baris
-- =====================================================================

-- =====================================================================
--  Teras Inn POS — skema PostgreSQL (Supabase)
--  Dipetakan dari SQLite/drift skema v15.
--
--  Perbedaan yang DISENGAJA terhadap skema lokal:
--
--  1. `id` bertipe uuid, bukan text. Data lama yang ber-ID gaya lawas
--     (prod_ti_air, TRX/18/07/26/081398) TIDAK ikut naik — sesuai
--     keputusan memulai dengan data bersih.
--
--  2. Waktu bertipe timestamptz, bukan integer epoch. Konversi ada di
--     lapisan sync aplikasi.
--
--  3. Uang bertipe bigint (rupiah, tanpa desimal). Jangan pakai float
--     untuk uang — pembulatannya tidak bisa dipercaya.
--
--  4. Kolom `sync_status` TIDAK ada di sini. Itu konsep sisi klien:
--     menandai baris lokal yang belum terkirim. Di server, setiap baris
--     menurut definisi sudah tersinkron.
--
--  5. TIDAK ada trigger yang menimpa `updated_at`. Nilainya ditentukan
--     klien, karena itu yang dipakai untuk memutuskan versi mana yang
--     menang saat dua perangkat mengubah baris yang sama.
-- =====================================================================

-- ---------------------------------------------------------------- users
create table public.users (
  id                    uuid primary key default gen_random_uuid(),
  username              text        not null unique,
  pin_hash              text        not null,
  salt                  text        not null,
  role                  text        not null check (role in ('owner','cashier')),
  is_active             boolean     not null default true,
  recovery_hash         text,
  recovery_salt         text,
  recovery_created_at   timestamptz,
  recovery_used_at      timestamptz,
  recovery_attempts     integer     not null default 0,
  recovery_locked_until timestamptz,
  login_attempts        integer     not null default 0,
  login_locked_until    timestamptz,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  deleted_at            timestamptz
);

-- ---------------------------------------------------------- permissions
create table public.permissions (
  code        text primary key,
  name        text not null,
  description text not null
);

create table public.user_permissions (
  user_id         uuid    not null references public.users(id) on delete cascade,
  permission_code text    not null references public.permissions(code) on delete cascade,
  enabled         boolean not null default false,
  primary key (user_id, permission_code)
);

-- ----------------------------------------------------------- categories
create table public.categories (
  id             uuid primary key default gen_random_uuid(),
  name           text        not null,
  icon_codepoint integer,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz
);

-- ------------------------------------------------------------- products
create table public.products (
  id               uuid primary key default gen_random_uuid(),
  name             text        not null,
  price            bigint      not null,
  barcode          text,
  category_id      uuid        references public.categories(id),
  has_spicy_option boolean     not null default false,
  -- Path RELATIF di Supabase Storage, mis. 'products/<uuid>.webp'.
  -- Jangan simpan URL penuh: domain project bisa berubah.
  image_path       text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz
);

-- --------------------------------------------------------------- shifts
create table public.shifts (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid        not null references public.users(id),
  start_at   timestamptz not null default now(),
  end_at     timestamptz,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- --------------------------------------------------------- transactions
create table public.transactions (
  id              uuid primary key default gen_random_uuid(),
  invoice_no      text        not null default '',
  total           bigint      not null,
  payment_method  text        not null check (payment_method in ('cash','qris')),
  cash_received   bigint,
  change          bigint,
  cashier_user_id uuid        references public.users(id),
  shift_id        uuid        references public.shifts(id),
  order_type      text        not null default 'dine_in'
                              check (order_type in ('dine_in','take_away','delivery')),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz
);

-- ---------------------------------------------------- transaction_items
create table public.transaction_items (
  id             uuid primary key default gen_random_uuid(),
  transaction_id uuid        not null references public.transactions(id) on delete cascade,
  product_id     uuid        not null references public.products(id),
  -- Nama dan harga SENGAJA disalin: struk lama harus tetap benar walau
  -- produknya kelak diganti nama atau naik harga.
  product_name   text        not null default '',
  qty            integer     not null,
  price_at_sale  bigint      not null,
  subtotal       bigint      not null,
  notes          text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz
);

-- ------------------------------------------------------------- expenses
create table public.expenses (
  id                 uuid primary key default gen_random_uuid(),
  shift_id           uuid        not null references public.shifts(id),
  user_id            uuid        not null references public.users(id),
  updated_by_user_id uuid        references public.users(id),
  description        text        not null,
  amount             bigint      not null,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  deleted_at         timestamptz
);

-- =====================================================================
--  INDEKS
--
--  Skema lokal belum punya indeks apa pun selain primary key. Pada 336
--  baris itu tidak terasa; di server yang menampung data bertahun-tahun,
--  laporan bulanan akan memindai seluruh tabel tanpa ini.
--
--  `updated_at` diindeks di semua tabel karena sync menariknya dengan
--  "beri saya baris yang berubah setelah waktu X" — itu query terpanas.
-- =====================================================================
create index idx_products_updated          on public.products(updated_at);
create index idx_products_category         on public.products(category_id) where deleted_at is null;
create index idx_categories_updated        on public.categories(updated_at);
create index idx_users_updated             on public.users(updated_at);
create index idx_shifts_updated            on public.shifts(updated_at);
create index idx_shifts_user_open          on public.shifts(user_id) where end_at is null;
create index idx_tx_updated                on public.transactions(updated_at);
create index idx_tx_created                on public.transactions(created_at) where deleted_at is null;
create index idx_tx_shift                  on public.transactions(shift_id);
create index idx_items_updated             on public.transaction_items(updated_at);
create index idx_items_transaction         on public.transaction_items(transaction_id);
create index idx_expenses_updated          on public.expenses(updated_at);
create index idx_expenses_shift            on public.expenses(shift_id);

-- =====================================================================
--  ROW LEVEL SECURITY
--
--  RLS WAJIB menyala di setiap tabel. Kunci `anon` tertanam di dalam APK
--  dan bisa dibaca siapa saja — RLS adalah satu-satunya yang berdiri di
--  antara data ini dan internet.
--
--  BERKAS INI TIDAK MEMBUAT SATU POLICY PUN. Ia hanya menyalakan RLS,
--  sehingga tabel yang baru dibuat menolak SEMUA akses sampai
--  `supabase/rls.sql` dijalankan.
--
--  Sengaja begitu. Sebelumnya di sini ada policy sementara `spike_*`
--  berbunyi `using (true) with check (true)` — siapa pun yang berhasil
--  login boleh melakukan apa saja. Kalau policy itu dibiarkan di berkas
--  skema, setiap pemasangan baru akan lahir dalam keadaan terbuka, dan
--  lupa menjalankan pengetatannya tidak menimbulkan gejala apa pun sampai
--  ada yang menyalahgunakannya.
--
--  Gagal-tertutup lebih baik: kalau rls.sql terlupa, aplikasinya langsung
--  tidak bisa membaca apa-apa dan kelalaian itu ketahuan dalam hitungan
--  detik, bukan bulan.
-- =====================================================================
alter table public.users             enable row level security;
alter table public.permissions       enable row level security;
alter table public.user_permissions  enable row level security;
alter table public.categories        enable row level security;
alter table public.products          enable row level security;
alter table public.shifts            enable row level security;
alter table public.transactions      enable row level security;
alter table public.transaction_items enable row level security;
alter table public.expenses          enable row level security;

-- LANGKAH BERIKUTNYA YANG WAJIB: jalankan `supabase/rls.sql`.
-- Tanpa itu, RLS menyala tanpa satu pun policy dan seluruh tabel menolak
-- akses — termasuk dari aplikasi yang sah.

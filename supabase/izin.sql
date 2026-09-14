-- =====================================================================
--  IZIN — katalog dan sinkronisasi
--
--  Jalankan SEKALI lewat SQL Editor di dashboard Supabase.
--  Aman dijalankan ulang.
--
--  ── MASALAH YANG DIPERBAIKI ──
--
--  Tabel `user_permissions` mencatat kasir mana boleh apa. Ia lahir sebelum
--  aturan sinkronisasi ada, jadi memakai kunci gabungan dan tidak punya
--  `updated_at` maupun `sync_status` — akibatnya TIDAK PERNAH ikut
--  disinkronkan.
--
--  Izin kasir karena itu hanya hidup di HP tempat pemilik mengaturnya. HP
--  kasir yang dipasang ulang kehilangan seluruh izinnya: menu Kasir pun tidak
--  muncul dan kasirnya tidak bisa berjualan sama sekali. Terlihat langsung
--  saat menguji pemasangan baru.
-- =====================================================================

-- ---------------------------------------------------------------------
--  1. Katalog izin
--
--  `user_permissions.permission_code` merujuk tabel ini lewat foreign key,
--  dan tabel ini KOSONG di server. Tanpa disemai, setiap baris izin yang
--  dikirim HP akan ditolak — foreign key-nya tidak ketemu.
--
--  ⚠ Daftar ini HARUS sama dengan `_seedPermissions` di app_database.dart.
--    Menambah kode izin baru di aplikasi tanpa menambahkannya di sini akan
--    membuat baris izin yang memakainya ditolak server, dan sinkronisasi
--    tabel itu gagal tanpa sebab yang terlihat di layar.
-- ---------------------------------------------------------------------
insert into public.permissions (code, name, description) values
  ('open_close_shift', 'Open/Close Shift', 'Ability to start and end work shifts'),
  ('create_transaction', 'Create Transaction', 'Ability to process sales transactions'),
  ('view_history', 'View Transaction History', 'Ability to view past transactions'),
  ('view_report', 'View Reports', 'Ability to view sales reports and analytics'),
  ('manage_products', 'Manage Products', 'Ability to add, edit, and delete products'),
  ('manage_cashiers', 'Manage Cashiers', 'Ability to add, edit, and manage cashier accounts'),
  ('edit_own_expense', 'Edit Own Expense', 'Ability to edit expenses created by self'),
  ('edit_any_expense', 'Edit Any Expense', 'Ability to edit any expense (owner override)'),
  ('delete_own_transaction', 'Delete Own Transaction', 'Ability to soft-delete transactions created by self'),
  ('delete_any_transaction', 'Delete Any Transaction', 'Ability to soft-delete any transaction (owner override)'),
  ('view_shift_reports', 'View Shift Reports', 'Ability to view shift reports page'),
  ('view_all_shifts', 'View All Shifts', 'Ability to view shift data from all users')
on conflict (code) do update
  set name = excluded.name,
      description = excluded.description;

-- ---------------------------------------------------------------------
--  2. Kolom sinkronisasi pada user_permissions
--
--  Kunci primernya berubah dari gabungan (user_id, permission_code) menjadi
--  `id` tunggal, supaya cocok dengan mesin sinkronisasi yang sudah ada tanpa
--  perlu mengubah mesinnya. Pasangannya tetap dijaga UNIK.
--
--  `id` di sisi aplikasi bersifat TURUNAN dari pasangan itu, bukan acak:
--  setiap HP menjalankan migrasinya sendiri, dan id acak akan menghasilkan
--  dua baris berbeda untuk pasangan yang sama — yang kedua lalu ditolak
--  batasan unik dan tertahan selamanya.
-- ---------------------------------------------------------------------
alter table public.user_permissions
  add column if not exists id         uuid,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists deleted_at timestamptz;

-- Baris lama (kalau ada) diberi id sebelum kolomnya dijadikan kunci.
update public.user_permissions set id = gen_random_uuid() where id is null;
alter table public.user_permissions alter column id set not null;

do $$
begin
  if exists (
    select 1 from pg_constraint
    where conname = 'user_permissions_pkey'
      and conrelid = 'public.user_permissions'::regclass
  ) then
    alter table public.user_permissions drop constraint user_permissions_pkey;
  end if;
end $$;

alter table public.user_permissions add primary key (id);

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'user_permissions_pasangan_unik'
  ) then
    alter table public.user_permissions
      add constraint user_permissions_pasangan_unik
      unique (user_id, permission_code);
  end if;
end $$;

create index if not exists idx_user_permissions_updated
  on public.user_permissions(updated_at);

-- ---------------------------------------------------------------------
--  3. Akses
--
--  Sebelumnya tabel ini hanya boleh dibaca, karena memang tidak ada yang
--  menulisnya dari perangkat. Sekarang ia ikut disinkronkan.
--  Catatan: policy ini baru berlaku setelah `supabase/rls.sql` dijalankan.
-- ---------------------------------------------------------------------
drop policy if exists tambah_user_permissions on public.user_permissions;
drop policy if exists ubah_user_permissions   on public.user_permissions;

create policy tambah_user_permissions on public.user_permissions
  for insert to authenticated with check (true);

create policy ubah_user_permissions on public.user_permissions
  for update to authenticated using (true) with check (true);

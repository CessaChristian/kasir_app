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
-- Empat kode lama sengaja DIBUANG di v21, bukan sekadar tidak disemai:
-- edit_own_expense, edit_any_expense, delete_own_transaction,
-- delete_any_transaction. Keempatnya bisa disetel ke kombinasi yang tidak
-- masuk akal — kasir yang diberi delete_any_* bisa menghapus transaksi kasir
-- LAIN. Aturannya kini tetap: owner boleh mengubah catatan siapa pun, selain
-- owner hanya catatannya sendiri.
--
-- Dua kode lagi dibuang di v27, dengan alasan berbeda:
-- - manage_cashiers: Kelola Kasir kini hak PATEN owner, tidak bisa
--   diberikan ke kasir — sama seperti Daftar Perangkat.
-- - view_shift_reports: melihat shift SENDIRI kini hak paten SEMUA akun.
--   Yang tetap jadi izin hanya view_all_shifts (melihat kasir lain).
--
-- Baris user_permissions dibuang LEBIH DULU: HP yang sudah memakai v27 tidak
-- lagi mengenal kode-kode ini, dan akan menolak baris yang memakainya —
-- sinkron tabel izin gagal terus. Jalankan ini SEBELUM APK v27 dipasang.
delete from public.user_permissions
 where permission_code in ('edit_own_expense','edit_any_expense',
                           'delete_own_transaction','delete_any_transaction',
                           'manage_cashiers','view_shift_reports');
delete from public.permissions
 where code in ('edit_own_expense','edit_any_expense',
                'delete_own_transaction','delete_any_transaction',
                'manage_cashiers','view_shift_reports');

insert into public.permissions (code, name, description) values
  ('open_close_shift', 'Buka & Tutup Shift', 'Memulai dan mengakhiri jam kerja'),
  ('create_transaction', 'Buat Transaksi', 'Melayani penjualan di halaman Kasir'),
  ('view_history', 'Lihat Riwayat Lengkap', 'Melihat transaksi dan pengeluaran sendiri dari shift-shift sebelumnya. Tanpa izin ini hanya shift yang sedang berjalan'),
  ('view_report', 'Lihat Laporan', 'Membuka analisis penjualan'),
  ('manage_products', 'Kelola Produk', 'Menambah, mengubah, dan menghapus produk'),
  ('view_all_shifts', 'Lihat Shift Semua Kasir', 'Melihat shift kasir lain, bukan hanya miliknya sendiri')
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
--  3. Akses — SENGAJA TIDAK DIATUR DI SINI
--
--  Berkas ini dulu membuat sendiri policy tulis untuk `user_permissions`,
--  berbunyi `with check (true)` / `using (true)`. Policy itu sekarang milik
--  `supabase/perangkat_tegakkan.sql`, yang memasang versi jauh lebih ketat:
--  `public.perangkat_aktif()` — hanya perangkat yang terdaftar dan aktif.
--
--  Kenapa dicabut dari sini: berkas ini WAJAR dijalankan ulang, misalnya saat
--  menambah izin baru ke katalog. Kalau ia masih ikut membuat policy, sekali
--  dijalankan ulang ia akan menimpa versi ketat itu dengan versi longgar —
--  tanpa galat, tanpa gejala, dan perangkat yang sudah dicabut bisa mengubah
--  izin lagi. Kerusakan diam-diam seperti itu paling mahal dicari.
--
--  Satu policy, satu pemilik. Yang di sini cuma menyemai data.
--  Urutan pemasangan: schema.sql → izin.sql → perangkat.sql → perangkat_tegakkan.sql
-- ---------------------------------------------------------------------

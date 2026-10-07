-- =====================================================================
--  SALINAN NAMA AKUN DI SHIFT, TRANSAKSI, DAN PENGELUARAN
--  (+ users.deleted_at untuk Hapus Akun)
--
--  Jalankan lewat SQL Editor di dashboard Supabase SEBELUM memasang APK
--  dengan basis data v35. Aman diulang.
--
--  ── MASALAH YANG DIPECAHKAN ──
--
--  Shift, transaksi, dan pengeluaran hanya menyimpan ID akun; namanya dicari
--  dari tabel `users` saat ditampilkan. Owner memutuskan (2026-10-07) akun
--  kasir boleh DIHAPUS dan username bekasnya boleh DIPAKAI ULANG. Kalau nama
--  tetap dicari dari `users`, riwayat lama ikut berubah nama — atau malah
--  tertulis atas nama karyawan baru yang memakai username yang sama.
--
--  Maka setiap catatan ikut menyimpan SALINAN nama saat dibuat. ID akun
--  TETAP ada dan tetap dipakai semua logika (siapa boleh membatalkan,
--  cakupan riwayat, melanjutkan shift). Salinan nama hanya untuk ditampilkan.
--
--  ── KENAPA updated_at TIDAK DIGESER ──
--
--  HP dengan APK v35 mengisi salinan nama data lamanya sendiri dari tabel
--  akun di HP — hasilnya sama persis dengan isian di sini. Tidak ada yang
--  perlu ditarik ulang.
--
--  Catatan: trigger `server_urut` tetap menyala dan memberi cap baru pada
--  baris yang diisi, jadi tiap HP akan MENARIK ULANG baris-baris ini sekali.
--  Isinya sama, HP mengabaikannya. Itu lebih aman daripada mematikan trigger
--  sementara: kiriman yang datang selama trigger mati bisa terlewat HP lain.
--
--  ── users.deleted_at ──
--
--  Dipasang sekarang (untuk Hapus Akun di tahap berikutnya) supaya SQL cukup
--  dijalankan sekali. Kosong = akun belum dihapus. Akun tidak pernah dibuang
--  dari tabel: riwayat masih menunjuknya lewat ID.
-- =====================================================================

-- ---------------------------------------------------------------------
--  1. Kolomnya (semua boleh kosong: HP yang belum diperbarui tetap bisa
--     mengirim tanpa mengisinya)
-- ---------------------------------------------------------------------
alter table public.shifts       add column if not exists user_name         text;
alter table public.transactions add column if not exists cashier_name      text;
alter table public.transactions add column if not exists cancelled_by_name text;
alter table public.expenses     add column if not exists user_name         text;
alter table public.expenses     add column if not exists cancelled_by_name text;
alter table public.users        add column if not exists deleted_at        timestamptz;

-- ---------------------------------------------------------------------
--  2. Data lama diisi sekali dengan nama akun saat ini
-- ---------------------------------------------------------------------
update public.shifts s
   set user_name = u.username
  from public.users u
 where u.id = s.user_id and s.user_name is null;

update public.transactions t
   set cashier_name = u.username
  from public.users u
 where u.id = t.cashier_user_id and t.cashier_name is null;

update public.transactions t
   set cancelled_by_name = u.username
  from public.users u
 where u.id = t.cancelled_by_user_id and t.cancelled_by_name is null;

update public.expenses e
   set user_name = u.username
  from public.users u
 where u.id = e.user_id and e.user_name is null;

update public.expenses e
   set cancelled_by_name = u.username
  from public.users u
 where u.id = e.cancelled_by_user_id and e.cancelled_by_name is null;

-- =====================================================================
--  PEMERIKSAAN — hasil yang benar: semua 0.
--
--    select
--      (select count(*) from public.shifts       where user_name is null)    as shift_tanpa_nama,
--      (select count(*) from public.transactions where cashier_user_id is not null
--                                                  and cashier_name is null) as trx_tanpa_nama,
--      (select count(*) from public.transactions where cancelled_by_user_id is not null
--                                                  and cancelled_by_name is null) as batal_tanpa_nama,
--      (select count(*) from public.expenses     where user_name is null)    as pengeluaran_tanpa_nama;
--
--  Dan kolom akun dihapus ada — hasil yang benar: 1 baris.
--
--    select column_name from information_schema.columns
--    where table_schema = 'public' and table_name = 'users'
--      and column_name = 'deleted_at';
-- =====================================================================

-- =====================================================================
--  KUNCI KOLOM  —  angka yang sudah tercatat tidak bisa diganti lewat
--                  kiriman HP
--
--  Jalankan lewat SQL Editor di dashboard Supabase. Aman diulang.
--  Tidak butuh APK baru.
--
--  ── MASALAHNYA ──
--
--  Server menerima perubahan apa pun dari HP yang terdaftar. Aplikasi
--  memang tidak pernah mengubah total transaksi, nominal pengeluaran, atau
--  kas awal shift — tombolnya tidak ada — tapi HP yang dibongkar bisa
--  mengirim perubahan langsung ke server tanpa lewat tombol:
--
--    Es Kopi Rp25.000 terjual  →  totalnya diubah jadi Rp5.000 di server
--    →  laporan owner ikut Rp5.000, selisihnya masuk kantong.
--
--  ── PERBAIKANNYA ──
--
--  Kolom-kolom di bawah hanya boleh terisi SEKALI. Kiriman yang mencoba
--  menggantinya tidak ditolak dengan galat — kalau ditolak, baris di HP itu
--  macet "belum terkirim" selamanya — melainkan nilai aslinya yang
--  disimpan. `updated_at` dimajukan melewati nilai lama dan kiriman supaya
--  HP pengirim menarik angka yang benar (pola yang sama dengan
--  supabase/open_bill_kunci.sql).
--
--  Daftar kolomnya dicocokkan dengan kode aplikasi: tidak satu pun ditulis
--  ulang setelah barisnya dibuat. Yang tetap boleh berubah: kolom
--  pembatalan (deleted_at, siapa, alasan), salinan nama, tipe pesanan, dan
--  kategori pengeluaran (pernah diisi ulang oleh migrasi).
--
--  Nama trigger `trg_<tabel>_kunci_kolom` berjalan SESUDAH
--  `trg_<tabel>_jaga_versi` dan SEBELUM `trg_<tabel>_server_urut` (trigger
--  BEFORE berurutan abjad).
-- =====================================================================

create or replace function public.kunci_kolom()
returns trigger
language plpgsql
as $$
declare
  dikoreksi boolean := false;
begin
  if tg_table_name = 'transactions' then
    if (new.total, new.cash_received, new.change, new.payment_method,
        new.invoice_no, new.created_at, new.shift_id, new.cashier_user_id)
       is distinct from
       (old.total, old.cash_received, old.change, old.payment_method,
        old.invoice_no, old.created_at, old.shift_id, old.cashier_user_id)
    then
      new.total := old.total;
      new.cash_received := old.cash_received;
      new.change := old.change;
      new.payment_method := old.payment_method;
      new.invoice_no := old.invoice_no;
      new.created_at := old.created_at;
      new.shift_id := old.shift_id;
      new.cashier_user_id := old.cashier_user_id;
      dikoreksi := true;
    end if;

  elsif tg_table_name = 'transaction_items' then
    if (new.qty, new.price_at_sale, new.subtotal, new.transaction_id)
       is distinct from
       (old.qty, old.price_at_sale, old.subtotal, old.transaction_id)
    then
      new.qty := old.qty;
      new.price_at_sale := old.price_at_sale;
      new.subtotal := old.subtotal;
      new.transaction_id := old.transaction_id;
      dikoreksi := true;
    end if;

  elsif tg_table_name = 'expenses' then
    if (new.amount, new.qty, new.shift_id, new.user_id, new.created_at)
       is distinct from
       (old.amount, old.qty, old.shift_id, old.user_id, old.created_at)
    then
      new.amount := old.amount;
      new.qty := old.qty;
      new.shift_id := old.shift_id;
      new.user_id := old.user_id;
      new.created_at := old.created_at;
      dikoreksi := true;
    end if;

  elsif tg_table_name = 'shifts' then
    if (new.start_at, new.user_id) is distinct from (old.start_at, old.user_id)
    then
      new.start_at := old.start_at;
      new.user_id := old.user_id;
      dikoreksi := true;
    end if;
    -- Kas awal: shift lama yang belum punya kas awal tidak dikunci.
    if old.kas_awal is not null and new.kas_awal is distinct from old.kas_awal
    then
      new.kas_awal := old.kas_awal;
      dikoreksi := true;
    end if;
    -- Shift yang sudah ditutup tidak bisa dibuka lagi atau dipindah jam
    -- tutupnya.
    if old.end_at is not null and new.end_at is distinct from old.end_at then
      new.end_at := old.end_at;
      dikoreksi := true;
    end if;

  elsif tg_table_name = 'users' then
    if new.role is distinct from old.role then
      new.role := old.role;
      dikoreksi := true;
    end if;
  end if;

  if dikoreksi then
    new.updated_at :=
      greatest(new.updated_at, old.updated_at, now()) + interval '1 second';
  end if;
  return new;
end $$;

-- ---------------------------------------------------------------------
--  Owner kedua ditolak.
--
--  Akun owner dibuat sekali saat toko pertama kali disiapkan. Akun baru
--  dengan role owner sesudahnya hanya bisa berarti kasir yang mencoba
--  mengangkat dirinya sendiri. Owner yang mengirim ulang barisnya sendiri
--  (id sama) tidak terkena.
-- ---------------------------------------------------------------------
create or replace function public.tolak_owner_kedua()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.role = 'owner' and exists (
    select 1 from public.users where role = 'owner' and id <> new.id
  ) then
    raise exception 'akun owner sudah ada' using errcode = '42501';
  end if;
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array[
    'transactions','transaction_items','expenses','shifts','users'
  ] loop
    execute format('drop trigger if exists %I on public.%I',
                   'trg_'||t||'_kunci_kolom', t);
    execute format(
      'create trigger %I before update on public.%I '
      'for each row execute function public.kunci_kolom()',
      'trg_'||t||'_kunci_kolom', t);
  end loop;
end $$;

drop trigger if exists trg_users_owner_kedua on public.users;
create trigger trg_users_owner_kedua
  before insert on public.users
  for each row execute function public.tolak_owner_kedua();

-- Fungsi trigger tidak untuk dipanggil langsung lewat API.
revoke all on function public.kunci_kolom() from public, anon, authenticated;
revoke all on function public.tolak_owner_kedua()
  from public, anon, authenticated;

-- =====================================================================
--  PEMERIKSAAN SESUDAH DIJALANKAN
--
--    select tgrelid::regclass as tabel, tgname
--      from pg_trigger
--     where tgname like 'trg_%_kunci_kolom' or tgname = 'trg_users_owner_kedua'
--     order by 1, 2;
--
--  Hasil yang benar: 6 baris.
-- =====================================================================

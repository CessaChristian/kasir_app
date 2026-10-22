-- =====================================================================
--  TOLAK VERSI LAMA  —  server menyimpan versi TERBARU, bukan yang tiba
--                      terakhir
--
--  Jalankan lewat SQL Editor di dashboard Supabase. Aman diulang.
--  Tidak perlu APK baru: aplikasi yang sekarang sudah cocok.
--
--  ── MASALAHNYA ──
--
--  HP mengirim baris dengan `upsert` polos, jadi server selalu menyimpan
--  kiriman yang DATANG TERAKHIR. Sementara itu setiap HP memilih versi yang
--  `updated_at`-nya PALING BARU. Kalau versi lama datang belakangan, server
--  dan HP-HP berbeda pendapat — selamanya:
--
--    10.00  HP A (offline) mengubah harga Latte jadi 20.000
--    10.05  HP owner mengubahnya jadi 22.000, langsung terkirim
--    10.10  HP A online, kirimannya (cap 10.00) menimpa server
--           -> server & HP A: 20.000, HP owner: 22.000 (versi server lebih
--              tua dari miliknya, jadi diabaikan), HP baru: 20.000
--
--  Jam HP yang terlalu maju (mis. tahun 2030) membuat kirimannya menang
--  atas semua perubahan HP lain, juga selamanya.
--
--  ── PERBAIKANNYA ──
--
--  Satu penjaga di setiap tabel yang disinkron:
--
--    1. Kiriman yang LEBIH TUA dari baris di server -> baris server
--       dipertahankan. Tidak ada galat: kalau ditolak, barisnya di HP
--       pengirim macet "belum terkirim" selamanya. `server_urut` tetap
--       dicap, jadi HP pengirim menarik versi yang menang di putaran
--       berikutnya.
--    2. `updated_at` lebih dari 5 menit di depan jam server -> dipotong ke
--       jam server.
--    3. Transaksi & pengeluaran: PEMBATALAN selalu diterima, walau jam HP
--       yang membatalkan terlambat — dan cap waktunya dimajukan melewati
--       versi lama supaya semua HP menerimanya. Yang sudah dibatalkan tidak
--       bisa "dihidupkan" lagi oleh kiriman versi lama.
--
--  Nama trigger `trg_<tabel>_jaga_versi` berjalan SEBELUM
--  `trg_<tabel>_server_urut` (trigger BEFORE berurutan abjad), jadi baris
--  yang dipertahankan pun tetap dicap waktu kedatangannya.
-- =====================================================================

create or replace function public.jaga_versi_terbaru()
returns trigger
language plpgsql
as $$
begin
  -- 2. Jam HP yang terlalu maju.
  if new.updated_at > now() + interval '5 minutes' then
    new.updated_at := now();
  end if;

  if tg_op <> 'UPDATE' then
    return new;
  end if;

  -- 3. Pembatalan bersifat satu arah dan selalu menang.
  if tg_table_name in ('transactions', 'expenses') then
    if old.deleted_at is not null and new.deleted_at is null then
      return old;
    end if;
    if old.deleted_at is null and new.deleted_at is not null then
      new.updated_at :=
        greatest(new.updated_at, old.updated_at + interval '1 second');
      return new;
    end if;
  end if;

  -- 1. Versi yang lebih tua tidak menimpa yang lebih baru.
  if new.updated_at < old.updated_at then
    return old;
  end if;
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array[
    'users','user_permissions','categories','products','shifts',
    'transactions','transaction_items','expenses','open_bills'
  ] loop
    execute format('drop trigger if exists %I on public.%I',
                   'trg_'||t||'_jaga_versi', t);
    execute format(
      'create trigger %I before insert or update on public.%I '
      'for each row execute function public.jaga_versi_terbaru()',
      'trg_'||t||'_jaga_versi', t);
  end loop;
end $$;

-- Fungsi trigger tidak untuk dipanggil langsung lewat API.
revoke all on function public.jaga_versi_terbaru()
  from public, anon, authenticated;

-- =====================================================================
--  PEMERIKSAAN SESUDAH DIJALANKAN
--
--    select tgrelid::regclass as tabel, tgname
--      from pg_trigger
--     where tgname like 'trg_%_jaga_versi'
--     order by 1;
--
--  Hasil yang benar: 9 baris (users, user_permissions, categories,
--  products, shifts, transactions, transaction_items, expenses,
--  open_bills).
-- =====================================================================

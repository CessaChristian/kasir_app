-- =====================================================================
--  URUTAN KEDATANGAN DI SERVER  —  menutup kebocoran data saat sinkron
--
--  Jalankan SEKALI lewat SQL Editor di dashboard Supabase.
--  Aman dijalankan ulang: semuanya `if not exists` / `or replace`.
--
--  ── MASALAH YANG DIPECAHKAN ──
--
--  Perangkat menarik data dengan bertanya: "beri aku baris yang `updated_at`
--  -nya lebih baru dari penandaku." Penandanya lalu dimajukan ke `updated_at`
--  tertinggi yang diterima.
--
--  Yang bocor: `updated_at` berasal dari JAM PERANGKAT, diisi saat barisnya
--  DIUBAH — bukan saat barisnya sampai di server. Baris bisa tiba di server
--  jauh sesudah cap waktunya, dan begitu penanda sudah melewatinya, baris itu
--  TIDAK AKAN PERNAH ditarik lagi.
--
--    09:00  HP kasir kehilangan internet, tetap melayani
--    09:00–12:00  60 transaksi tercatat, cap waktunya 09:00–12:00
--    11:30  HP owner menerima baris bercap 11:30 → penandanya maju ke 11:30
--    12:05  HP kasir online, mendorong 60 transaksinya (cap tetap 09:00–12:00)
--    12:06  HP owner menarik "yang > 11:30"  →  60 transaksi itu TIDAK IKUT
--
--  Gagalnya diam-diam: sinkronnya melapor berhasil, tidak ada galat, dan
--  datanya aman di server — cuma tidak pernah sampai ke HP owner.
--
--  Jam perangkat yang meleset menghasilkan kebocoran yang sama tanpa perlu
--  offline sama sekali.
--
--  ── KENAPA BUKAN "BIAR SERVER YANG MENGISI updated_at" ──
--
--  Itu jalan yang kelihatannya jelas, dan merusak hal lain. `updated_at`
--  dipakai untuk DUA tugas: menentukan siapa menang saat dua perangkat
--  mengubah baris yang sama, DAN menentukan sampai mana kita sudah menarik.
--  Kalau server yang mengisinya, tugas kedua jadi benar tapi yang pertama
--  rusak — perubahan lokal yang belum terkirim bisa tertimpa versi server
--  yang lebih tua isinya tapi lebih baru capnya.
--
--  Maka tugasnya DIPISAH:
--
--    updated_at   (jam perangkat)  → tetap. urusannya hanya siapa menang.
--    server_urut  (jam server)     → BARU. urusannya hanya sampai mana kita
--                                     sudah menarik.
-- =====================================================================

-- ---------------------------------------------------------------------
--  1. Stempel waktu kedatangan
--
--  `clock_timestamp()` dipakai, BUKAN `now()`. `now()` membeku di awal
--  transaksi, jadi seratus baris dalam satu pengiriman akan bercap sama
--  persis. Yang ini maju terus di dalam transaksi, sehingga urutannya lebih
--  halus. Cap kembar tetap tidak masalah — lihat catatan jeda aman di
--  `sync_engine.dart`.
--
--  Trigger-nya MENIMPA apa pun yang dikirim perangkat. Kolom ini menyatakan
--  "kapan server menerimanya", jadi perangkat tidak boleh punya suara di
--  sini — termasuk perangkat yang jamnya meleset atau yang berniat curang.
-- ---------------------------------------------------------------------
create or replace function public.stempel_server_urut()
returns trigger
language plpgsql
as $$
begin
  new.server_urut := clock_timestamp();
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array[
    'users','user_permissions','categories','products','shifts',
    'transactions','transaction_items','expenses'
  ] loop
    -- Kolomnya. Baris yang sudah ada ikut terisi saat kolomnya dibuat.
    execute format(
      'alter table public.%I add column if not exists server_urut '
      'timestamptz not null default clock_timestamp()', t);

    -- Indeks: setiap tarikan menyaring dan mengurutkan berdasarkan kolom ini.
    -- Tanpa indeks, tiap sinkron memindai seluruh tabel.
    execute format(
      'create index if not exists %I on public.%I (server_urut)',
      'idx_'||t||'_server_urut', t);

    execute format('drop trigger if exists %I on public.%I',
                   'trg_'||t||'_server_urut', t);
    execute format(
      'create trigger %I before insert or update on public.%I '
      'for each row execute function public.stempel_server_urut()',
      'trg_'||t||'_server_urut', t);
  end loop;
end $$;

-- =====================================================================
--  SESUDAH DIJALANKAN
--
--  Aplikasi akan MENARIK ULANG SEMUANYA sekali di tiap perangkat. Itu
--  disengaja: penanda lama berisi `updated_at`, yang tidak sebanding dengan
--  kolom baru. Penandanya dikosongkan oleh migrasi v22 di aplikasi, jadi
--  tarikan pertama sesudah pembaruan akan lebih lama dari biasanya.
--
--  Tidak ada data yang hilang saat itu: menggabungkan bersifat idempoten —
--  baris yang isinya sudah sama dilewati, dan yang lokalnya lebih baru
--  menang seperti biasa.
--
--  PEMERIKSAAN:
--
--    select table_name, column_name
--    from information_schema.columns
--    where table_schema = 'public' and column_name = 'server_urut'
--    order by table_name;
--
--  Hasil yang benar: 8 baris.
--
--    select tgname, tgrelid::regclass
--    from pg_trigger where tgname like 'trg_%_server_urut'
--    order by 2;
--
--  Hasil yang benar: 8 baris.
-- =====================================================================

-- =====================================================================
--  PERBAIKAN SEKALI JALAN untuk `supabase/sync_urutan.sql`
--
--  Jalankan SEKALI lewat SQL Editor, sesudah `sync_urutan.sql`.
--  JANGAN dijalankan berulang di kemudian hari — alasannya di bagian bawah.
--
--  ── APA YANG KELIRU ──
--
--  `sync_urutan.sql` menambahkan kolomnya dengan `default clock_timestamp()`.
--  Saat kolom itu dibuat, PostgreSQL mengisi SELURUH baris lama dengan nilai
--  dari saat itu juga — seribu baris bertahun-tahun lalu semuanya bercap
--  "detik ini", berselisih hanya mikrodetik.
--
--  Akibatnya penanda tarikan tiap perangkat mendarat di gumpalan itu. Aplikasi
--  menarik dengan jeda aman satu menit ke belakang, dan satu menit ke belakang
--  dari gumpalan itu mencakup SELURUH isinya. Jadi setiap sinkron menarik
--  ulang seluruh tabel — selamanya, sampai ada baris baru yang cukup jauh
--  memajukan penandanya.
--
--  Gejalanya persis yang terlihat: tarik-segarkan selalu melaporkan angka yang
--  sama ("856 data diperbarui") walaupun tidak ada yang berubah sama sekali.
--
--  Dan itu bukan sekadar berisik. Sekitar 1 MB tiap sinkron, tiap lima menit,
--  dua perangkat — sekitar 8 GB sebulan, sedangkan kuota gratisnya 5 GB.
--
--  ── PERBAIKANNYA ──
--
--  Baris lama diberi cap `updated_at`-nya sendiri. Itu perkiraan terbaik yang
--  tersedia untuk "kapan barisnya sampai", dan yang penting: capnya tersebar
--  wajar sepanjang waktu, bukan menggumpal di satu titik. Penanda tiap
--  perangkat lalu mendarat di baris terbaru, dan jeda satu menit hanya
--  mencakup semenit data sungguhan — beberapa baris, bukan seribu.
--
--  `least(..., now())` menjaga dari jam perangkat yang KEDEPAN. Cap di masa
--  depan akan melempar penanda melewati kedatangan sungguhan berikutnya, dan
--  itu justru kebocoran yang sedang kita tutup.
-- =====================================================================

-- ---------------------------------------------------------------------
--  1. Trigger dimatikan dulu
--
--  Trigger-nya menimpa `server_urut` pada SETIAP update. Tanpa mematikannya,
--  perintah pengisian di bawah akan langsung ditimpa balik dengan "detik ini"
--  — persis keadaan yang mau diperbaiki.
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'users','user_permissions','categories','products','shifts',
    'transactions','transaction_items','expenses'
  ] loop
    execute format('drop trigger if exists %I on public.%I',
                   'trg_'||t||'_server_urut', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
--  2. Baris lama diberi cap waktunya sendiri
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'users','user_permissions','categories','products','shifts',
    'transactions','transaction_items','expenses'
  ] loop
    execute format(
      'update public.%I set server_urut = least(updated_at, now()) '
      'where updated_at is not null', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
--  3. Trigger dipasang kembali
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'users','user_permissions','categories','products','shifts',
    'transactions','transaction_items','expenses'
  ] loop
    execute format(
      'create trigger %I before insert or update on public.%I '
      'for each row execute function public.stempel_server_urut()',
      'trg_'||t||'_server_urut', t);
  end loop;
end $$;

-- =====================================================================
--  KENAPA JANGAN DIJALANKAN ULANG
--
--  Langkah 2 MENIMPA `server_urut` dengan `updated_at` untuk semua baris,
--  termasuk baris yang sudah tiba dengan benar sesudah perbaikan ini. Cap
--  kedatangannya akan mundur ke waktu pembuatannya, dan perangkat yang
--  penandanya sudah melewati titik itu tidak akan menariknya lagi.
--
--  Itu aman HARI INI hanya karena aplikasi versi v23 mengosongkan penanda
--  tiap perangkat sekali, sehingga semuanya menarik ulang dari nol.
--
--  Kalau suatu hari perlu dijalankan lagi, penanda tiap perangkat harus ikut
--  dikosongkan — beri tahu dulu, jangan jalankan sendiri.
--
--  PEMERIKSAAN — cap waktunya harus TERSEBAR, bukan menggumpal:
--
--    select min(server_urut), max(server_urut),
--           count(distinct date_trunc('day', server_urut)) as jumlah_hari
--    from public.transactions;
--
--  Benar   : min jauh di masa lalu, jumlah_hari lebih dari satu
--  Keliru  : min dan max berselisih mikrodetik, jumlah_hari = 1
-- =====================================================================

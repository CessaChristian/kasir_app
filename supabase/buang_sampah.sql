-- =====================================================================
--  BUANG SAMPAH — hapus permanen data yang sudah dihapus dari aplikasi
--
--  Jalankan lewat SQL Editor di dashboard Supabase. Aman diulang.
--
--  ── APA ITU "DATA SAMPAH" ──
--
--  Menghapus di aplikasi tidak benar-benar membuang barisnya: kolom
--  `deleted_at` diisi, barisnya tetap ada. Itu disengaja — baris itulah yang
--  mengabarkan ke HP lain bahwa sesuatu sudah dihapus. Tanpa kabar itu, HP
--  yang belum sinkron tetap memegang datanya, dan begitu ia mengubahnya,
--  datanya HIDUP LAGI di server.
--
--  Tapi sesudah semua HP menerima kabarnya, baris itu cuma sampah: aplikasi
--  tidak punya fitur pulihkan, dan tidak ada yang membacanya lagi.
--
--  ── KAPAN BOLEH DIBUANG: "CENTANG BIRU SEMUA" ──
--
--  Seperti pesan WhatsApp — baru boleh dihapus kalau semua sudah membaca.
--
--    server_urut     kapan kabar hapusnya SAMPAI di server
--    terakhir_aktif  kapan sebuah HP terakhir SELESAI sinkron
--
--  Kalau kabarnya sampai sebelum HP yang PALING TELAT terakhir sinkron,
--  berarti semua HP sudah membacanya. Mundur satu menit lagi untuk menutup
--  jeda antara "HP selesai menarik" dan "HP melapor hadir".
--
--  `deleted_at` SENGAJA tidak dipakai sebagai patokan: itu jam HP saat
--  menghapus, bukan kapan kabarnya sampai. Hapusan yang dibuat offline jam 9
--  tapi baru sampai jam 12 akan terbuang sebelum HP lain sempat tahu.
--
--  Kalau tidak ada HP aktif sama sekali, batasnya kosong, dan perbandingan
--  dengan kosong tidak pernah benar — jadi TIDAK ADA yang terbuang. Kalau
--  ragu, diam.
--
--  ── KALAU PEMBUANGAN BERHENTI ──
--
--  Satu HP yang lama tidak dibuka menahan batasnya di masa lalu, dan
--  pembuangan berhenti total. Itu bukan rusak: itu tanda ada HP yang perlu
--  dicabut atau dilupakan di halaman Perangkat.
-- =====================================================================

-- ---------------------------------------------------------------------
--  1. Lepas rantai item struk -> produk
--
--  Item struk sudah MENYALIN nama dan harga produknya sendiri
--  (`product_name`, `price_at_sale`), dan tidak ada satu pun laporan yang
--  mencari produk lewat `product_id`. Rantainya cuma menghalangi produk yang
--  pernah laku untuk dibuang.
--
--  Aplikasi melepas rantai yang sama di SQLite-nya lewat migrasi v24. Itu
--  WAJIB sudah terpasang di semua HP sebelum produk pertama dibuang: HP
--  dengan APK lama akan menolak item struk yang produknya sudah tiada, dan
--  riwayatnya bolong tanpa pesan apa pun.
-- ---------------------------------------------------------------------
alter table public.transaction_items
  drop constraint if exists transaction_items_product_id_fkey;

-- ---------------------------------------------------------------------
--  2. Fungsinya
--
--  `security definer`: berjalan sebagai pemilik database, jadi tidak
--  terhalang pencabutan hak DELETE yang dipasang `rls.sql` untuk HP.
--
--  `p_jeda` cuma rem kedua — umur minimal sejak dihapus. Rem utamanya tetap
--  "centang biru". Untuk mencoba, panggil dengan '0 seconds'.
-- ---------------------------------------------------------------------
create or replace function public.buang_sampah(
  p_jeda interval default interval '30 days'
)
returns table (tabel text, dibuang bigint)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_batas  timestamptz;
  v_jumlah bigint;
begin
  select min(terakhir_aktif) - interval '1 minute'
    into v_batas
    from public.perangkat
   where status = 'aktif';

  -- Transaksi SENGAJA TIDAK dibuang. Transaksi tidak pernah dihapus, hanya
  -- DIBATALKAN (`deleted_at` + siapa + alasan), dan catatan pembatalan
  -- disimpan selamanya sebagai bukti untuk owner. Lihat
  -- `supabase/transaksi_batal.sql`.

  -- Pengeluaran juga TIDAK dibuang, dengan alasan yang sama: yang terhapus
  -- adalah yang DIBATALKAN, dan itu bukti. Lihat
  -- `supabase/pengeluaran_batal.sql`.

  -- Produk. Boleh walau pernah laku — rantainya sudah dilepas di langkah 1.
  delete from public.products
   where deleted_at is not null
     and server_urut < v_batas
     and deleted_at  < now() - p_jeda;
  get diagnostics v_jumlah = row_count;
  tabel := 'produk'; dibuang := v_jumlah; return next;

  -- Kategori, SESUDAH produk. Produk masih punya rantai ke kategori, jadi
  -- yang masih ditunjuk produk mana pun dilewati, bukan digagalkan.
  -- Menghapus kategori di aplikasi sudah melepas produknya lebih dulu, jadi
  -- biasanya tidak ada yang tertahan.
  delete from public.categories c
   where c.deleted_at is not null
     and c.server_urut < v_batas
     and c.deleted_at  < now() - p_jeda
     and not exists (select 1 from public.products p where p.category_id = c.id);
  get diagnostics v_jumlah = row_count;
  tabel := 'kategori'; dibuang := v_jumlah; return next;
end $$;

-- ---------------------------------------------------------------------
--  3. HANYA dashboard yang boleh memanggilnya
--
--  Supabase memberi hak EXECUTE ke `anon` dan `authenticated` untuk setiap
--  fungsi baru di skema public. Kalau dibiarkan, HP mana pun — termasuk
--  yang kuncinya bocor — bisa memicu pembuangan permanen lewat API.
--  Dicabut eksplisit; dashboard dan pg_cron berjalan sebagai pemilik, jadi
--  tetap bisa.
-- ---------------------------------------------------------------------
revoke all on function public.buang_sampah(interval) from public;
revoke all on function public.buang_sampah(interval) from anon, authenticated;

-- =====================================================================
--  CARA MENCOBA
--
--  1. Hapus produk atau kategori dari aplikasi. Transaksi dan pengeluaran
--     tidak ikut — pembatalan keduanya disimpan selamanya.
--  2. Tarik-segarkan di KEDUA HP, supaya dua-duanya "centang biru".
--  3. Jalankan:
--
--       select * from public.buang_sampah('0 seconds');
--
--     Hasilnya berupa laporan, misalnya:
--
--        tabel       | dibuang
--       -------------+---------
--        produk      |       1
--        kategori    |       0
--
--  Kalau semuanya 0 padahal ada yang baru dihapus: kemungkinan besar ada HP
--  yang belum sinkron sesudah penghapusan. Cek dengan:
--
--       select nama, status, terakhir_aktif from public.perangkat;
--
--  PEMERIKSAAN HAK — hasil yang benar: KOSONG.
--
--       select grantee from information_schema.routine_privileges
--       where routine_name = 'buang_sampah'
--         and grantee in ('anon', 'authenticated');
-- =====================================================================

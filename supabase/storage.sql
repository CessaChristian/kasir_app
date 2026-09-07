-- =====================================================================
--  PENYIMPANAN GAMBAR PRODUK
--
--  Jalankan SEKALI lewat SQL Editor di dashboard Supabase.
--  Aman dijalankan ulang.
--
--  ── KENAPA GAMBARNYA TIDAK DISIMPAN DI DALAM TABEL ──
--
--  PostgreSQL sanggup menyimpan berkas di kolom `bytea`, dan pada skala warung
--  (puluhan produk, ~50 KB per gambar) ukurannya sama sekali tidak memberatkan.
--  Tapi itu melawan cara sinkronisasi aplikasi ini bekerja.
--
--  Sync menarik dan mendorong BARIS UTUH. Kalau gambar ada di dalam baris
--  produk, maka mengubah harga saja akan mengirim ulang seluruh gambarnya —
--  padahal gambarnya tidak berubah. Ditambah REST mengirim JSON, jadi biner
--  harus di-base64 dulu: sepertiga lebih besar tanpa alasan.
--
--  Dengan storage terpisah, baris produk hanya membawa teks path, dan berkas
--  gambarnya berpindah SEKALI seumur hidupnya.
-- =====================================================================

-- ---------------------------------------------------------------------
--  Bucket
--
--  `public = false` disengaja. Bucket publik bisa dibuka siapa saja yang tahu
--  URL-nya, tanpa login — dan URL-nya mudah ditebak karena berisi nama berkas
--  yang juga tersimpan di kolom `products.image_path`. Aplikasi sudah login
--  sebagai akun perangkat, jadi tidak ada kerumitan tambahan dari memilih
--  bucket privat.
--
--  Batas 2 MB per berkas: gambar disimpan aplikasi sebagai WebP sisi terpanjang
--  800 px, yang di praktiknya 30–60 KB. Batas ini bukan untuk penggunaan
--  normal, melainkan supaya berkas yang jelas salah tidak diam-diam
--  menghabiskan kuota.
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'product-images',
  'product-images',
  false,
  2097152,
  array['image/webp','image/jpeg','image/png']
)
on conflict (id) do update
  set public             = excluded.public,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- ---------------------------------------------------------------------
--  Akses
--
--  Semua perangkat yang sah berizin sama, sejalan dengan alasan yang sama
--  seperti pada tabel (lihat rls.sql): login staf diperiksa di dalam aplikasi,
--  jadi server tidak tahu siapa yang sedang memegang HP.
--
--  DELETE diberikan supaya berkas yatim — sisa gambar dari produk yang sudah
--  diganti fotonya — ikut terbuang, bukan menumpuk selamanya.
--
--  Risikonya sudah ditimbang: menghapus berdasarkan pandangan SATU perangkat
--  bisa membuang berkas yang perangkat lain masih pakai. Yang membuatnya aman
--  di sini adalah pembersihan dijalankan SETELAH tarikan selesai, sehingga
--  daftar produk lokal sudah memuat perubahan dari perangkat lain — dan
--  aplikasi punya penjaga tambahan yang menolak menghapus apa pun kalau tabel
--  produknya kosong (lihat SyncGambar).
-- ---------------------------------------------------------------------
drop policy if exists gambar_baca   on storage.objects;
drop policy if exists gambar_tambah on storage.objects;
drop policy if exists gambar_ubah   on storage.objects;
drop policy if exists gambar_hapus  on storage.objects;

create policy gambar_baca on storage.objects
  for select to authenticated
  using (bucket_id = 'product-images');

create policy gambar_tambah on storage.objects
  for insert to authenticated
  with check (bucket_id = 'product-images');

-- Diperlukan karena unggahan memakai `upsert`: mengganti foto produk menulis
-- ke nama berkas BARU, tapi percobaan ulang setelah unggahan yang gagal di
-- tengah jalan akan menimpa berkas yang sama.
create policy gambar_ubah on storage.objects
  for update to authenticated
  using (bucket_id = 'product-images')
  with check (bucket_id = 'product-images');

create policy gambar_hapus on storage.objects
  for delete to authenticated
  using (bucket_id = 'product-images');

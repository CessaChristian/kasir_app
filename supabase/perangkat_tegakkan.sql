-- =====================================================================
--  MENYALAKAN PENEGAKAN DAFTAR PERANGKAT
--
--  Sesudah ini, aturan di server berbunyi: boleh baca-tulis HANYA kalau
--  perangkatnya terdaftar dan aktif. Ini keadaan TETAP — tidak ada berkas
--  untuk melonggarkannya lagi, dan itu disengaja.
--
--  ── KALAU SEMUA HP TERKUNCI ──
--
--  Dua jalan pulih, dan keduanya TIDAK melonggarkan aturan apa pun:
--
--  1. Kalau yang kosong/salah adalah ISI tabel `perangkat` — misal barisnya
--     terhapus — tidak perlu dashboard sama sekali. Buka aplikasinya: ia
--     melihat dirinya tidak terdaftar lalu memunculkan layar kunci sendiri.
--     Masukkan kunci pemasangan, barisnya dibuat lagi, akses kembali.
--
--     Itu bisa karena dua hal yang sengaja dibiarkan longgar: `baca_perangkat`
--     memakai `using (true)` sehingga perangkat tetap boleh membaca daftarnya
--     walau barisnya hilang, dan `daftarkan_perangkat` adalah `security
--     definer` sehingga berjalan sebagai pemilik dan tidak diperiksa RLS.
--     Keduanya jangan diubah — di situlah jalan pulangnya.
--
--  2. Kalau yang rusak adalah ATURANNYA — misal fungsi `perangkat_aktif()`
--     terhapus atau berganti nama, sehingga semua kueri galat — jalankan
--     ulang BERKAS INI. Ia memakai `create or replace`, jadi memperbaiki
--     dirinya sendiri.
--
--  Yang tetap perlu disiapkan sebelum menjalankannya pertama kali: buka
--  halaman Perangkat, pastikan SEMUA HP sudah muncul dan berstatus aktif.
--  Bukan karena sulit dipulihkan, tapi supaya warungnya tidak berhenti
--  melayani sambil menunggu tiap HP didaftarkan satu-satu — dan pendaftaran
--  itu butuh internet.
-- =====================================================================

--  Satu tempat bertanya "boleh tidak", supaya syaratnya tidak tersalin
--  berbeda-beda ke sembilan tabel.
--
--  STABLE: dievaluasi sekali per pernyataan, bukan per baris.
create or replace function public.perangkat_aktif()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.perangkat
    where id = auth.uid() and status = 'aktif'
  );
$$;

revoke all on function public.perangkat_aktif() from public;
grant execute on function public.perangkat_aktif() to authenticated;

do $$
declare t text;
begin
  foreach t in array array[
    'users','user_permissions','categories','products','shifts',
    'transactions','transaction_items','expenses'
  ] loop
    execute format('drop policy if exists %I on public.%I', 'baca_'||t, t);
    execute format('drop policy if exists %I on public.%I', 'tambah_'||t, t);
    execute format('drop policy if exists %I on public.%I', 'ubah_'||t, t);
    execute format('drop policy if exists %I on public.%I', 'spike_'||t, t);

    execute format(
      'create policy %I on public.%I for select to authenticated '
      'using (public.perangkat_aktif())', 'baca_'||t, t);
    execute format(
      'create policy %I on public.%I for insert to authenticated '
      'with check (public.perangkat_aktif())', 'tambah_'||t, t);
    execute format(
      'create policy %I on public.%I for update to authenticated '
      'using (public.perangkat_aktif()) with check (public.perangkat_aktif())',
      'ubah_'||t, t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
--  Berkas foto ikut dijaga
--
--  Tanpa ini, perangkat yang dicabut masih bisa menyentuh bucket foto. Dan
--  akibatnya bukan sekadar bocor, tapi merusak: daftar produk di HP yang
--  dicabut MEMBEKU sejak ia dicabut, sehingga foto yang ditambahkan pemilik
--  sesudah itu terlihat olehnya sebagai "tidak dirujuk siapa pun" — lalu
--  dibuang dari server.
--
--  Persis bentuk bug foto yang dulu: aturan pembersihan yang benar,
--  dijalankan di atas gambaran dunia yang sudah kedaluwarsa.
-- ---------------------------------------------------------------------
drop policy if exists gambar_baca   on storage.objects;
drop policy if exists gambar_tambah on storage.objects;
drop policy if exists gambar_ubah   on storage.objects;
drop policy if exists gambar_hapus  on storage.objects;

create policy gambar_baca on storage.objects
  for select to authenticated
  using (bucket_id = 'product-images' and public.perangkat_aktif());

create policy gambar_tambah on storage.objects
  for insert to authenticated
  with check (bucket_id = 'product-images' and public.perangkat_aktif());

create policy gambar_ubah on storage.objects
  for update to authenticated
  using (bucket_id = 'product-images' and public.perangkat_aktif())
  with check (bucket_id = 'product-images' and public.perangkat_aktif());

create policy gambar_hapus on storage.objects
  for delete to authenticated
  using (bucket_id = 'product-images' and public.perangkat_aktif());

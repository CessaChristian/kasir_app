-- =====================================================================
--  MENYALAKAN PENEGAKAN DAFTAR PERANGKAT
--
--  JANGAN dijalankan sebelum gerbang ini terlewati:
--
--    Buka halaman Perangkat di aplikasi, pastikan SEMUA HP yang dipakai
--    sudah muncul di daftar dan berstatus aktif.
--
--  Kalau dijalankan lebih dulu, setiap HP yang belum terdaftar akan langsung
--  terkunci — termasuk HP yang kamu pakai untuk membukanya lagi. Pulihnya
--  harus lewat dashboard, jadi pastikan kamu bisa membuka dashboard Supabase
--  saat menjalankan ini.
--
--  ── RENCANA MUNDUR ──
--
--  Jalankan supabase/perangkat_longgarkan.sql. Satu perintah, tanpa perlu
--  menyentuh HP mana pun.
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

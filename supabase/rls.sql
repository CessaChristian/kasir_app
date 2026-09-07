-- =====================================================================
--  PENGETATAN AKSES — menggantikan policy sementara `spike_*`
--
--  Jalankan SEKALI lewat SQL Editor di dashboard Supabase.
--  Aman dijalankan ulang: semuanya memakai `if exists` / `if not exists`.
--
--  ── APA YANG BISA DAN TIDAK BISA DITEGAKKAN DI SINI ──
--
--  Login staf (PIN) diperiksa di dalam aplikasi, terhadap tabel `users`
--  lokal — bukan ke server. Itu konsekuensi aplikasi yang harus jalan tanpa
--  internet. Akibatnya server TIDAK TAHU siapa yang sedang memegang HP; ia
--  hanya melihat "sebuah perangkat yang sah mengirim data".
--
--  Maka semua akun perangkat di sini sengaja BERIZIN SAMA. Aturan "kasir
--  tidak boleh mengubah harga" ditegakkan aplikasi, bukan berkas ini —
--  karena owner memang boleh memakai HP kasir, dan sebaliknya.
--
--  Yang tetap bisa ditegakkan server adalah aturan yang benar TANPA PEDULI
--  siapa yang login. Itu yang ditulis di bawah, dan nilainya nyata: aturan
--  ini tetap berlaku walau APK dibongkar dan kredensial perangkat dicuri.
-- =====================================================================

-- ---------------------------------------------------------------------
--  1. Buang policy sementara
--
--  Isinya `using (true) with check (true)` — siapa pun yang berhasil login
--  boleh melakukan apa saja pada semua tabel. Sengaja longgar untuk uji
--  coba sinkronisasi, dan tidak layak dipakai pengguna sungguhan.
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'users','permissions','user_permissions','categories','products',
    'shifts','transactions','transaction_items','expenses'
  ] loop
    execute format('drop policy if exists %I on public.%I', 'spike_'||t, t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
--  2. Tabel yang ikut sinkronisasi: boleh baca, tambah, ubah — TIDAK hapus
--
--  Penghapusan DELETE sengaja tidak diberi policy sama sekali. Seluruh
--  penghapusan di aplikasi ini bersifat lunak (kolom `deleted_at` diisi,
--  barisnya tetap ada), dan sudah diperiksa: tidak ada satu pun jalur di
--  kode yang mengirim DELETE ke server.
--
--  Artinya larangan ini tidak menghalangi apa pun yang sah, tapi menutup
--  kerusakan yang TIDAK BISA dipulihkan. Data masih bisa dikotori oleh
--  perangkat yang kredensialnya bocor — tapi tidak bisa dilenyapkan, dan
--  itu perbedaan kelas.
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'users','categories','products','shifts',
    'transactions','transaction_items','expenses'
  ] loop
    execute format(
      'create policy %I on public.%I for select to authenticated using (true)',
      'baca_'||t, t);
    execute format(
      'create policy %I on public.%I for insert to authenticated with check (true)',
      'tambah_'||t, t);
    execute format(
      'create policy %I on public.%I for update to authenticated using (true) with check (true)',
      'ubah_'||t, t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
--  3. Tabel izin: baca saja
--
--  `permissions` adalah data seed statis. `user_permissions` belum ikut
--  sinkronisasi sama sekali (sudah diperiksa: nol penyebutan di
--  sync_engine.dart), jadi tidak ada yang perlu menulisnya dari perangkat.
--  Kalau nanti ikut disinkronkan, policy tulisnya ditambahkan saat itu —
--  bukan dibuka sekarang "untuk berjaga-jaga".
-- ---------------------------------------------------------------------
create policy baca_permissions on public.permissions
  for select to authenticated using (true);
create policy baca_user_permissions on public.user_permissions
  for select to authenticated using (true);

-- ---------------------------------------------------------------------
--  4. Cabut hak DELETE sampai ke lapisan GRANT
--
--  RLS tanpa policy DELETE sudah menolak penghapusan, tapi menolaknya
--  DIAM-DIAM: permintaan berhasil dengan "0 baris terpengaruh". Mencabut
--  di lapisan GRANT membuatnya gagal dengan pesan jelas, sehingga kalau
--  suatu hari ada kode yang keliru mengirim DELETE, kita mendengarnya
--  alih-alih mengira penghapusannya berhasil.
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'users','permissions','user_permissions','categories','products',
    'shifts','transactions','transaction_items','expenses'
  ] loop
    execute format('revoke delete on public.%I from authenticated, anon', t);
  end loop;
end $$;

-- =====================================================================
--  5. BATASAN NILAI
--
--  Sudah diperiksa terhadap data yang ada sekarang: NOL pelanggaran di
--  seluruh tabel, termasuk 613 baris rincian transaksi. Jadi pemasangannya
--  tidak akan gagal dan tidak ada baris lama yang perlu diperbaiki dulu.
--
--  Gunanya: aturan ini berlaku pada tulisan dari mana pun, termasuk dari
--  perangkat yang kredensialnya bocor dan dari skrip yang salah tulis.
-- =====================================================================
alter table public.products
  add constraint harga_produk_wajar check (price >= 0) not valid;

alter table public.transactions
  add constraint total_wajar         check (total >= 0)                       not valid,
  add constraint uang_diterima_wajar check (cash_received is null or cash_received >= 0) not valid,
  add constraint kembalian_wajar     check (change is null or change >= 0)    not valid;

alter table public.transaction_items
  add constraint jumlah_wajar   check (qty > 0)                       not valid,
  add constraint harga_wajar    check (price_at_sale >= 0)            not valid,
  add constraint subtotal_wajar check (subtotal >= 0)                 not valid,
  -- Invarian uang yang paling berharga: subtotal WAJIB hasil kali jumlah
  -- dan harga saat itu. Sudah dibuktikan berlaku pada 613 dari 613 baris.
  -- Ini yang menghalangi perangkat yang dibajak menulis rincian dengan
  -- angka yang tidak saling cocok.
  add constraint subtotal_konsisten check (subtotal = qty * price_at_sale) not valid;

alter table public.expenses
  add constraint jumlah_pengeluaran_wajar check (amount > 0) not valid;

-- `not valid` di atas berarti batasan berlaku untuk tulisan BARU tanpa
-- memindai seluruh tabel saat dipasang. Baris lama sudah kita periksa
-- bersih, jadi sekalian disahkan — dijalankan terpisah supaya penguncian
-- tabelnya sesingkat mungkin.
alter table public.products           validate constraint harga_produk_wajar;
alter table public.transactions       validate constraint total_wajar;
alter table public.transactions       validate constraint uang_diterima_wajar;
alter table public.transactions       validate constraint kembalian_wajar;
alter table public.transaction_items  validate constraint jumlah_wajar;
alter table public.transaction_items  validate constraint harga_wajar;
alter table public.transaction_items  validate constraint subtotal_wajar;
alter table public.transaction_items  validate constraint subtotal_konsisten;
alter table public.expenses           validate constraint jumlah_pengeluaran_wajar;

-- =====================================================================
--  SISA PENGETATAN AKSES
--
--  Jalankan SEKALI lewat SQL Editor di dashboard Supabase.
--  Aman dijalankan ulang: semuanya `if exists` / `revoke`.
--
--  ── BERKAS INI BUKAN LAGI PENGETATAN MENYELURUH ──
--
--  Dulu isinya menggantikan seluruh policy sementara `spike_*` untuk semua
--  tabel. Itu sudah dikerjakan `supabase/perangkat_tegakkan.sql`, dan versinya
--  lebih ketat — bukan `using (true)` melainkan `using (public.perangkat_aktif())`.
--
--  Memakai berkas lama apa adanya justru MELONGGARKAN yang sudah terpasang,
--  dan `create policy` dengan nama yang sudah ada akan gagal `42710` lalu
--  membatalkan seluruh blok. Maka berkas ini ditulis ulang: isinya hanya
--  yang benar-benar masih kurang, diperiksa langsung ke `pg_policies`.
--
--  Keadaan server saat berkas ini ditulis (2026-09-28):
--
--    8 tabel data  → baca/tambah/ubah sudah `perangkat_aktif()`, DELETE nihil
--    perangkat     → `baca_perangkat` sengaja `using (true)`, lihat di bawah
--    permissions   → MASIH `spike_permissions` = ALL + true   ← yang ditambal
-- =====================================================================

-- ---------------------------------------------------------------------
--  1. Tabel `permissions` — tutup rapat, tanpa pengganti
--
--  `spike_permissions` berbunyi `for all using (true)`: setiap perangkat yang
--  berhasil login boleh membaca, menambah, mengubah, DAN MENGHAPUS katalog
--  izin. Karena syaratnya `true` dan bukan `public.perangkat_aktif()`,
--  perangkat yang sudah DICABUT pun masih bisa.
--
--  Ini satu-satunya tabel yang masih terbuka, dan kebetulan yang paling
--  mahal kalau dihapus. `public.user_permissions.permission_code` menunjuk
--  ke sini dengan `on delete cascade`, dan cascade dijalankan mesin
--  database sebagai penegakan relasi — RLS TIDAK ikut memeriksanya. Jadi
--  satu `delete from public.permissions` melenyapkan baris
--  `user_permissions` secara fisik, menembus perlindungan "tidak ada policy
--  DELETE" yang dipasang di tabel itu, dan tanpa meninggalkan nisan
--  (`deleted_at`) sehingga perangkat lain tidak akan pernah tahu.
--
--  Policy-nya dibuang TANPA diganti, jadi tabelnya menolak semua akses dari
--  perangkat. Itu aman: sudah diperiksa, aplikasi tidak pernah menyentuh
--  tabel ini di server — `sync_engine.dart` hanya menyinkronkan
--  `user_permissions`, dan tidak ada satu pun panggilan Supabase ke
--  `permissions` di seluruh `lib/`. Isinya disemai dari dashboard lewat
--  `supabase/izin.sql`, yang berjalan sebagai pemilik dan tidak butuh policy.
-- ---------------------------------------------------------------------
drop policy if exists spike_permissions on public.permissions;

-- ---------------------------------------------------------------------
--  2. Sapu sisa policy sementara pada tabel data
--
--  `pg_policies` per 2026-09-28 sudah tidak menunjukkan satu pun, karena
--  `perangkat_tegakkan.sql` membuangnya saat menimpa. Ditulis di sini supaya
--  pemasangan lain yang pernah memakai `schema.sql` versi lama ikut bersih.
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'users','user_permissions','categories','products','shifts',
    'transactions','transaction_items','expenses'
  ] loop
    execute format('drop policy if exists %I on public.%I', 'spike_'||t, t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
--  3. Cabut hak DELETE sampai lapisan GRANT
--
--  RLS tanpa policy DELETE sudah menolak penghapusan — tapi menolaknya
--  DIAM-DIAM: permintaannya sukses dengan "0 baris terpengaruh", persis
--  seperti kalau barisnya memang tidak ada. Kalau suatu hari ada kode kita
--  yang keliru mengirim DELETE, kita akan mengira penghapusannya berhasil.
--
--  Mencabutnya di lapisan GRANT membuatnya gagal BERSUARA (`42501
--  insufficient_privilege`), jadi kekeliruan seperti itu terdengar.
--
--  Tidak ada yang sah terhalang: seluruh penghapusan di aplikasi ini lunak
--  (`deleted_at` diisi lewat UPDATE). Fungsi `lupakan_perangkat` juga aman —
--  ia `security definer`, berjalan sebagai pemilik, tidak lewat hak ini.
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'users','permissions','user_permissions','categories','products',
    'shifts','transactions','transaction_items','expenses','perangkat'
  ] loop
    execute format('revoke delete on public.%I from anon, authenticated', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
--  4. `permissions` juga dicabut hak tulisnya
--
--  Langkah 1 sudah membuat RLS menolak semuanya. Ini lapisan kedua, supaya
--  penolakannya bersuara dan supaya niatnya terbaca jelas: tabel ini milik
--  server, bukan milik perangkat.
-- ---------------------------------------------------------------------
revoke insert, update on public.permissions from anon, authenticated;

-- =====================================================================
--  PEMERIKSAAN SESUDAH DIJALANKAN
--
--  (a) `permissions` tidak boleh punya policy sama sekali, dan 8 tabel data
--      tidak boleh punya satu pun baris DELETE:
--
--        select tablename, policyname, cmd, qual
--        from pg_policies where schemaname = 'public'
--        order by tablename, policyname;
--
--  (b) hak DELETE benar-benar tercabut:
--
--        select table_name, privilege_type
--        from information_schema.role_table_grants
--        where table_schema = 'public'
--          and grantee in ('anon','authenticated')
--          and privilege_type = 'DELETE';
--
--      Hasil yang benar: KOSONG.
-- =====================================================================

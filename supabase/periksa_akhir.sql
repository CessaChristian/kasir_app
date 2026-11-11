-- =====================================================================
--  PEMERIKSAAN AKHIR SERVER (audit 6 Nov 2026 nomor 20)
--
--  Jalankan lewat SQL Editor SESUDAH semua berkas di URUTAN.md. Hanya
--  membaca, tidak mengubah apa pun. Aman dijalankan kapan saja.
--
--  Hasil yang BENAR: kelima bagian di bawah tidak mengembalikan baris
--  apa pun. Setiap baris yang muncul adalah tanda berkas terlewat, salah
--  urutan, atau berkas lama yang dijalankan ulang (lihat URUTAN.md).
--
--  Daftar harapan dibuat dari server tiruan yang dibangun persis menurut
--  URUTAN.md. Kalau ada berkas SQL baru, daftar ini ikut diperbarui.
-- =====================================================================

-- 1. Fungsi yang punya lebih dari satu versi (mis. perangkat_hadir lama dan
--    baru berdampingan, sehingga panggilan dari aplikasi ditolak PGRST203).
select 'fungsi dobel' as masalah, p.proname as nama, count(*) as jumlah
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
 group by p.proname
having count(*) > 1;

-- 2. Fungsi yang kurang, atau berbeda parameternya.
with harap(nama, parameter) as (values ('abaikan_kunci_recovery',''),('alih_shift',''),('arahkan_bill_produk_gabung',''),('arahkan_item_produk_gabung',''),('buang_sampah','p_jeda interval'),('catat_cap_asli',''),('catat_model_perangkat','p_model text, p_tablet boolean'),('cocok_pin','p_nilai text, p_garam text, p_hash text'),('daftarkan_perangkat','p_kunci text, p_nama text'),('dari_api',''),('gabung_produk_kembar',''),('gabung_shift',''),('hapus_bill','p_bill uuid'),('hash_kredensial_sah','p_hash text'),('isi_nomor_kasir',''),('jaga_akun_owner',''),('jaga_status_bill',''),('jaga_versi_terbaru',''),('klaim_berlaku','p_tx uuid, p_pada timestamp with time zone'),('klaim_bill','p_bill uuid, p_tx uuid'),('kode_perangkat_ke','n integer'),('kunci_cap_asli','p_tabel text, p_id uuid'),('kunci_kolom',''),('lepas_kategori_terhapus_produk',''),('lepas_klaim_bill','p_bill uuid, p_tx uuid'),('lepas_produk_kategori_terhapus',''),('lupakan_perangkat','p_id uuid, p_pin text'),('pemegang_shift_lain','p_shift_id uuid'),('perangkat_aktif',''),('perangkat_hadir','p_shift_id uuid, p_tarik_bersih boolean, p_tertahan integer, p_gagal_kirim integer, p_selisih_jam integer'),('peta_isi_bill','p_items jsonb'),('pin_owner_cocok','p_pin text'),('potong_nama_perangkat',''),('shift_dipegang_perangkat_lain','p_shift_id uuid'),('status_bill','p_bill uuid'),('stempel_server_urut',''),('tolak_batal_kasir_shift_tutup',''),('tolak_hapus_item_nota_sah',''),('tolak_owner_kedua',''),('ubah_kredensial_owner','p_bukti text, p_jenis text, p_pin_hash text, p_salt text, p_recovery_hash text, p_recovery_salt text'),('ubah_nama_perangkat','p_id uuid, p_nama text'),('ubah_status_perangkat','p_id uuid, p_aktif boolean, p_pin text'),('ujung_gabungan','p_shift uuid'))
select 'fungsi kurang' as masalah, h.nama, h.parameter
  from harap h
 where not exists (
   select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = h.nama
      and pg_get_function_identity_arguments(p.oid) = h.parameter);

-- 3. Trigger yang kurang.
with harap(tabel, nama) as (values ('categories','trg_categories_aa_cap_asli'),('categories','trg_categories_jaga_versi'),('categories','trg_categories_lepas_produk'),('categories','trg_categories_server_urut'),('expenses','trg_expenses_aa_cap_asli'),('expenses','trg_expenses_alih_shift'),('expenses','trg_expenses_jaga_versi'),('expenses','trg_expenses_kunci_kolom'),('expenses','trg_expenses_sah_batal'),('expenses','trg_expenses_server_urut'),('info_toko','trg_info_toko_aa_cap_asli'),('info_toko','trg_info_toko_jaga_versi'),('info_toko','trg_info_toko_server_urut'),('open_bills','trg_open_bills_aa_cap_asli'),('open_bills','trg_open_bills_alih_shift'),('open_bills','trg_open_bills_jaga'),('open_bills','trg_open_bills_jaga_versi'),('open_bills','trg_open_bills_produk_gabung'),('open_bills','trg_open_bills_server_urut'),('perangkat','trg_perangkat_potong_nama'),('products','trg_products_aa_cap_asli'),('products','trg_products_jaga_versi'),('products','trg_products_kembar'),('products','trg_products_lepas_kategori_terhapus'),('products','trg_products_server_urut'),('shifts','trg_shifts_aa_cap_asli'),('shifts','trg_shifts_gabung'),('shifts','trg_shifts_jaga_versi'),('shifts','trg_shifts_kunci_kolom'),('shifts','trg_shifts_server_urut'),('transaction_items','trg_transaction_items_aa_cap_asli'),('transaction_items','trg_transaction_items_jaga_versi'),('transaction_items','trg_transaction_items_kunci_kolom'),('transaction_items','trg_transaction_items_produk_gabung'),('transaction_items','trg_transaction_items_sah_batal'),('transaction_items','trg_transaction_items_server_urut'),('transactions','trg_transactions_aa_cap_asli'),('transactions','trg_transactions_alih_shift'),('transactions','trg_transactions_jaga_versi'),('transactions','trg_transactions_kunci_kolom'),('transactions','trg_transactions_sah_batal'),('transactions','trg_transactions_server_urut'),('user_permissions','trg_user_permissions_aa_cap_asli'),('user_permissions','trg_user_permissions_jaga_versi'),('user_permissions','trg_user_permissions_server_urut'),('users','trg_users_aa_cap_asli'),('users','trg_users_abaikan_kunci_recovery'),('users','trg_users_jaga_owner'),('users','trg_users_jaga_versi'),('users','trg_users_kunci_kolom'),('users','trg_users_nomor_kasir'),('users','trg_users_owner_kedua'),('users','trg_users_server_urut'))
select 'trigger kurang' as masalah, h.tabel, h.nama
  from harap h
 where not exists (
   select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = h.tabel and t.tgname = h.nama
      and not t.tgisinternal);

-- 4. Constraint (CHECK, foreign key, unik) yang kurang.
with harap(tabel, nama) as (values ('expenses','expenses_cancelled_by_user_id_fkey'),('expenses','expenses_category_check'),('expenses','expenses_nominal_wajar'),('expenses','expenses_qty_check'),('expenses','expenses_shift_id_fkey'),('expenses','expenses_user_id_fkey'),('info_toko','info_toko_alamat_check'),('info_toko','info_toko_id_check'),('info_toko','info_toko_no_hp_check'),('info_toko','info_toko_wifi_nama_check'),('info_toko','info_toko_wifi_sandi_check'),('open_bills','open_bills_name_check'),('open_bills','open_bills_shift_id_fkey'),('open_bills','open_bills_transaction_id_fkey'),('open_bills','open_bills_user_id_fkey'),('perangkat','perangkat_id_fkey'),('perangkat','perangkat_shift_id_fkey'),('perangkat','perangkat_status_check'),('products','products_category_id_fkey'),('products','products_harga_wajar'),('products','products_jalur_foto_sah'),('shifts','shifts_digabung_ke_fkey'),('shifts','shifts_kas_awal_tidak_negatif'),('shifts','shifts_user_id_fkey'),('transaction_items','transaction_items_angka_wajar'),('transaction_items','transaction_items_transaction_id_fkey'),('transactions','transactions_angka_wajar'),('transactions','transactions_cancelled_by_user_id_fkey'),('transactions','transactions_cashier_user_id_fkey'),('transactions','transactions_order_type_check'),('transactions','transactions_payment_method_check'),('transactions','transactions_shift_id_fkey'),('user_permissions','user_permissions_pasangan_unik'),('user_permissions','user_permissions_permission_code_fkey'),('user_permissions','user_permissions_user_id_fkey'),('users','users_pin_hash_sah'),('users','users_recovery_hash_sah'),('users','users_role_check'),('users','users_username_key'))
select 'constraint kurang' as masalah, h.tabel, h.nama
  from harap h
 where not exists (
   select 1 from pg_constraint c join pg_namespace n on n.oid = c.connamespace
    where n.nspname = 'public' and c.conrelid::regclass::text = h.tabel
      and c.conname = h.nama);

-- 5. Fungsi yang WAJIB bisa dipanggil HP (role authenticated). Dulu dua
--    fungsi bantu dicabut izinnya, dan semua perubahan dari HP ditolak
--    `permission denied` (8 Nov 2026).
select 'izin HP kurang' as masalah, f as fungsi
  from unnest(array[
    'public.kunci_cap_asli(text, uuid)',
    'public.hash_kredensial_sah(text)',
    'public.perangkat_aktif()',
    'public.perangkat_hadir(uuid, boolean, integer, integer, integer)',
    'public.ubah_status_perangkat(uuid, boolean, text)',
    'public.lupakan_perangkat(uuid, text)',
    'public.ubah_kredensial_owner(text, text, text, text, text, text)',
    'public.status_bill(uuid)',
    'public.klaim_bill(uuid, uuid)',
    'public.lepas_klaim_bill(uuid, uuid)',
    'public.hapus_bill(uuid)'
  ]) f
 where not has_function_privilege('authenticated', f, 'execute');

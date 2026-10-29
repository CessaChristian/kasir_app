# Skema Database

Ada **dua database** yang isinya sama-sama penting:

| | Di HP | Di server |
|---|---|---|
| Mesin | SQLite lewat **Drift** | PostgreSQL di **Supabase** |
| Definisi | `lib/data/app_database.dart` | berkas `supabase/*.sql` |
| Versi | `schemaVersion = 42` | urutan di [`supabase/URUTAN.md`](../supabase/URUTAN.md) |

> `app_database.g.dart` adalah hasil generate `build_runner` — **jangan diedit**.

---

## 1. Kolom wajib di tabel yang disinkron

| Kolom | Fungsi |
|---|---|
| `id` (TEXT UUID) | Primary key, dibuat `newUuid()` — unik lintas HP. |
| `created_at` | Kapan dibuat. |
| `updated_at` | Kapan terakhir diubah — versi yang lebih baru menang. |
| `deleted_at` | Terisi = dihapus/dibatalkan (tidak pernah hapus permanen dari HP). |
| `sync_status` | Lokal saja: `pending` = belum terkirim, `synced` = sudah. |

Di server ada tambahan **`server_urut`** (jam kedatangan) — penanda tarik HP.

## 2. Daftar tabel

### Disinkron
- **`users`** — akun: `username` (huruf kecil, unik), `pin_hash`, `salt`,
  `role` (`owner`/`cashier`), `is_active`, `nomor_kasir` (untuk nomor nota),
  data recovery code, penghitung salah PIN & kunci login.
- **`permissions`** (referensi kode izin) & **`user_permissions`** (izin per kasir).
- **`categories`** — `name`, `icon_codepoint`, `tampil_di_kasir`.
- **`products`** — `name`, `price`, `category_id`, `has_spicy_option`,
  `has_sweet_option`, `has_ice_option`, `image_path` (foto di Supabase Storage).
- **`shifts`** — `user_id`, `user_name` (salinan), `start_at`, `end_at`
  (null = berjalan), `kas_awal`, `digabung_ke` (diisi server, v42).
- **`transactions`** — `invoice_no`, `total`, `payment_method` (`cash`/`qris`),
  `cash_received`, `change`, `cashier_user_id`, `shift_id`, `order_type`,
  `bill_name`; pembatalan: `deleted_at`, `cancelled_by_user_id`, `cancel_reason`.
- **`transaction_items`** — `product_id`, `product_name` & `price_at_sale`
  (salinan, supaya struk lama tetap benar), `qty`, `subtotal`, `notes`.
  Sengaja tanpa rantai ke `products`.
- **`expenses`** — `shift_id` (kosong = pengeluaran owner), `user_id`,
  `description`, `amount` (total), `qty`, `category`; pembatalan seperti
  transaksi.
- **`open_bills`** — `name`, `shift_id`, `user_id`, `items` (JSON),
  `transaction_id` (terisi saat dibayar).

### Lokal saja (tidak disinkron)
- **`sync_state`** — penanda tarik terakhir per tabel.
- **`baris_tertahan`** — baris server yang ditolak database HP, dicoba ulang.

### Server saja
- **`perangkat`** — HP terdaftar: nama, model, status, shift yang dipegang,
  `terakhir_aktif`, `terakhir_tarik`, `jumlah_tertahan`.
- **`nomor_terakhir`**, **`percobaan_kunci`**, **`rahasia`** — pendukung nomor
  kasir, batas tebak kunci pemasangan, dan kunci pemasangan.

## 3. Kode izin

| Kode | Nama di aplikasi |
|---|---|
| `open_close_shift` | Buka & Tutup Shift *(bawaan kasir baru)* |
| `create_transaction` | Buat Transaksi *(bawaan kasir baru)* |
| `view_history` | Lihat Riwayat Lengkap (shift-shift yang sudah lewat) |
| `view_report` | Lihat Laporan |
| `view_all_shifts` | Lihat Shift Semua Kasir |
| `manage_products` | Kelola Produk |
| `manage_categories` | Kelola Kategori |

Owner selalu punya semuanya. Kelola Kasir, Daftar Perangkat, membuka menu
Riwayat, dan melihat shift sendiri **bukan izin** — itu hak paten.

## 4. Penjaga di server

Dijalankan sebagai trigger/RLS di Supabase (berkas di `supabase/`):

| Berkas | Isi |
|---|---|
| `rls.sql`, `perangkat_tegakkan.sql` | Hanya HP terdaftar & aktif yang boleh baca/tulis |
| `sync_urutan.sql` | Kolom `server_urut` untuk penanda tarik |
| `tolak_versi_lama.sql` | Kiriman yang lebih tua tidak menimpa; pembatalan satu arah |
| `kunci_kolom.sql` | Total, nominal, kas awal, jam shift, role tidak bisa diganti |
| `open_bill_kunci.sql` | Bill tidak bisa dibayar/dihapus dua kali |
| `shift_gabung.sql` | Shift dobel dari dua HP offline digabung ke yang pertama |
| `buang_sampah*.sql` | Produk/kategori terhapus dibuang permanen setelah semua HP menerimanya |

Urutan menjalankan semua berkas: [`supabase/URUTAN.md`](../supabase/URUTAN.md).

## 5. Migrasi

### Di HP (Drift)

`onUpgrade(from, to)` berisi blok `if (from < N && to >= N)` — aman walau
upgrade melompati banyak versi.

1. Ubah definisi tabel di `app_database.dart`, naikkan `schemaVersion`.
2. Tambah blok migrasi. Kolom baru: `m.addColumn(...)`, dicek dulu lewat
   `pragma_table_info` (lihat contoh v37/v42).
3. **Kolom baru di tabel yang disinkron** → kosongkan `sync_state.last_pulled_cursor`
   tabel itu supaya baris lama tertarik ulang dengan kolom barunya.
4. `dart run build_runner build --delete-conflicting-outputs`.
5. Tulis test migrasi (contoh: `test/data/migrasi_v41_test.dart`), lalu
   `flutter analyze` + `flutter test`.

> **Dilarang** `deleteTable` / drop & recreate untuk data asli. Pola itu hanya
> pernah dipakai di v10 saat data masih dummy.

### Di server

Buat berkas SQL **baru** (jangan ubah berkas lama yang sudah dijalankan),
aman dijalankan ulang, catat di `URUTAN.md`, dan cabut hak fungsi baru dari
`anon`. Test di `test/arsitektur/` mengecek dua hal terakhir. Berkasnya
dijalankan owner lewat SQL Editor Supabase.

## 6. Lokasi file database HP

`kasir_app.sqlite` di folder dokumen aplikasi (`getApplicationDocumentsDirectory()`).
Database dibuka di isolate latar supaya layar tidak tersendat.

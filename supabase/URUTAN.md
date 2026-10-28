# Urutan menjalankan berkas SQL

Server Supabase dibangun dari berkas-berkas di folder ini, dijalankan
**satu per satu lewat SQL Editor, sesuai urutan di bawah**. Setiap berkas
aman diulang.

Urutan ini **sudah dibuktikan** (28 Okt 2026): semua berkas dijalankan di
PostgreSQL 16 lokal dengan tiruan skema `auth`, `storage`, `cron`, dan
`extensions` milik Supabase, lalu hasilnya dicocokkan dengan DDL server asli:
132 kolom, 40 constraint, 44 indeks (+1 dari `username_huruf_kecil.sql`),
28 trigger, 22 fungsi, dan 32 policy — sama persis.

Yang perlu diperhatikan:

- **`rls.sql` dijalankan PALING AKHIR.** Isinya menyebut tabel `perangkat`,
  `rahasia`, `nomor_terakhir`, dan `percobaan_kunci` yang baru dibuat berkas
  sesudahnya — dijalankan di urutan commit-nya (no. 2), berkas ini gagal.
- **`perangkat_tarik.sql` sebelum `buang_sampah_tarik.sql`.** Fungsi buang
  sampah memakai kolom `terakhir_tarik`. PostgreSQL tidak memeriksa isi fungsi
  saat dibuat, jadi urutan terbalik tidak gagal — tapi fungsinya baru benar
  setelah kolomnya ada.
- `schema.sql` adalah skema AWAL, bukan skema lengkap. Skema lengkap = semua
  berkas di bawah, berurutan.
- `buang_sampah_tarik.sql` sebaiknya dijalankan setelah semua HP aktif memakai
  APK yang melapor `terakhir_tarik` (lihat kepala berkasnya).

Server baru juga butuh: ekstensi `pg_cron` dinyalakan (Database → Extensions)
sebelum `buang_sampah_jadwal.sql`, dan bucket Storage dibuat oleh
`storage.sql`.

| No | Berkas | Isi |
|---|---|---|
| 1 | `schema.sql` | Teras Inn POS — skema PostgreSQL (Supabase) |
| 2 | `storage.sql` | PENYIMPANAN GAMBAR PRODUK |
| 3 | `izin.sql` | IZIN — katalog dan sinkronisasi |
| 4 | `perangkat.sql` | DAFTAR PERANGKAT |
| 5 | `perangkat_tegakkan.sql` | MENYALAKAN PENEGAKAN DAFTAR PERANGKAT |
| 6 | `sync_urutan.sql` | URUTAN KEDATANGAN DI SERVER — menutup kebocoran data saat sinkron |
| 7 | `sync_urutan_perbaiki.sql` | PERBAIKAN SEKALI JALAN untuk `supabase/sync_urutan.sql` |
| 8 | `perangkat_shift.sql` | SIAPA YANG SEDANG MEMEGANG SHIFT |
| 9 | `buang_sampah.sql` | BUANG SAMPAH — hapus permanen data yang sudah dihapus dari aplikasi |
| 10 | `users_tanpa_deleted_at.sql` | USERS TANPA deleted_at |
| 11 | `buang_sampah_jadwal.sql` | JADWAL BUANG SAMPAH — tiap hari jam 00.00 WIB |
| 12 | `produk_pilihan.sql` | PILIHAN PRODUK — Pedas, Manis, Es |
| 13 | `produk_tanpa_barcode.sql` | PRODUK TANPA BARCODE |
| 14 | `transaksi_batal.sql` | PEMBATALAN TRANSAKSI — dicatat dan disimpan selamanya |
| 15 | `pengeluaran_batal.sql` | PEMBATALAN PENGELUARAN — sama seperti transaksi |
| 16 | `pengeluaran_tanpa_updated_by.sql` | PENGELUARAN TANPA updated_by_user_id |
| 17 | `kategori_terhapus.sql` | KATEGORI TERHAPUS — produk tidak boleh menunjuk kategori yang dihapus |
| 18 | `pengeluaran_kategori.sql` | KATEGORI BIAYA & JUMLAH PENGELUARAN |
| 19 | `pengeluaran_kategori_wajib.sql` | KATEGORI PENGELUARAN JADI WAJIB — data lama masuk "Bahan Baku" |
| 20 | `pengeluaran_tanpa_shift.sql` | PENGELUARAN OWNER — boleh tanpa shift |
| 21 | `salinan_nama_akun.sql` | SALINAN NAMA AKUN DI SHIFT, TRANSAKSI, DAN PENGELUARAN |
| 22 | `kategori_tampil.sql` | KATEGORI BISA DISEMBUNYIKAN DARI KASIR + IZIN KELOLA KATEGORI |
| 23 | `perangkat_model.sql` | MODEL & JENIS PERANGKAT DI DAFTAR PERANGKAT |
| 24 | `shift_kas_awal.sql` | KAS AWAL SHIFT |
| 25 | `open_bill.sql` | OPEN BILL |
| 26 | `nomor_nota.sql` | NOMOR NOTA PENDEK — NOMOR KASIR & KODE PERANGKAT |
| 27 | `open_bill_kunci.sql` | OPEN BILL — KUNCI BAYAR/HAPUS & PENJAGA STATUS AKHIR |
| 28 | `shift_pemegang_basi.sql` | PEMEGANG SHIFT YANG SUDAH DIAM TIDAK DIHITUNG LAGI |
| 29 | `tolak_versi_lama.sql` | TOLAK VERSI LAMA — server menyimpan versi TERBARU, bukan yang tiba |
| 30 | `perangkat_tarik.sql` | PERANGKAT_TARIK — pisahkan "HP masih dipakai" dari "HP sudah |
| 31 | `buang_sampah_tarik.sql` | BUANG SAMPAH — "centang biru" memakai terakhir_tarik |
| 32 | `kunci_kolom.sql` | KUNCI KOLOM — angka yang sudah tercatat tidak bisa diganti lewat |
| 33 | `perangkat_aman.sql` | PERANGKAT AMAN — kunci pemasangan tidak bisa ditebak, HP yang |
| 34 | `username_huruf_kecil.sql` | USERNAME UNIK TANPA PEDULI BESAR-KECIL HURUF (revisi QA C1, 28 Okt 2026) |
| 35 | `cabut_hak_sisa.sql` | CABUT HAK SISA (revisi QA C10, 28 Okt 2026) |
| 36 | `shift_gabung.sql` | SHIFT GABUNG — dua shift satu akun dari dua HP offline disatukan (revisi QA K9, 29 Okt 2026) |
| 37 | `rls.sql` | SISA PENGETATAN AKSES |

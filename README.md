# Kasir App — POS untuk Rumah Makan

Aplikasi Point of Sale (POS) berbasis Flutter untuk rumah makan kecil. Dibangun dengan database lokal (SQLite via Drift), tanpa ketergantungan server atau internet.

## Fitur Utama

- **Autentikasi dua peran** — Owner dan Kasir dengan PIN terenkripsi, sistem recovery code, dan rate limiting login
- **Manajemen produk** — Tambah/edit/hapus produk, kategori, barcode, dan pelacakan stok
- **Transaksi kasir** — Keranjang belanja, pembayaran Cash dan QRIS, animasi add-to-cart
- **Riwayat transaksi** — Filter per bulan, detail item per transaksi
- **Laporan harian & bulanan** — Grafik tren pendapatan, produk terlaris (pie chart), performa per karyawan
- **Export Excel** — Laporan dalam format `.xlsx` dengan 4 sheet: Ringkasan, Produk Terlaris, Daftar Transaksi, Per Karyawan
- **Manajemen karyawan** — Tambah/nonaktifkan kasir, atur izin akses, ganti PIN

## Tech Stack

| Komponen | Teknologi |
|----------|-----------|
| Framework | Flutter (Dart) |
| Database lokal | [Drift](https://drift.simonbinder.eu/) (SQLite ORM) |
| Grafik | [fl_chart](https://pub.dev/packages/fl_chart) |
| Export Excel | [excel](https://pub.dev/packages/excel) |
| Share file | [share_plus](https://pub.dev/packages/share_plus) |
| Keamanan PIN | [crypto](https://pub.dev/packages/crypto) (SHA-256 + salt) |
| Preferensi lokal | [shared_preferences](https://pub.dev/packages/shared_preferences) |

## Prasyarat

Pastikan sudah terinstall:

- [Flutter SDK](https://docs.flutter.dev/get-started/install) versi `^3.10.7`
- Dart SDK `^3.10.7` (sudah termasuk dalam Flutter)
- Android Studio / VS Code dengan Flutter extension
- Perangkat fisik atau emulator Android/iOS

Cek instalasi Flutter:
```bash
flutter doctor
```

## Cara Clone dan Menjalankan

### 1. Clone repository

```bash
git clone https://github.com/CessaChristian/kasir_app.git
cd kasir_app
```

### 2. Install dependencies

```bash
flutter pub get
```

### 3. Generate kode Drift (database)

File `app_database.g.dart` perlu di-generate sebelum bisa menjalankan aplikasi:

```bash
dart run build_runner build --delete-conflicting-outputs
```

> Jika ada perubahan pada schema database, jalankan perintah ini lagi.

### 4. Jalankan aplikasi

```bash
flutter run
```

Untuk build release APK:
```bash
flutter build apk --release
```

## Struktur Folder

```
lib/
├── app/
│   └── app_shell.dart          # Navigasi utama (bottom nav)
├── data/
│   ├── app_database.dart       # Schema & query database (Drift)
│   ├── app_database.g.dart     # Kode generated Drift (jangan diedit manual)
│   ├── db.dart                 # Singleton instance database
│   └── models/                 # Model data tambahan
├── features/
│   ├── auth/                   # Login, setup owner, recovery code
│   ├── dashboard/              # Halaman utama & ringkasan pendapatan hari ini
│   ├── history/                # Riwayat transaksi
│   ├── owner/                  # Manajemen karyawan & izin
│   ├── products/               # Manajemen produk & kategori
│   ├── report/                 # Laporan & export Excel
│   └── sales/                  # Halaman kasir & keranjang
├── shared/
│   ├── auth/session_manager.dart   # Manajemen sesi login
│   ├── constants/app_constants.dart
│   └── widgets/                # Widget reusable
├── utils/                      # Formatter, enkripsi
└── main.dart
```

## Setup Pertama Kali

Saat aplikasi pertama dijalankan:

1. Aplikasi akan mendeteksi belum ada akun **Owner**
2. Tampil halaman **Setup Owner** — isi username dan PIN (4–6 digit)
3. Simpan **recovery code** yang ditampilkan di tempat aman (digunakan jika lupa PIN)
4. Login dengan akun Owner
5. Tambah produk dan karyawan sesuai kebutuhan

## Catatan Pengembangan

- **Database lokal** — Semua data tersimpan di perangkat. Tidak ada sinkronisasi cloud. Backup manual disarankan.
- **Migrasi schema** — Perubahan struktur database dikelola secara incremental di `app_database.dart` (lihat fungsi `migration`).
- **Kode generated** — File `*.g.dart` di-generate oleh `build_runner` dan tidak perlu di-commit jika menggunakan CI/CD (tambahkan ke `.gitignore` sesuai kebutuhan).

## Lisensi

MIT License — bebas digunakan dan dimodifikasi.

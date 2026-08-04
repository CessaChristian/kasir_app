# Getting Started — Setup & Menjalankan Kasir App

Panduan ini untuk **menyiapkan project di komputermu dari nol** sampai aplikasi
berjalan di emulator/HP. Ditulis untuk pemula, jadi setiap langkah dijelaskan
*kenapa*-nya juga.

---

## 1. Prasyarat (yang harus diinstall dulu)

| Alat | Keterangan |
|---|---|
| **Flutter SDK** `^3.10.7` | Sudah termasuk Dart. [Panduan instalasi resmi](https://docs.flutter.dev/get-started/install). |
| **Android Studio** atau **VS Code** | Untuk editor + emulator Android. Pasang plugin/extension **Flutter**. |
| **Git** | Untuk clone & kerja versi kode. |
| **Emulator Android** atau **HP fisik** | Tempat menjalankan aplikasi. |

Setelah install Flutter, jalankan:

```bash
flutter doctor
```

Perintah ini mengecek apakah semua sudah beres. Perbaiki dulu item yang
ditandai ❌ (biasanya soal Android SDK / lisensi Android). Kalau butuh menerima
lisensi Android:

```bash
flutter doctor --android-licenses
```

---

## 2. Ambil kode & dependencies

```bash
# Clone repository
git clone https://github.com/CessaChristian/kasir_app.git
cd kasir_app

# Download semua package yang dibutuhkan (tercatat di pubspec.yaml)
flutter pub get
```

`flutter pub get` membaca `pubspec.yaml` lalu mengunduh semua library (drift,
fl_chart, dll.) ke cache lokal. Wajib dijalankan setiap kali `pubspec.yaml`
berubah.

---

## 3. Generate kode database (WAJIB) 🔑

Project ini memakai **Drift** (ORM SQLite). Sebagian kode database
**dibuat otomatis** oleh generator dan disimpan di file
`lib/data/app_database.g.dart`.

```bash
dart run build_runner build --delete-conflicting-outputs
```

- **Kenapa perlu?** File `.g.dart` berisi kelas-kelas hasil generate (misalnya
  `Product`, `ProductsCompanion`, class `_$AppDatabase`). Tanpa file ini, kode
  **tidak akan bisa di-compile**.
- **Kapan diulang?** Setiap kali kamu mengubah definisi tabel/skema di
  `lib/data/app_database.dart` (menambah tabel, menambah kolom, dsb.).
- **`--delete-conflicting-outputs`** artinya: kalau ada file hasil generate lama
  yang bentrok, timpa saja. Aman dipakai.

> File `app_database.g.dart` **ikut di-commit** ke Git di project ini, jadi
> kadang setelah `git pull` kamu tidak perlu generate ulang — kecuali skema
> berubah. Kalau ragu, jalankan saja perintah di atas; tidak berbahaya.

---

## 4. Jalankan aplikasi

Pastikan ada emulator menyala atau HP tersambung (`flutter devices` untuk cek),
lalu:

```bash
flutter run
```

Build release APK (untuk dipasang di HP tanpa kabel):

```bash
flutter build apk --release
```

---

## 5. Akun pertama (onboarding)

Saat aplikasi dibuka **pertama kali** (database masih kosong), akan muncul
**wizard onboarding**:

1. **Setup Owner** — isi *username* dan **PIN** (4–6 digit). Ini akun pemilik
   dengan akses penuh.
2. Aplikasi otomatis membuat **2 usaha**: **Teras Inn** (dine-in) dan
   **Thai Tea** (grab-and-go). (Keduanya *hardcode* di kode — lihat
   [features-overview.md](features-overview.md).)
3. **Recovery code** ditampilkan **sekali** — simpan baik-baik. Kode ini dipakai
   untuk reset PIN kalau owner lupa PIN.
4. Setelah itu kamu diarahkan ke halaman **Login**. Masuk pakai username + PIN
   owner.

Setelah login sebagai owner, kamu bisa menambah **kasir** lewat menu
**Kelola Kasir** (drawer). Kasir login dengan PIN masing-masing dan otomatis
membuka *shift*.

> **Reset dari awal:** kalau ingin mengulang onboarding, hapus data aplikasi
> (uninstall / clear data). Database SQLite tersimpan di folder dokumen aplikasi
> (`kasir_app.sqlite`).

---

## 6. Verifikasi bahwa semuanya sehat

Sebelum & sesudah mengerjakan sesuatu, pastikan project tetap sehat:

```bash
flutter analyze   # analisa statik — harus: "No issues found!"
flutter test      # jalankan semua test — harus: "All tests passed!"
```

Kedua perintah ini adalah **syarat wajib** sebelum menyatakan sebuah pekerjaan
selesai (lihat [contributing.md](contributing.md)).

---

## 7. Troubleshooting umum

| Gejala | Penyebab & solusi |
|---|---|
| Error `_$AppDatabase` / class dari `.g.dart` tidak ditemukan | Belum generate. Jalankan langkah **3** (`build_runner`). |
| Perubahan skema tidak muncul | Belum generate ulang setelah ubah `app_database.dart`. Ulangi langkah **3**. |
| Halaman stuck loading / data kosong terus | Biasanya belum ada **usaha aktif** (belum login) atau database belum ter-*wire*. Pastikan sudah login. |
| `flutter pub get` gagal | Cek koneksi internet & versi Flutter (`flutter --version`) sesuai `^3.10.7`. |
| Emulator tidak terdeteksi | `flutter devices` untuk cek; nyalakan emulator dari Android Studio (Device Manager). |
| Ingin lihat isi database | Database = file SQLite di folder dokumen app. Bisa dibuka dengan DB Browser for SQLite (ambil file dari device via `adb`). |

Kalau masih mentok, baca [architecture.md](architecture.md) untuk paham alur
data, atau tanyakan ke tim.

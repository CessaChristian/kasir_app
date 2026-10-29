# Getting Started — Setup & Menjalankan Kasir App

Panduan **menyiapkan project dari nol** sampai aplikasi berjalan di HP.

---

## 1. Prasyarat

| Alat | Keterangan |
|---|---|
| **Flutter SDK** (Dart `^3.10.7`) | [Panduan instalasi resmi](https://docs.flutter.dev/get-started/install). |
| **Android Studio** atau **VS Code** | Editor + emulator Android, plugin **Flutter**. |
| **Git** | Untuk clone & versi kode. |
| **Emulator Android** atau **HP fisik** | Android 7 (API 24) ke atas. |
| **Internet saat build pertama** | `sqlite3` mengunduh SQLite saat build. |

```bash
flutter doctor
flutter doctor --android-licenses   # kalau diminta
```

## 2. Ambil kode & dependencies

```bash
git clone https://github.com/CessaChristian/kasir_app.git
cd kasir_app
flutter pub get
```

## 3. Generate kode database (WAJIB)

```bash
dart run build_runner build --delete-conflicting-outputs
```

Membuat `lib/data/app_database.g.dart` (kode Drift). Ulangi setiap skema di
`app_database.dart` berubah. File ini ikut di-commit.

## 4. Server Supabase

Alamat & kunci publik server sudah tertulis di
`lib/data/supabase/supabase_config.dart` — tidak perlu `--dart-define`.

Untuk server **baru**, jalankan semua berkas di `supabase/` lewat **SQL Editor**
Supabase, berurutan sesuai [`supabase/URUTAN.md`](../supabase/URUTAN.md).
Sebelum `buang_sampah_jadwal.sql`, nyalakan ekstensi `pg_cron`
(Database → Extensions).

## 5. Jalankan aplikasi

```bash
flutter run                    # debug
flutter build apk --release    # APK rilis
```

**APK rilis** ditandatangani dengan kunci di folder `teras-inn-kunci/` (tidak
ada di Git, cadangannya disimpan owner). Tanpa folder itu build rilis gagal
dengan pesan yang menjelaskannya. APK yang ditandatangani kunci berbeda **tidak
bisa dipasang di atas** versi lama — datanya harus dihapus dulu.

## 6. HP pertama

Penyiapan pertama **wajib online**:

1. **Setup Owner** — username (huruf kecil) + PIN 6 digit.
2. **Recovery code** ditampilkan **sekali** — simpan baik-baik.
3. Login sebagai owner. Tambah kasir lewat **Profil → Kelola Kasir**.

**HP berikutnya** menampilkan **Daftarkan Perangkat** dan meminta **kunci
pemasangan**. Kunci itu dibuat owner sekali di Supabase (SQL Editor, perintahnya
ada di kepala `supabase/perangkat.sql` — kuncinya sengaja tidak ditulis di repo)
dan bisa diganti kapan saja tanpa memengaruhi HP yang sudah terdaftar.
Daftar HP dikelola di **Profil → Perangkat Terdaftar**.

## 7. Verifikasi

```bash
flutter analyze   # harus: No issues found!
flutter test      # harus: All tests passed!
```

## 8. Troubleshooting

| Gejala | Penyebab & solusi |
|---|---|
| `_$AppDatabase` / class `.g.dart` tidak ditemukan | Jalankan langkah **3**. |
| Build rilis gagal "key.properties tidak ditemukan" | Folder `teras-inn-kunci/` belum ada — minta cadangannya ke owner. |
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | Tanda tangan beda dengan APK terpasang (debug vs rilis). Pasang jenis yang sama, atau hapus aplikasi lama. |
| Layar "Perlu internet" saat pertama dibuka | Server tak terjangkau — cek internet. Penyiapan pertama memang wajib online. |
| Data HP lain tidak muncul | Tarik layar ke bawah untuk sinkron, atau cek **Perangkat Terdaftar** (HP bermasalah diberi peringatan). |
| Ingin lihat isi database | APK debug: `adb exec-out run-as id.terasinn.kasir cat app_flutter/kasir_app.sqlite > db.sqlite`. |

# Kasir App — Aplikasi POS Multi-Business

Aplikasi **Point of Sale (POS)** berbasis **Flutter** untuk usaha F&B kecil.
Berjalan **local-first** (semua data di perangkat, tanpa server/internet) dan
dirancang menangani **beberapa usaha dalam satu aplikasi** — saat ini
**Teras Inn** (rumah makan / dine-in) dan **Thai Tea** (minuman / grab-and-go).

> **Status:** Phase 1 (local-only) aktif. Arsitektur sudah disiapkan untuk
> Phase 2 (sinkronisasi cloud) namun sync-nya belum dikerjakan.
> `flutter analyze` bersih, **41 test lulus**.

---

## ✨ Fitur Utama

- **Multi-business** — satu aplikasi menangani 2 usaha; owner bisa berpindah usaha, data terpisah otomatis per usaha.
- **Autentikasi 2 peran** — Owner & Kasir dengan **PIN** (di-hash PBKDF2), *recovery code* untuk owner, dan *rate limiting* login.
- **Onboarding** — wizard setup akun owner pertama + seed 2 usaha otomatis.
- **Manajemen produk** — produk, kategori, barcode, pelacakan stok, opsi level pedas, foto produk.
- **Kasir (POS)** — keranjang, pembayaran **Cash & QRIS**, tipe pesanan (dine-in / take away / delivery), struk.
- **Shift** — kasir otomatis membuka shift saat login & menutupnya saat logout; owner memantau lewat halaman **Pantau Shift**.
- **Riwayat transaksi** — filter, detail item, hapus transaksi (soft-delete + kembalikan stok).
- **Laporan** — harian & bulanan, grafik tren, produk terlaris, performa per kasir, **export Excel**.
- **Pengeluaran** — catat pengeluaran per shift.
- **Manajemen usaha & kasir** — kelola kasir + izin akses, profil usaha, mode device.

## 🧰 Tech Stack

| Komponen | Teknologi |
|---|---|
| Framework | Flutter (Dart, SDK `^3.10.7`) |
| Database lokal | [drift](https://drift.simonbinder.eu/) `^2.22` (SQLite ORM) + `sqlite3_flutter_libs` |
| ID & format | `uuid`, `intl` (locale `id_ID`) |
| Grafik | [fl_chart](https://pub.dev/packages/fl_chart) |
| Keamanan PIN | `crypto` (PBKDF2-HMAC-SHA256 + salt) |
| Preferensi lokal | `shared_preferences` |
| Export / share | `excel`, `share_plus` |
| Gambar | `image_picker` |
| Codegen (dev) | `drift_dev`, `build_runner`, `flutter_lints`, `flutter_launcher_icons` |

## 📱 Platform

Target utama **Android** (dan iOS). Folder `web/`, `linux/`, `macos/`,
`windows/` masih berupa *scaffolding* bawaan Flutter dan belum jadi fokus.

---

## 🚀 Quick Start

Butuh [Flutter SDK](https://docs.flutter.dev/get-started/install) `^3.10.7`.
Cek dulu: `flutter doctor`.

```bash
# 1. Clone
git clone https://github.com/CessaChristian/kasir_app.git
cd kasir_app

# 2. Install dependencies
flutter pub get

# 3. Generate kode database (Drift) — WAJIB sebelum run pertama kali
dart run build_runner build --delete-conflicting-outputs

# 4. Jalankan (pastikan ada emulator/device aktif)
flutter run
```

> ℹ️ Langkah **build_runner** membuat file `lib/data/app_database.g.dart`
> (kode Drift). Ulangi perintah tersebut setiap kali skema database di
> `lib/data/app_database.dart` berubah.

Panduan setup lengkap + akun pertama ada di
**[docs/getting-started.md](docs/getting-started.md)**.

## ✅ Verifikasi (wajib sebelum menyatakan "selesai")

```bash
flutter analyze   # harus: No issues found!
flutter test      # harus: All tests passed!
```

---

## 🗂️ Struktur Folder (ringkas)

```
lib/
├── app/            # AppShell (navigasi) + AppTheme (tema per usaha)
├── data/           # Database (Drift): schema, query, BusinessContext, wiring db
├── features/       # Fitur per modul: auth, business, dashboard, products,
│                   #   sales, history, report, reports, shift, expenses,
│                   #   owner, onboarding, settings
├── shared/         # Widget/konstanta/auth (SessionManager) yang dipakai lintas fitur
├── utils/          # Formatter, kripto (PBKDF2), helper
└── main.dart       # Entry point + routing berdasarkan status login
test/               # Unit & integration test (41 test)
docs/               # Dokumentasi project (baca di bawah)
```

## 📚 Dokumentasi Lengkap

Mulai dari sini kalau kamu baru bergabung — baca berurutan:

1. **[docs/getting-started.md](docs/getting-started.md)** — instalasi, run, akun pertama, troubleshooting.
2. **[docs/architecture.md](docs/architecture.md)** — peta arsitektur & pola-pola kunci.
3. **[docs/database-schema.md](docs/database-schema.md)** — tabel, relasi, dan migrasi database.
4. **[docs/features-overview.md](docs/features-overview.md)** — apa saja fitur yang sudah dibangun.
5. **[docs/code-style.md](docs/code-style.md)** — konvensi kode & penamaan.
6. **[docs/contributing.md](docs/contributing.md)** — cara kerja tim, commit, & menambah fitur.

Indeks lengkap: **[docs/README.md](docs/README.md)**.

## 📄 Lisensi

**Proprietary / privat.** Hak cipta pemilik project. Kode ini **tidak** untuk
didistribusikan atau digunakan ulang secara publik tanpa izin.

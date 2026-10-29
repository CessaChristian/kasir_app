# Kasir App — Teras Inn POS

Aplikasi **Point of Sale (POS)** berbasis **Flutter** untuk **Teras Inn**
(rumah makan / kedai kopi).

Berjalan **local-first**: semua data disimpan di HP, jadi kasir tetap bisa
berjualan saat internet mati. Begitu online, data disinkronkan ke server
**Supabase** sehingga beberapa HP (kasir & owner) melihat data yang sama.

> Verifikasi wajib sebelum menyatakan pekerjaan selesai:
> `flutter analyze` bersih dan `flutter test` lulus semua.

---

## ✨ Fitur Utama

- **Pendaftaran perangkat** — HP baru harus didaftarkan owner (kunci pemasangan).
  Owner bisa ganti nama, mencabut, memulihkan, atau melupakan HP.
- **Akun & PIN** — Owner & Kasir, PIN 6 digit (PBKDF2), username huruf kecil,
  penguncian bertahap saat salah PIN, *recovery code* untuk owner.
- **Shift** — dibuka manual dengan **kas awal**, bisa dipegang beberapa HP,
  kas akhir dihitung otomatis, tutup shift wajib online.
- **Kasir (POS)** — keranjang, opsi pedas/manis/es, Dine In / Delivery,
  bayar **Tunai & QRIS**, struk di layar, nomor nota per HP.
- **Open Bill** — simpan pesanan dulu, bayar belakangan.
- **Riwayat** — per tanggal, cari nota/bill/menu, pembatalan dengan alasan.
- **Pengeluaran** — kasir mencatat dalam shift; owner boleh tanpa shift.
- **Laporan** — periode bebas, grafik, produk terlaris, yang dibatalkan,
  unduh **PDF / Excel** (simpan ke HP atau bagikan).
- **Riwayat & Detail Shift** — rekap per shift (Cash/QRIS, kas awal/akhir).
- **Kelola Kasir & Hak Akses** — 7 izin yang bisa diatur per kasir.
- **Sinkron otomatis** — tiap 5 menit, sesudah aksi penting, atau tarik layar.

Belum ada: **cetak struk ke printer Bluetooth** (tombolnya sudah tampil, belum
berfungsi).

## 🧰 Tech Stack

| Komponen | Teknologi |
|---|---|
| Framework | Flutter (Dart SDK `^3.10.7`) |
| Database HP | [drift](https://drift.simonbinder.eu/) `^2.35` + `sqlite3` `^3.4` (SQLite dibawa lewat build hook) |
| Server | Supabase (PostgreSQL + RLS + Storage) lewat `supabase_flutter` |
| Brankas HP | `flutter_secure_storage` (identitas perangkat, tiket login server) |
| Laporan | `pdf`, `excel`, `share_plus` |
| Foto produk | `image_picker` + `flutter_image_compress` |
| Lain-lain | `uuid`, `intl` (`id_ID`), `crypto`, `shared_preferences`, `device_info_plus` |
| Dev | `drift_dev`, `build_runner`, `flutter_lints`, `flutter_launcher_icons` |

## 📱 Platform

Target utama **Android** (minSdk 24). Folder `ios/`, `web/`, `linux/`,
`macos/`, `windows/` masih bawaan Flutter dan belum disiapkan untuk rilis.

---

## 🚀 Quick Start

```bash
git clone https://github.com/CessaChristian/kasir_app.git
cd kasir_app
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # kode Drift
flutter run
```

Server Supabase dibangun dari berkas di `supabase/` — urutannya ada di
**[supabase/URUTAN.md](supabase/URUTAN.md)**. Panduan lengkap:
**[docs/getting-started.md](docs/getting-started.md)**.

## 🗂️ Struktur Folder (ringkas)

```
lib/
├── app/        # AppShell, kerangka owner/kasir, penjaga perangkat, tema
├── data/       # Drift (skema & query), sinkron, Supabase, perangkat
├── features/   # auth, dashboard, expenses, history, onboarding, open_bill,
│               #   owner, perangkat, products, profil, report, sales, shift
├── shared/     # SessionManager, aturan username, UI & widget bersama
├── utils/      # formatter, kripto, pesan galat
└── main.dart   # inisialisasi + alur layar awal
supabase/       # berkas SQL server + URUTAN.md
test/           # unit, widget, dan test arsitektur
docs/           # dokumentasi
```

## 📚 Dokumentasi

1. **[docs/getting-started.md](docs/getting-started.md)** — instalasi, server, HP pertama.
2. **[docs/architecture.md](docs/architecture.md)** — peta kode, sinkron, keamanan.
3. **[docs/database-schema.md](docs/database-schema.md)** — tabel, izin, migrasi.
4. **[docs/features-overview.md](docs/features-overview.md)** — fitur & izinnya.
5. **[docs/code-style.md](docs/code-style.md)** — konvensi kode.
6. **[docs/contributing.md](docs/contributing.md)** — alur kerja & Definition of Done.

## 📄 Lisensi

**Proprietary / privat.** Hak cipta pemilik project. Kode ini **tidak** untuk
didistribusikan atau digunakan ulang secara publik tanpa izin.

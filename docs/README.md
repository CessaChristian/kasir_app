# Dokumentasi Kasir App

Selamat datang! 👋 Folder ini berisi dokumentasi lengkap project **Kasir App**
(aplikasi POS multi-business berbasis Flutter). Dokumentasi ini ditujukan
terutama untuk **anggota tim baru** agar cepat paham apa yang sedang kita
kerjakan dan standar yang kita pakai.

Ditulis dengan asumsi pembaca **masih pemula Flutter/Dart** — jadi banyak
istilah dijelaskan dari dasar. Kalau kamu sudah berpengalaman, langsung
lompat ke bagian yang kamu butuhkan.

## Urutan baca yang disarankan

| # | Dokumen | Isi singkat |
|---|---|---|
| 1 | [getting-started.md](getting-started.md) | Cara install, menjalankan app, membuat akun pertama, dan troubleshooting. **Mulai di sini.** |
| 2 | [architecture.md](architecture.md) | Peta besar kode: lapisan, pola kunci (multi-business, permission, keamanan), dan aturan yang tak boleh dilanggar. |
| 3 | [database-schema.md](database-schema.md) | Semua tabel database, relasinya, kolom sync, dan cara melakukan migrasi. |
| 4 | [features-overview.md](features-overview.md) | Daftar fitur yang sudah jadi + alur & izin (permission) tiap fitur. |
| 5 | [code-style.md](code-style.md) | Konvensi penamaan, gaya kode, komentar dartdoc, dan lint. |
| 6 | [contributing.md](contributing.md) | Workflow git tim, format commit, cara menambah fitur/tabel/izin, dan Definition of Done. |

## Folder lain di `docs/`

- **[research/](research/)** — catatan riset aplikasi POS pembanding (Kasir Pintar
  Pro, Moka POS) + pola multi-business & grab-and-go. Dibaca sebelum membangun
  fitur POS baru (lihat [contributing.md](contributing.md)).

> **Catatan:** ada file kerja internal (`CLAUDE.md` dan `docs/superpowers/`) yang
> **sengaja tidak dimasukkan ke Git** (ada di `.gitignore`). Jadi kalau kamu
> tidak melihatnya setelah clone, itu normal.

## Prinsip project (ringkas)

- **Local-first, sync-ready.** Semua data di perangkat sekarang (Phase 1), tapi
  setiap tabel sudah menyimpan kolom yang dibutuhkan untuk sinkronisasi cloud
  nanti (Phase 2). Jangan bikin tabel baru tanpa kolom sync — detailnya di
  [database-schema.md](database-schema.md).
- **Multi-business.** Hampir semua data "milik" salah satu usaha. Kode sudah
  otomatis memfilter data sesuai usaha yang sedang aktif — lihat
  [architecture.md](architecture.md).
- **Riset dulu, baru bangun.** Sebelum membuat fitur POS baru, lihat bagaimana
  Kasir Pintar Pro / Moka POS melakukannya (folder `research/`).
- **Selalu terverifikasi.** Sebuah perubahan dianggap selesai hanya setelah
  `flutter analyze` bersih dan `flutter test` lulus.

# Dokumentasi Kasir App

Selamat datang! 👋 Folder ini berisi dokumentasi project **Kasir App** —
aplikasi POS Teras Inn berbasis Flutter. Ditujukan untuk **anggota tim baru**
supaya cepat paham apa yang sedang dikerjakan dan standar yang dipakai.

Ditulis dengan asumsi pembaca **masih pemula Flutter/Dart** — jadi banyak
istilah dijelaskan dari dasar.

## Urutan baca yang disarankan

| # | Dokumen | Isi singkat |
|---|---|---|
| 1 | [getting-started.md](getting-started.md) | Install, menjalankan app, menyiapkan server & HP pertama. **Mulai di sini.** |
| 2 | [architecture.md](architecture.md) | Peta kode, alur layar awal, sinkron, izin, keamanan, aturan yang tak boleh dilanggar. |
| 3 | [database-schema.md](database-schema.md) | Tabel HP & server, kode izin, cara migrasi. |
| 4 | [features-overview.md](features-overview.md) | Fitur yang sudah jadi + izin tiap fitur. |
| 5 | [code-style.md](code-style.md) | Konvensi penamaan, gaya kode, komentar. |
| 6 | [contributing.md](contributing.md) | Alur git, format commit, menambah fitur/tabel/izin, Definition of Done. |

## Folder lain

- **[research/](research/)** — riset POS pembanding (Kasir Pintar Pro, Moka POS).
  Dibaca sebelum membangun fitur POS baru. Catatan multi-business di sana
  tinggal sejarah — aplikasi sekarang hanya untuk satu usaha.
- **[../supabase/](../supabase/)** — berkas SQL server. Urutan menjalankannya:
  [URUTAN.md](../supabase/URUTAN.md).

> **Catatan:** ada file kerja internal (`CLAUDE.md`, `INSTRUCTION.md`,
> `docs/superpowers/`) yang **sengaja tidak masuk Git**. Kalau tidak terlihat
> setelah clone, itu normal.

## Prinsip project (ringkas)

- **Local-first + sinkron.** HP tetap bisa berjualan tanpa internet; data
  dikirim ke Supabase saat online. Tabel yang disinkron wajib punya kolom
  sinkron — detailnya di [database-schema.md](database-schema.md).
- **Server tidak percaya HP begitu saja.** Aturan penting (versi terbaru menang,
  angka yang tidak boleh diubah, gabung shift) dijaga juga di server.
- **Riset dulu, baru bangun.** Fitur POS baru mengacu cara Kasir Pintar Pro /
  Moka POS.
- **Selalu terverifikasi.** Selesai = `flutter analyze` bersih + `flutter test`
  lulus, dan perubahan yang menyentuh layar dicoba di HP.

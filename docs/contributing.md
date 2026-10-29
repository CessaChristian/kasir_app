# Panduan Kontribusi

Dokumen ini menjelaskan **cara kerja tim**: alur git, format commit, cara
menambah sesuatu ke project, dan kapan sebuah pekerjaan dianggap **selesai**.

---

## 1. Alur Git (workflow tim)

Kita bekerja dengan **branch terpisah per orang**, dan `main` sebagai branch
**stabil/integrasi** (hanya berisi kode yang sudah beres & terverifikasi).

```
main          ← branch stabil. Kode yang sudah lolos analyze + test.
 ├── cessa    ← branch kerja Cessa
 └── <teman>  ← branch kerja anggota lain
```

> Nama branch di atas contoh — sesuaikan dengan nama anggota tim.

**Alur harian:**

1. Pastikan berada di branch pribadimu, dan tarik update terbaru dari `main`:
   ```bash
   git checkout <branch-pribadimu>
   git pull origin main          # ambil perubahan terbaru dari main
   ```
2. Kerjakan perubahan, lalu commit (lihat format §2).
3. Sebelum menggabungkan, **wajib** pastikan sehat:
   ```bash
   flutter analyze && flutter test
   ```
4. Gabungkan ke `main`:
   - Kalau pakai GitHub: buka **Pull Request** dari branch-mu ke `main`, minta
     anggota lain me-*review*, lalu merge.
   - Kalau merge lokal: pastikan sudah update dari `main` dulu untuk mengurangi
     konflik.
5. Anggota lain menarik `main` terbaru ke branch mereka (`git pull origin main`)
   agar tidak jauh tertinggal.

**Aturan penting:**
- Jangan push kode yang belum terverifikasi (belum lolos analyze + test) ke `main`.
- Sering-sering sinkron dengan `main` agar konflik kecil & mudah diselesaikan.
- **Jangan commit file kerja internal** — `CLAUDE.md`, `INSTRUCTION.md`, dan
  `docs/superpowers/` sudah ada di `.gitignore` dan sengaja tidak masuk repo.
- **Jangan pernah commit `teras-inn-kunci/`** (kunci tanda tangan rilis).
- File `app_database.g.dart` **ikut di-commit** (jangan hapus dari Git).

## 2. Format commit — Conventional Commits

Kita memakai gaya **[Conventional Commits](https://www.conventionalcommits.org/)**:

```
<tipe>(<scope opsional>): <deskripsi singkat>
```

- Ditulis dalam **kalimat perintah** (imperative), huruf kecil, tanpa titik akhir.
- Contoh nyata dari repo ini:
  ```
  feat(shift): shift satu akun dari dua HP offline digabung server
  fix(auth): login username harus persis huruf kecil
  fix(dasbor): angka lama tidak lagi menimpa yang baru
  chore(deps): drift 2.35 + sqlite3 3, sqlite3_flutter_libs dibuang
  docs: perbarui dokumentasi sesuai keadaan aplikasi
  ```

**Tipe yang dipakai:**

| Tipe | Untuk |
|---|---|
| `feat` | fitur baru |
| `fix` | perbaikan bug |
| `refactor` | rombak kode tanpa ubah perilaku |
| `test` | menambah/ubah test |
| `docs` | dokumentasi |
| `chore` | pekerjaan rutin (config, tooling, dsb.) |
| `style` | format/gaya (tanpa ubah logika) |

**Scope** (opsional, dalam kurung) menandai bagian yang disentuh, mis.
`feat(shift): ...`, `fix(sales): ...`.

## 3. Standing rule: riset dulu sebelum bikin fitur POS baru

Sebelum membangun fitur POS baru, **lihat dulu bagaimana Kasir Pintar Pro /
Moka POS melakukannya**. Catatan riset ada di `docs/research/`. Ini standar tim
agar fitur kita mengikuti pola POS yang sudah terbukti, bukan mengarang sendiri.

## 4. Cara menambah sesuatu

### Menambah fitur baru
1. Buat folder `lib/features/<nama_fitur>/` (struktur feature-first — lihat
   [code-style.md](code-style.md)).
2. Kalau butuh data: tambahkan query di `app_database.dart` atau buat
   *repository* di fitur tsb. Tegakkan izin di repository
   (`requireOwner()` / `requirePermission(kode)`), jangan hanya di tampilan.
3. Kalau butuh muncul di menu: tambahkan di kerangka/profil yang sesuai
   (`lib/app/kerangka_owner.dart`, `kerangka_kasir.dart`, `features/profil/`).
4. Tambahkan **test** bila logikanya penting.
5. Perbarui dokumentasi ([features-overview.md](features-overview.md)) bila perlu.

### Menambah tabel / kolom database
Ikuti langkah di **[database-schema.md](database-schema.md) §5** (naikkan
`schemaVersion`, tambah blok migrasi, sertakan kolom sync wajib, kosongkan
penanda tarik bila menambah kolom ke tabel yang disinkron, generate ulang
dengan `build_runner`). **Jangan pakai pola drop-table** untuk migrasi baru.

Kalau tabelnya juga ada di server: buat berkas SQL baru di `supabase/`, catat
di `URUTAN.md`, uji dulu di PostgreSQL lokal, lalu minta owner menjalankannya
di SQL Editor Supabase.

### Menambah izin (permission) baru
1. Tambahkan kode izin di `_seedPermissions()` (`app_database.dart`) — perlu
   migrasi yang men-*seed* ulang izin untuk HP lama.
2. Tambahkan definisinya (nama, keterangan, ikon) di
   `features/owner/models/ringkasan_kasir.dart` supaya muncul di Hak Akses.
3. Tegakkan di repository dengan `requirePermission(kode)`.
4. Bawaan kasir baru diatur `izinBawaanKasir`; izin yang tidak berlaku untuk
   owner diatur `SessionManager.izinBukanUntukOwner`.

## 5. Testing

- Test ada di folder `test/` (mengikuti struktur `lib/`).
- Untuk logika DB, pakai `AppDatabase.forTesting(NativeDatabase.memory())`
  (database di memori) — lihat contoh di `test/features/shift/`. Repository
  yang dijaga izin butuh sesi: `masukSebagaiOwner()` di `test/bantu/sesi.dart`.
- Perbaikan bug: test baru harus **terbukti gagal di kode lama** dulu.
- `test/arsitektur/` menjaga aturan lintas file (berkas SQL tercatat di
  URUTAN.md, fungsi server tertutup dari `anon`, izin tidak longgar, dll.).
- Jalankan: `flutter test`. Semua test harus lulus.

## 6. Definition of Done ✅

Sebuah pekerjaan **belum** boleh dianggap selesai / digabung ke `main` sebelum:

- [ ] `flutter analyze` → **No issues found!**
- [ ] `flutter test` → **All tests passed!**
- [ ] Kode di-*format* (`dart format .`).
- [ ] (Fitur POS baru) sudah mengacu riset di `docs/research/`.
- [ ] Dokumentasi terkait diperbarui bila perlu.
- [ ] Perubahan yang menyentuh layar/sinkron dicoba langsung di HP/emulator.
- [ ] Tidak menyertakan file internal yang di-*gitignore* (`CLAUDE.md`,
      `INSTRUCTION.md`, `docs/superpowers/`, `teras-inn-kunci/`).
- [ ] Sudah di-*review* (lewat Pull Request / diperiksa anggota lain) sebelum
      masuk `main`.

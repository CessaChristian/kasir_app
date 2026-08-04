# Konvensi Kode & Gaya

Tujuan konvensi ini: kode **mudah dibaca** dan terasa **konsisten** siapa pun
yang menulis. Kalau ragu, ikuti gaya kode di sekitar file yang kamu sentuh.

Acuan resmi: [Effective Dart](https://dart.dev/effective-dart) dan
[Style guide Flutter](https://github.com/flutter/flutter/blob/master/docs/contributing/Style-guide-for-Flutter-repo.md).

---

## 1. Penamaan (naming)

| Jenis | Gaya | Contoh |
|---|---|---|
| File & folder | `snake_case` (huruf kecil + garis bawah) | `shift_monitor_page.dart` |
| Class & Widget & enum | `PascalCase` (UpperCamelCase) | `ShiftMonitorPage`, `AuthSession` |
| Variabel, fungsi, parameter | `lowerCamelCase` | `activeBusinessId`, `hasPermission()` |
| Konstanta | `lowerCamelCase` (boleh awalan `k`) | `kSeedBusinesses`, `_activeBusinessKey` |
| Private (khusus dalam file/class) | awali `_` | `_load()`, `_ShiftRow` |

Beri nama yang **deskriptif**. Hindari singkatan tak jelas. Nama widget
sebaiknya mencerminkan komponen UI yang dibuatnya.

## 2. Struktur folder untuk fitur baru (feature-first)

Setiap fitur = satu folder di `lib/features/<nama_fitur>/` dengan subfolder
sesuai kebutuhan:

```
features/<nama_fitur>/
├── pages/          # layar penuh (…_page.dart)
├── widgets/        # potongan UI khusus fitur ini
├── sheets/         # bottom sheet (kalau ada)
├── repositories/   # akses data (query DB) khusus fitur ini
├── models/         # model data khusus fitur ini
└── services/       # logika/orkestrasi (kalau ada)
```

Kalau sebuah widget/util dipakai **lintas fitur**, pindahkan ke `lib/shared/`.

## 3. Bahasa & komentar

- **Komentar & dokumentasi ditulis dalam Bahasa Indonesia** (konsisten dengan
  kode yang sudah ada). Nama identifier (class/variabel) tetap Inggris.
- Pakai **dartdoc** `///` untuk mendokumentasikan class/method penting —
  jelaskan *kenapa* (niat/keputusan), bukan sekadar *apa*:
  ```dart
  /// Singleton untuk manajemen active business.
  /// Listen via [ListenableBuilder] untuk auto-rebuild saat business switch.
  class BusinessContext extends ChangeNotifier { ... }
  ```
- Komentar `//` untuk penjelasan singkat di dalam fungsi. Fokus pada bagian yang
  tidak jelas maksudnya (mis. alasan sebuah *guard* atau *workaround*).

## 4. Gaya penulisan Dart/Flutter

- **Format otomatis** sebelum commit:
  ```bash
  dart format .
  ```
- Pakai **`const`** sebisa mungkin untuk widget yang tidak berubah (hemat
  rebuild): `const SizedBox(height: 12)`.
- Utamakan **widget kecil & terpisah** daripada satu `build()` raksasa.
- Hindari `print()` di kode produksi (dilarang oleh lint).
- Untuk teks yang panjangnya dinamis di dalam `Row`, bungkus dengan
  `Expanded`/`Flexible` + `overflow: TextOverflow.ellipsis` agar tidak
  *overflow*.

## 5. Lint & analisa statik

Aturan lint diatur di **`analysis_options.yaml`** (memakai paket
`flutter_lints`). Kode **wajib lolos**:

```bash
flutter analyze   # target: "No issues found!"
```

Kalau suatu lint benar-benar perlu dimatikan di satu tempat, gunakan komentar
`// ignore: nama_lint` **dengan alasan yang jelas** — jangan mematikan lint
sembarangan.

## 6. Akses data

- UI mengambil data lewat `db` (AppDatabase) atau *repository* fitur — **jangan**
  menulis SQL mentah di dalam widget.
- Ingat: query data bisnis otomatis di-scope ke usaha aktif. Jangan membuat
  jalan pintas yang melewati aturan ini (lihat [architecture.md](architecture.md)).
- **Jangan pernah edit** `lib/data/app_database.g.dart` (hasil generate).

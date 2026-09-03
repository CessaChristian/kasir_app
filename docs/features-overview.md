# Overview Fitur

Daftar fitur yang **sudah dibangun**, beserta alur singkat dan **izin
(permission)** yang mengaturnya. Ini membantu kamu memahami "apa saja yang kita
kerjakan" dan di folder mana mencarinya.

Menu yang muncul untuk tiap user **difilter otomatis** sesuai izinnya
(`lib/app/app_shell.dart`). Owner melihat semua; kasir hanya yang diizinkan.

---

## Autentikasi & Onboarding — `features/auth`, `features/onboarding`

- **Onboarding (pertama kali):** wizard membuat **akun owner** + otomatis
  men-*seed* **2 usaha** (Teras Inn dine-in, Thai Tea grab-and-go) dalam 1
  transaksi atomik. Menampilkan **recovery code** sekali.
- **Login:** username + PIN. PIN diverifikasi PBKDF2; ada **rate limiting**
  (akun terkunci sementara bila gagal berkali-kali).
- **Recovery:** owner bisa reset PIN memakai recovery code (dengan lockout
  bertingkat bila salah berkali-kali).
- **Shift saat login:** kasir otomatis membuka shift; owner tidak.

## Dashboard — `features/dashboard`

Halaman utama setelah login. Menampilkan ringkasan (pendapatan hari ini,
breakdown Cash/QRIS, produk terlaris). Untuk **owner**
tampil kartu pintasan **"Pantau Shift Kasir"**; untuk **kasir** tampil kartu
**shift aktif**. *Izin:* semua user (`all`).

## Produk & Kategori — `features/products`

Tambah/edit/hapus produk & kategori, barcode, opsi level pedas,
dan foto produk. *Izin:* `manage_products`.

## Kasir / POS — `features/sales`

Alur penjualan: pilih produk → keranjang → pilih **tipe pesanan** (dine-in /
take away / delivery) → bayar **Cash** (dengan kembalian) atau **QRIS** → struk.
*Izin:* `create_transaction`.

## Riwayat — `features/history`

Daftar transaksi + detail item per transaksi. Bisa **hapus transaksi**
(soft-delete). *Izin:* `view_history`;
hapus butuh `delete_own_transaction` / `delete_any_transaction`.

## Laporan — `features/report`

Laporan **harian & bulanan**: total pesanan/pendapatan/pengeluaran, tren harian
(grafik), produk terlaris (pie chart), dan **performa per kasir**. Bisa
**export ke Excel** (`.xlsx`) lalu dibagikan. *Izin:* `view_report`.

## Pengeluaran — `features/expenses`

Catat pengeluaran yang terikat ke **shift** aktif (jadi hanya bisa dicatat saat
ada shift — yaitu oleh kasir). Kasir bisa mengedit pengeluarannya sendiri; owner
bisa mengedit milik siapa pun. *Izin:* `edit_own_expense` / `edit_any_expense`.

## Pantau Shift — `features/shift`

Halaman khusus (gaya Kasir Pintar Pro) untuk **memantau shift kasir**:

- Daftar shift **dikelompokkan per hari** (subheader), tiap baris menampilkan
  kasir, rentang waktu (atau badge "Berjalan"), jumlah transaksi, dan
  pendapatan.
- Ketuk sebuah shift → **detail shift**: kartu ringkasan (pendapatan, jumlah
  transaksi, Cash/QRIS, pengeluaran, kas bersih) + daftar **semua transaksi**
  shift itu (bisa diketuk → struk).
- Cakupan data: `view_all_shifts` → lihat semua kasir; tanpa itu → hanya shift
  sendiri.

*Izin:* `view_shift_reports` (owner selalu punya; bisa diberikan ke kasir).

> **Catatan Phase 2:** di pemakaian multi-device nyata, device owner belum punya
> data shift kasir sampai **sinkronisasi** aktif. Halaman ini otomatis benar
> begitu sync jalan.

## Manajemen (owner) — `features/owner`, `features/business`, `features/settings`

- **Kelola Kasir** (`manage_cashiers`) — tambah/nonaktifkan kasir, atur izin per
  kasir, ganti PIN.
- **Business** (`manage_business`) — daftar & detail usaha, edit profil
  (alamat/telepon/logo). Nama usaha *hardcode* (tidak bisa diubah dari UI).
- **Mode Device** (`manage_business`) — kunci device ke 1 usaha ("Cashier
  Mode").
- **Berpindah usaha** — lewat `BusinessSwitcher` di app bar (`switch_business`).
  Saat owner/kasir pindah usaha, `BusinessSwitchService` menutup shift lama &
  membuka shift baru bila perlu.

---

## Peran (role) singkat

| | Owner | Kasir |
|---|---|---|
| Akses | Semua fitur & semua usaha yang dimilikinya | Sesuai izin yang diaktifkan owner |
| Shift | **Tidak** menjalankan shift (memantau) | Otomatis buka shift saat login |
| Contoh izin default | semua | `create_transaction`, `view_history`, `open_close_shift`, `edit_own_expense`, `delete_own_transaction` |

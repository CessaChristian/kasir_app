# Overview Fitur

Daftar fitur yang **sudah dibangun**, alur singkatnya, dan **izin** yang
mengaturnya. Izin dicek di repository (bukan hanya di menu), lihat
[architecture.md](architecture.md) §5.

---

## Perangkat — `features/perangkat`, `data/perangkat`

- HP baru menampilkan **Daftarkan Perangkat** dan meminta **kunci
  pemasangan** (dibuat owner di Supabase, lihat
  [getting-started.md](getting-started.md) §6). Tebakan kunci dibatasi server.
- **Daftar Perangkat** (owner, wajib online): nama & model HP, terakhir aktif,
  data terakhir diterima, peringatan HP yang tidak menerima data. Aksi:
  Ganti Nama, Cabut, Pulihkan, Lupakan.
- HP yang dicabut langsung keluar dan tetap terkunci walau dibuka ulang offline.

## Akun & Onboarding — `features/auth`, `features/onboarding`

- **Onboarding** (wajib online): buat akun owner, lalu **recovery code**
  ditampilkan sekali.
- **Login**: username (huruf kecil, persis) + PIN 6 digit. Salah PIN →
  penundaan bertahap; 10 kali → terkunci sampai owner reset PIN.
- **Lupa PIN Owner**: reset memakai recovery code.

## Dashboard — `features/dashboard`

- **Owner**: pendapatan hari ini vs kemarin di jam yang sama, transaksi,
  pengeluaran, laba kotor, Tunai/QRIS, siapa yang sedang shift, produk terlaris.
- **Kasir**: ringkasan shift berjalan (atau shift terakhir) + tombol buka shift.

## Shift — `features/shift`

- **Buka shift** dengan kas awal; **tutup shift** (wajib online, tidak boleh
  ada open bill tersisa, tidak sedang dipegang HP lain).
- **Riwayat Shift** + **Detail Shift**: rincian Cash/QRIS × Dine In/Delivery,
  pengeluaran, kas awal & kas akhir, daftar transaksi & pengeluaran.
- *Izin:* `open_close_shift` (buka/tutup); shift sendiri = hak semua akun;
  shift kasir lain = `view_all_shifts`. Isi shift yang sudah selesai butuh
  `view_history` (owner selalu boleh).

## Kasir / POS — `features/sales`

Pilih produk (opsi pedas/manis/es bila ada) → keranjang → Dine In / Delivery →
**Tunai** (uang diterima & kembalian) atau **QRIS** → struk di layar.
Nomor nota `CS/<no. kasir>/<tgl buka shift>/<kode HP>-<urut>`.
*Izin:* `create_transaction`. Cetak struk ke printer **belum dibuat**.

## Open Bill — `features/open_bill`

Simpan pesanan dengan nama (mis. "Meja 3"), tambah item belakangan, bayar
nanti. Bill yang sedang dibayar/dihapus di HP lain ditolak lewat server.

## Riwayat — `features/history`

Transaksi dikelompokkan per tanggal; cari nomor nota, nama bill, atau nama menu;
filter Tunai/QRIS. **Pembatalan** wajib alasan dan dicatat siapa yang
membatalkan. Owner: transaksi apa pun; kasir: miliknya di shift yang berjalan.
*Cakupan:* owner semua; `view_history` milik sendiri; tanpa itu shift berjalan.

## Pengeluaran — `features/expenses`

Kasir mencatat pengeluaran dalam shift berjalan; owner boleh tanpa shift.
Kategori: Asset, Bahan Baku, Operasional Kedai; ada jumlah (qty). Pengeluaran
tidak diedit — yang salah dibatalkan lalu dicatat ulang.

## Laporan — `features/report`

Periode bebas (hari ini, kemarin, 7/30 hari, bulan, rentang). Pendapatan,
transaksi, rata-rata, pengeluaran, laba kotor, grafik (per jam/hari/bulan),
produk terlaris, yang dibatalkan. **Unduh PDF/Excel** (maks. 12 bulan) →
simpan ke folder Download (Android 10+) atau bagikan. *Izin:* `view_report`.

## Produk & Kategori — `features/products`

Produk: nama unik (maks. 40), harga (maks. 9 digit), kategori, foto (dikompres
WebP/JPEG), opsi pedas/manis/es. Kategori: ikon, bisa disembunyikan dari Kasir.
*Izin:* `manage_products`, `manage_categories`.

## Kelola Kasir & Hak Akses — `features/owner` (owner saja)

Buat kasir (username + PIN), aktif/nonaktifkan, reset PIN (sekaligus membuka
kunci), hapus, dan atur **hak akses** per kasir.

---

## Peran singkat

| | Owner | Kasir |
|---|---|---|
| Akses | Semua fitur | Sesuai izin dari owner |
| Navigasi tengah | Produk | Kasir |
| Shift | Memantau semua shift | Buka/tutup shift sendiri |
| Izin bawaan kasir baru | — | `open_close_shift`, `create_transaction` |
| Sesi berakhir | 15 menit tanpa sentuhan | 15 menit tanpa kabar |

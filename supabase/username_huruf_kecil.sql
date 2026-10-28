-- =====================================================================
--  USERNAME UNIK TANPA PEDULI BESAR-KECIL HURUF (revisi QA C1, 28 Okt 2026)
--
--  Jalankan lewat SQL Editor di dashboard Supabase. Aman diulang.
--
--  Aplikasi sekarang selalu menulis username huruf kecil dan memeriksa nama
--  kembar tanpa peduli besar-kecil huruf. Indeks ini penjaga terakhirnya:
--  dua HP yang sama-sama offline tidak bisa membuat `Budi` dan `budi`.
--
--  `users_username_key` (unik persis) tetap dibiarkan — tidak mengganggu.
--
--  Kalau gagal dengan "could not create unique index", berarti SUDAH ada dua
--  akun yang namanya cuma beda besar-kecil huruf. Cek dengan:
--    select lower(username), array_agg(username)
--      from public.users group by 1 having count(*) > 1;
-- =====================================================================

create unique index if not exists users_username_lower_unik
  on public.users (lower(username));

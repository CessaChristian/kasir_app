-- =====================================================================
--  IZIN FUNGSI BANTU UNTUK HP (perbaikan darurat 8 Nov 2026)
--
--  Jalankan lewat SQL Editor di dashboard Supabase SESUDAH
--  batal_shift_tutup.sql. Aman diulang.
--
--  ── MASALAH YANG DIPECAHKAN ──
--
--  versi_asli.sql dan kredensial_ketat.sql mencabut izin HP memanggil dua
--  fungsi bantu, padahal keduanya dipakai atas nama HP:
--  - kunci_cap_asli, oleh penjaga versi di setiap perubahan baris. Akibatnya
--    tutup shift, pembatalan, dan edit dari HP ditolak `permission denied`.
--  - hash_kredensial_sah, oleh CHECK kolom hash PIN. Akibatnya akun kasir
--    baru tidak bisa dibuat.
--  Data tidak hilang: tetap menunggu di HP dan terkirim sesudah berkas ini
--  dijalankan.
--
--  Keduanya hanya rumus tanpa rahasia, jadi aman dipanggil HP.
-- =====================================================================

grant execute on function public.kunci_cap_asli(text, uuid) to authenticated;
grant execute on function public.hash_kredensial_sah(text) to authenticated;

-- =====================================================================
--  PEMERIKSAAN SESUDAH DIJALANKAN
--
--    select has_function_privilege('authenticated',
--             'public.kunci_cap_asli(text, uuid)', 'execute'),
--           has_function_privilege('authenticated',
--             'public.hash_kredensial_sah(text)', 'execute');
--    -- true | true
-- =====================================================================

-- =====================================================================
--  BUANG SAMPAH — "centang biru" memakai terakhir_tarik
--
--  Jalankan lewat SQL Editor di dashboard Supabase. Aman diulang.
--
--  ⚠ JALANKAN HANYA SESUDAH:
--    1. supabase/perangkat_tarik.sql sudah dijalankan, DAN
--    2. SEMUA HP aktif memakai APK baru dan sudah sinkron sekali —
--       kolom "Data terakhir diterima" di halaman Perangkat sudah terisi
--       untuk setiap HP.
--  Kalau dijalankan lebih awal tidak merusak apa pun: HP yang kolomnya
--  masih kosong menahan pembuangan (lihat di bawah). Hanya saja tidak ada
--  yang terbuang sampai semua HP diperbarui.
--
--  ── YANG BERUBAH ──
--
--  Patokannya dulu `terakhir_aktif` — kapan HP terakhir memberi kabar.
--  Kabar itu sekarang juga datang dari sinkron yang gagal, dari HP yang
--  punya baris tertahan, dan dari sentuhan layar. HP seperti itu belum
--  menerima kabar hapusnya, tapi dulu dianggap sudah.
--
--  Sekarang patokannya `terakhir_tarik`: kapan HP terakhir selesai menarik
--  dengan BERSIH (supabase/perangkat_tarik.sql).
--
--  `min()` mengabaikan nilai kosong, jadi HP aktif yang kolomnya masih
--  kosong (APK lama, atau belum pernah menarik dengan bersih) harus
--  ditangani tersendiri: selama ada satu saja, batasnya kosong dan TIDAK
--  ADA yang terbuang. Kalau ragu, diam.
--
--  Selebihnya sama persis dengan supabase/buang_sampah.sql.
-- =====================================================================

create or replace function public.buang_sampah(
  p_jeda interval default interval '30 days'
)
returns table (tabel text, dibuang bigint)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_batas  timestamptz;
  v_jumlah bigint;
begin
  select case when bool_and(terakhir_tarik is not null)
              then min(terakhir_tarik) - interval '1 minute' end
    into v_batas
    from public.perangkat
   where status = 'aktif';

  -- Transaksi dan pengeluaran SENGAJA TIDAK dibuang: yang terhapus adalah
  -- yang DIBATALKAN, dan itu bukti untuk owner.

  delete from public.products
   where deleted_at is not null
     and server_urut < v_batas
     and deleted_at  < now() - p_jeda;
  get diagnostics v_jumlah = row_count;
  tabel := 'produk'; dibuang := v_jumlah; return next;

  delete from public.categories c
   where c.deleted_at is not null
     and c.server_urut < v_batas
     and c.deleted_at  < now() - p_jeda
     and not exists (select 1 from public.products p where p.category_id = c.id);
  get diagnostics v_jumlah = row_count;
  tabel := 'kategori'; dibuang := v_jumlah; return next;
end $$;

revoke all on function public.buang_sampah(interval) from public;
revoke all on function public.buang_sampah(interval) from anon, authenticated;

-- =====================================================================
--  PEMERIKSAAN — siapa yang menahan pembuangan:
--
--    select nama, status, terakhir_aktif, terakhir_tarik, jumlah_tertahan
--      from public.perangkat
--     order by terakhir_tarik nulls first;
--
--  HP aktif yang terakhir_tarik-nya kosong atau paling lama adalah yang
--  menahan. Perbarui aplikasinya, atau cabut di halaman Perangkat.
-- =====================================================================

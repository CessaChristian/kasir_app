-- =====================================================================
--  STATUS BILL MENURUT JAM SERVER (review C5/R6, 3 Nov 2026)
--
--  Jalankan lewat SQL Editor di dashboard Supabase SESUDAH
--  klaim_lima_menit.sql. Aman diulang. APK lama tetap jalan (tidak
--  memanggil fungsi ini).
--
--  ── MASALAH YANG DIPECAHKAN ──
--
--  Sebelum "Perbarui Bill", HP membaca baris open_bills lalu menilai
--  sendiri apakah klaim pembayaran masih berlaku — memakai JAM HP. HP yang
--  jamnya kecepatan 6 menit menganggap klaim HP lain yang baru 1 menit
--  sudah hangus, menyimpan perubahan, dan menampilkan "Bill diperbarui".
--  Server (yang benar) membuang perubahan itu diam-diam karena isi bill
--  terkunci selama diklaim: pesanan tambahan tidak pernah tertagih.
--
--  → HP bertanya ke fungsi ini. Berlaku-tidaknya klaim dinilai server
--    (klaim_berlaku, jam server); jam server ikut dikirim supaya sisa
--    waktu di pesan kasir juga dihitung dengan jam server.
--
--  Fungsinya hanya MEMBACA dan memakai hak pemanggil (security invoker):
--  yang tidak boleh membaca baris itu lewat select biasa juga tidak bisa
--  membacanya lewat sini.
-- =====================================================================

create or replace function public.status_bill(p_bill uuid)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
  select jsonb_build_object(
    'baris', (select to_jsonb(b) from public.open_bills b where b.id = p_bill),
    'klaim_berlaku', coalesce((
      select public.klaim_berlaku(b.klaim_tx, b.klaim_pada)
        from public.open_bills b
       where b.id = p_bill
    ), false),
    'sekarang', now()
  );
$$;

revoke all on function public.status_bill(uuid) from public, anon;
grant execute on function public.status_bill(uuid) to authenticated;

-- =====================================================================
--  PEMERIKSAAN SESUDAH DIJALANKAN
--
--    select public.status_bill(gen_random_uuid()) ->> 'klaim_berlaku';
--    -- false   (bill tidak ada; 'baris' bernilai null)
-- =====================================================================

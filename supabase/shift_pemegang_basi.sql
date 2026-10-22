-- =====================================================================
--  PEMEGANG SHIFT YANG SUDAH DIAM TIDAK DIHITUNG LAGI
--
--  Jalankan lewat SQL Editor di dashboard Supabase SEBELUM memasang APK
--  yang menampilkan nama perangkat pemegang shift. Aman diulang.
--
--  ── MASALAH YANG DIPECAHKAN ──
--
--  "Tutup shift" ditolak selama ada perangkat AKTIF lain yang tercatat
--  memegang shift itu (perangkat_shift.sql). Catatan itu hanya diperbarui
--  saat perangkat sinkron — perangkat yang mati, kehabisan baterai, atau
--  aplikasinya digeser dari riwayat tidak sempat melepasnya. Terbukti
--  2026-10-17: emulator yang mati sejak sehari sebelumnya menahan shift,
--  dan HP kasir tidak bisa menutupnya sama sekali.
--
--  Keputusan owner 2026-10-20: perangkat yang 15 menit tidak memberi kabar
--  dianggap tidak memegang shift lagi. HP-nya sendiri ikut menganggap
--  sesinya berakhir dan meminta login ulang (SessionManager.batasDiam —
--  angkanya HARUS sama dengan interval di bawah). Shift-nya TIDAK ditutup
--  otomatis; tetap kasir yang menutupnya.
--
--  HP yang aktif melapor tiap 5 menit (sinkron otomatis), jadi 15 menit
--  memberi ruang dua kali gagal sebelum dianggap diam.
-- =====================================================================

-- ---------------------------------------------------------------------
--  1. Jawaban ya/tidak — dipakai APK lama. Dengan batas waktu ini APK
--     lama pun langsung bisa menutup shift yang ditahan perangkat mati.
-- ---------------------------------------------------------------------
create or replace function public.shift_dipegang_perangkat_lain(p_shift_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.perangkat
    where shift_id = p_shift_id
      and id <> auth.uid()
      and status = 'aktif'
      and terakhir_aktif > now() - interval '15 minutes'
  );
$$;

revoke all on function public.shift_dipegang_perangkat_lain(uuid) from public;
grant execute on function public.shift_dipegang_perangkat_lain(uuid) to authenticated;

-- ---------------------------------------------------------------------
--  2. Siapa pemegangnya — dipakai APK baru supaya pesan penolakan bisa
--     menyebut perangkatnya ("masih dipakai di Emulator 2, aktif 3 menit
--     lalu").
--
--  `diam_detik` dihitung di server, bukan dari jam HP: jam HP bisa melenceng
--  beberapa menit, dan selisih itu langsung membuat pesannya keliru.
-- ---------------------------------------------------------------------
create or replace function public.pemegang_shift_lain(p_shift_id uuid)
returns table (nama text, diam_detik integer)
language sql
stable
security definer
set search_path = public
as $$
  select p.nama,
         greatest(0, extract(epoch from now() - p.terakhir_aktif))::integer
  from public.perangkat p
  where p.shift_id = p_shift_id
    and p.id <> auth.uid()
    and p.status = 'aktif'
    and p.terakhir_aktif > now() - interval '15 minutes'
  order by p.terakhir_aktif desc;
$$;

revoke all on function public.pemegang_shift_lain(uuid) from public;
grant execute on function public.pemegang_shift_lain(uuid) to authenticated;

-- =====================================================================
--  UJI — jalankan sesudah bagian di atas. Semuanya di dalam transaksi
--  yang dibatalkan di akhir, jadi data asli tidak berubah.
--
--  begin;
--    -- Pura-pura menjadi perangkat pertama.
--    select set_config('request.jwt.claims',
--      json_build_object('sub', (select id from public.perangkat
--                                order by dibuat_pada limit 1))::text, true);
--    set local role authenticated;
--
--    -- Ambil satu shift yang masih berjalan, dan beri perangkat KEDUA
--    -- shift itu dengan kabar terakhir 5 menit lalu.
--    reset role;
--    update public.perangkat
--       set shift_id = (select id from public.shifts
--                       where end_at is null and deleted_at is null limit 1),
--           terakhir_aktif = now() - interval '5 minutes',
--           status = 'aktif'
--     where id = (select id from public.perangkat
--                 order by dibuat_pada offset 1 limit 1);
--    set local role authenticated;
--
--    select 'segar 5 menit: harus true dan 1 baris' as uji,
--           public.shift_dipegang_perangkat_lain(s.id) as dipegang,
--           (select count(*) from public.pemegang_shift_lain(s.id)) as baris
--      from public.shifts s where end_at is null and deleted_at is null limit 1;
--
--    reset role;
--    update public.perangkat
--       set terakhir_aktif = now() - interval '16 minutes'
--     where id = (select id from public.perangkat
--                 order by dibuat_pada offset 1 limit 1);
--    set local role authenticated;
--
--    select 'diam 16 menit: harus false dan 0 baris' as uji,
--           public.shift_dipegang_perangkat_lain(s.id) as dipegang,
--           (select count(*) from public.pemegang_shift_lain(s.id)) as baris
--      from public.shifts s where end_at is null and deleted_at is null limit 1;
--  rollback;
-- =====================================================================

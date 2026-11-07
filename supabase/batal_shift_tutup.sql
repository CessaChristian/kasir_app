-- =====================================================================
--  PEMBATALAN KASIR DI SHIFT YANG SUDAH DITUTUP DIABAIKAN
--  (audit 6 Nov 2026 nomor 28, keputusan owner 7 Nov 2026)
--
--  Jalankan lewat SQL Editor di dashboard Supabase SESUDAH versi_asli.sql.
--  Aman diulang. Tidak perlu APK baru.
--
--  ── MASALAH YANG DIPECAHKAN ──
--
--  HP A menutup shift dan owner sudah melihat kas akhirnya. HP B yang belum
--  tahu membatalkan nota tunai Rp 100.000 di shift itu, lalu pembatalannya
--  terkirim: kas akhir shift yang sudah diserahkan berubah tanpa tanda apa
--  pun. Sama untuk pembatalan pengeluaran.
--
--  ── PERBAIKANNYA ──
--
--  Pembatalan oleh akun KASIR yang tiba saat shift-nya sudah ditutup
--  diabaikan, tanpa galat. Versi server dipertahankan dan capnya dimajukan,
--  jadi HP kasir menarik lagi transaksi itu sebagai transaksi biasa. Sesudah
--  itu hanya owner yang bisa membatalkannya. Pembatalan oleh owner selalu
--  diterima. Kasir tidak diberi pesan (keputusan owner).
--
--  Trigger `trg_<tabel>_sah_batal` berjalan SESUDAH `..._jaga_versi` (yang
--  selalu menerima pembatalan) dan SEBELUM `..._server_urut` (abjad).
-- =====================================================================

create or replace function public.tolak_batal_kasir_shift_tutup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (old.deleted_at is null and new.deleted_at is not null) then
    return new;
  end if;
  if not exists (
    select 1 from public.users u
     where u.id = new.cancelled_by_user_id and u.role = 'cashier'
  ) then
    return new;
  end if;
  if not exists (
    select 1 from public.shifts s
     where s.id = public.ujung_gabungan(old.shift_id)
       and s.end_at is not null
  ) then
    return new;
  end if;
  -- Dipertahankan, dan dimajukan supaya HP pengirim menarik versi ini.
  new := old;
  new.updated_at :=
    greatest(old.updated_at, now()) + interval '1 second';
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['transactions', 'expenses'] loop
    execute format('drop trigger if exists %I on public.%I',
                   'trg_'||t||'_sah_batal', t);
    execute format(
      'create trigger %I before update on public.%I '
      'for each row execute function public.tolak_batal_kasir_shift_tutup()',
      'trg_'||t||'_sah_batal', t);
  end loop;
end $$;

revoke all on function public.tolak_batal_kasir_shift_tutup()
  from public, anon, authenticated;

-- =====================================================================
--  PEMERIKSAAN SESUDAH DIJALANKAN
--
--    select count(*) from pg_trigger where tgname like 'trg_%_sah_batal';
--    -- 2
-- =====================================================================

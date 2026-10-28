-- =====================================================================
--  SHIFT GABUNG  —  dua shift yang dibuka akun yang sama di dua HP offline
--                   disatukan di server (revisi QA K9, 29 Okt 2026)
--
--  Jalankan lewat SQL Editor di dashboard Supabase. Aman diulang.
--  Butuh APK dengan skema HP v42 supaya HP yang shift-nya digabung ikut
--  pindah ke shift tujuan; APK lama tetap aman (lihat "HP LAMA" di bawah).
--
--  ── MASALAHNYA ──
--
--  Satu akun membuka shift di dua HP yang sama-sama offline:
--
--    08.00  HP-1 (offline): sari buka shift A, kas awal Rp100.000, jualan
--    08.03  HP-2 (offline): sari buka shift B, kas awal Rp100.000, jualan
--    09.00  keduanya online  →  server punya DUA shift berjalan untuk sari
--
--  Rekap terpecah dua, kas awal terhitung dua kali, dan tidak ada yang
--  menutupnya bersamaan. Penjagaan "shift dipegang perangkat lain" hanya
--  bekerja kalau HP-nya online.
--
--  ── PERBAIKANNYA ──
--
--  Shift yang DATANG BELAKANGAN ke server digabung ke shift yang datang
--  lebih dulu, kalau keduanya milik akun yang sama dan WAKTUNYA TUMPANG
--  TINDIH (keputusan owner):
--
--    1. Shift B ditandai `digabung_ke = A` dan `deleted_at` diisi. Kas
--       awalnya tidak dipakai — kas awal ikut shift A.
--    2. Transaksi, pengeluaran, dan open bill yang menyebut B — baik yang
--       datang sekarang maupun nanti dari HP-2 yang belum tahu — disimpan
--       dengan `shift_id = A`. `updated_at`-nya dimajukan supaya HP-2
--       menarik versi yang sudah pindah.
--    3. Kiriman HP-2 yang mengubah B sesudahnya (mis. menutupnya) tidak
--       menghidupkannya lagi.
--
--  Shift yang tidak tumpang tindih (HP-1 sudah tutup jam 12.00, HP-2 baru
--  buka jam 13.00) adalah dua shift yang sah dan TIDAK digabung.
--
--  ── HP LAMA ──
--
--  HP tanpa APK v42 tidak tahu kolom `digabung_ke`. Ia melihat shift B
--  terhapus dan memperlakukannya seperti shift yang ditutup dari perangkat
--  lain: kasir diminta membuka shift baru. Penjualannya tidak hilang —
--  tetap masuk shift A di server.
--
--  Nama trigger `trg_<tabel>_alih_shift` / `trg_shifts_gabung` berjalan
--  SEBELUM `trg_<tabel>_jaga_versi` (trigger BEFORE berurutan abjad).
-- =====================================================================

alter table public.shifts
  add column if not exists digabung_ke uuid references public.shifts(id);

-- ---------------------------------------------------------------------
--  Ujung rantai gabungan: A, kalau B digabung ke A. Rantai dibatasi
--  supaya data yang rusak tidak membuat trigger berputar selamanya.
-- ---------------------------------------------------------------------
create or replace function public.ujung_gabungan(p_shift uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_id  uuid := p_shift;
  v_ke  uuid;
begin
  for i in 1..10 loop
    select digabung_ke into v_ke from public.shifts where id = v_id;
    exit when v_ke is null;
    v_id := v_ke;
  end loop;
  return v_id;
end $$;

-- ---------------------------------------------------------------------
--  Shift baru yang tumpang tindih dengan shift akun yang sama → digabung.
-- ---------------------------------------------------------------------
create or replace function public.gabung_shift()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tujuan uuid;
  v_cap    timestamptz;
begin
  if tg_op = 'UPDATE' then
    -- 3. Yang sudah digabung tetap digabung. Versi server dipertahankan
    --    dan dimajukan supaya HP pengirim menariknya.
    --    Capnya melewati kiriman itu juga: kalau tidak, salinan HP pengirim
    --    tetap lebih baru dan kabar penggabungannya tidak pernah ditarik.
    if old.digabung_ke is not null then
      v_cap := greatest(new.updated_at, old.updated_at, now())
               + interval '1 second';
      new := old;
      new.updated_at := v_cap;
    end if;
    return new;
  end if;

  -- `upsert` menjalankan trigger INSERT juga untuk baris yang SUDAH ada
  -- (lalu beralih ke UPDATE). Yang digabung hanya kedatangan pertama.
  if exists (select 1 from public.shifts where id = new.id) then
    return new;
  end if;

  -- Dua HP yang tiba bersamaan tidak boleh sama-sama merasa "pertama".
  perform pg_advisory_xact_lock(hashtext('gabung_shift:' || new.user_id));

  select s.id into v_tujuan
    from public.shifts s
   where s.user_id = new.user_id
     and s.deleted_at is null
     and s.digabung_ke is null
     and s.start_at < coalesce(new.end_at, 'infinity')
     and new.start_at < coalesce(s.end_at, 'infinity')
   order by s.server_urut, s.id
   limit 1;

  if v_tujuan is not null then
    new.digabung_ke := v_tujuan;
    new.deleted_at := coalesce(new.deleted_at, now());
    new.updated_at := greatest(new.updated_at, now()) + interval '1 second';
  end if;
  return new;
end $$;

drop trigger if exists trg_shifts_gabung on public.shifts;
create trigger trg_shifts_gabung
  before insert or update on public.shifts
  for each row execute function public.gabung_shift();

-- ---------------------------------------------------------------------
--  Catatan yang menyebut shift yang sudah digabung → pindah ke tujuannya.
-- ---------------------------------------------------------------------
create or replace function public.alih_shift()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tujuan uuid;
begin
  if new.shift_id is null then
    return new;
  end if;
  v_tujuan := public.ujung_gabungan(new.shift_id);
  if v_tujuan is distinct from new.shift_id then
    new.shift_id := v_tujuan;
    new.updated_at := greatest(new.updated_at, now()) + interval '1 second';
  end if;
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['transactions','expenses','open_bills'] loop
    execute format('drop trigger if exists %I on public.%I',
                   'trg_'||t||'_alih_shift', t);
    execute format(
      'create trigger %I before insert or update on public.%I '
      'for each row execute function public.alih_shift()',
      'trg_'||t||'_alih_shift', t);
  end loop;
end $$;

-- Fungsi trigger tidak untuk dipanggil langsung lewat API.
revoke all on function public.ujung_gabungan(uuid)
  from public, anon, authenticated;
revoke all on function public.gabung_shift() from public, anon, authenticated;
revoke all on function public.alih_shift() from public, anon, authenticated;

-- =====================================================================
--  PEMERIKSAAN SESUDAH DIJALANKAN
--
--    select tgrelid::regclass as tabel, tgname
--      from pg_trigger
--     where tgname = 'trg_shifts_gabung' or tgname like 'trg_%_alih_shift'
--     order by 1;
--
--  Hasil yang benar: 4 baris (shifts, transactions, expenses, open_bills).
--
--  Shift yang pernah digabung:
--
--    select id, user_id, start_at, digabung_ke
--      from public.shifts where digabung_ke is not null;
-- =====================================================================

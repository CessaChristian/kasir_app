-- =====================================================================
--  OPEN BILL AMAN — pelunasan selalu diterima, isi terkunci selama dibayar,
--  klaim kedaluwarsa (revisi QA kedua S6 & S8, 30 Okt 2026)
--
--  Jalankan lewat SQL Editor di dashboard Supabase SESUDAH
--  open_bill_kunci.sql dan tolak_versi_lama.sql. Aman diulang.
--
--  ── MASALAH YANG DIPECAHKAN ──
--
--  S6. HP A mengubah isi bill pukul 10:00:30. HP B, yang jamnya telat
--      semenit, melunasinya — tercap 09:59:50. Penjaga versi menganggap
--      pelunasan itu versi lama dan membuangnya: bill terbuka lagi, padahal
--      terkunci klaim HP B, dan shift tidak bisa ditutup.
--      → Pelunasan oleh pemegang klaim selalu diterima; cap waktunya
--        dimajukan melewati versi lama, seperti pembatalan transaksi.
--
--  S8. HP A mengklaim lalu membayar; kiriman HP B (offline, basi) menambah
--      "nasi ×3" — diterima, dan bill lunas memuat pesanan yang tidak
--      dibayar. `klaim_tx` juga bisa dikosongkan lewat update biasa, dan
--      HP yang mati sesudah mengklaim mengunci bill selamanya.
--      → Isi & nama bill dikunci selama diklaim, lunas, atau dihapus.
--      → klaim_tx hanya berubah lewat klaim_bill / lepas_klaim_bill.
--      → Klaim kedaluwarsa sesudah 15 menit — sama dengan batas HP diam
--        (shift_pemegang_basi.sql): HP yang 15 menit tanpa kabar dianggap
--        mati.
--
--  ── KOLOM BARU ──
--    open_bills.klaim_pada   kapan klaim_tx dipasang.
-- =====================================================================

alter table public.open_bills add column if not exists klaim_pada timestamptz;

-- ---------------------------------------------------------------------
--  Klaim yang masih berlaku.
-- ---------------------------------------------------------------------
create or replace function public.klaim_berlaku(p_tx uuid, p_pada timestamptz)
returns boolean
language sql
stable
as $$
  select p_tx is not null
     and (p_pada is null or p_pada > now() - interval '15 minutes');
$$;

create or replace function public.klaim_bill(p_bill uuid, p_tx uuid)
returns text
language plpgsql
security invoker
set search_path = public
as $$
declare
  b    record;
  kena boolean;
begin
  perform set_config('teras.ubah_klaim', 'ya', true);
  update public.open_bills
     set klaim_tx = p_tx,
         klaim_pada = now()
   where id = p_bill
     and transaction_id is null
     and deleted_at is null
     and (klaim_tx = p_tx or not public.klaim_berlaku(klaim_tx, klaim_pada));
  -- Disimpan dulu: PERFORM di bawah menimpa FOUND.
  kena := found;
  perform set_config('teras.ubah_klaim', '', true);
  if kena then
    return 'ok';
  end if;

  select deleted_at into b from public.open_bills where id = p_bill;
  if not found then
    return 'belum_ada';
  end if;
  if b.deleted_at is not null then
    return 'dihapus';
  end if;
  return 'dibayar';
end $$;

create or replace function public.lepas_klaim_bill(p_bill uuid, p_tx uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  perform set_config('teras.ubah_klaim', 'ya', true);
  update public.open_bills
     set klaim_tx = null,
         klaim_pada = null
   where id = p_bill
     and klaim_tx = p_tx
     and transaction_id is null;
  perform set_config('teras.ubah_klaim', '', true);
end $$;

create or replace function public.hapus_bill(p_bill uuid)
returns text
language plpgsql
security invoker
set search_path = public
as $$
declare
  b record;
begin
  update public.open_bills
     set deleted_at = now(),
         updated_at = now()
   where id = p_bill
     and transaction_id is null
     and deleted_at is null
     and not public.klaim_berlaku(klaim_tx, klaim_pada);
  if found then
    return 'ok';
  end if;

  select deleted_at into b from public.open_bills where id = p_bill;
  if not found then
    return 'belum_ada';
  end if;
  if b.deleted_at is not null then
    return 'dihapus';
  end if;
  return 'dibayar';
end $$;

-- ---------------------------------------------------------------------
--  Penjaga status — menggantikan versi open_bill_kunci.sql.
--
--  Berjalan SEBELUM trg_open_bills_jaga_versi (abjad), jadi pelunasan yang
--  cap waktunya dimajukan di sini lolos dari penjaga versi.
-- ---------------------------------------------------------------------
create or replace function public.jaga_status_bill()
returns trigger
language plpgsql
as $$
declare
  dikoreksi boolean := false;
  klaim     boolean := public.klaim_berlaku(old.klaim_tx, old.klaim_pada);
  pelunasan boolean := old.transaction_id is null
                       and old.deleted_at is null
                       and new.transaction_id is not null
                       and new.transaction_id is not distinct from old.klaim_tx;
begin
  -- klaim_tx hanya lewat klaim_bill / lepas_klaim_bill.
  if coalesce(current_setting('teras.ubah_klaim', true), '') <> 'ya' then
    if new.klaim_tx is distinct from old.klaim_tx
       or new.klaim_pada is distinct from old.klaim_pada then
      new.klaim_tx := old.klaim_tx;
      new.klaim_pada := old.klaim_pada;
      dikoreksi := true;
    end if;
  end if;

  if old.transaction_id is not null or old.deleted_at is not null then
    -- Status akhir: tidak berubah lagi, isinya juga.
    if new.transaction_id is distinct from old.transaction_id
       or new.deleted_at is distinct from old.deleted_at
       or new.items is distinct from old.items
       or new.name is distinct from old.name then
      new.transaction_id := old.transaction_id;
      new.deleted_at := old.deleted_at;
      new.items := old.items;
      new.name := old.name;
      dikoreksi := true;
    end if;
  elsif pelunasan then
    -- Pelunasan oleh pemegang klaim selalu diterima (S6) — juga kalau
    -- klaimnya sudah lewat 15 menit, selama belum diambil transaksi lain.
    new.updated_at :=
      greatest(new.updated_at, old.updated_at + interval '1 second');
    return new;
  elsif klaim then
    -- Sedang dibayar: transaction_id hanya untuk pemegang klaim, tidak
    -- boleh dihapus, isinya tidak boleh berubah (S8).
    if new.transaction_id is not null then
      new.transaction_id := null;
      dikoreksi := true;
    end if;
    if new.deleted_at is not null then
      new.deleted_at := null;
      dikoreksi := true;
    end if;
    if new.items is distinct from old.items
       or new.name is distinct from old.name then
      new.items := old.items;
      new.name := old.name;
      dikoreksi := true;
    end if;
  elsif new.transaction_id is not null then
    -- Lunas tanpa klaim: APK lama, atau bill yang dibuat offline.
    new.updated_at :=
      greatest(new.updated_at, old.updated_at + interval '1 second');
    return new;
  end if;

  if dikoreksi then
    new.updated_at :=
      greatest(new.updated_at, old.updated_at, now()) + interval '1 second';
  end if;
  return new;
end $$;

revoke all on function public.klaim_berlaku(uuid, timestamptz)
  from public, anon;
grant execute on function public.klaim_berlaku(uuid, timestamptz)
  to authenticated;
revoke all on function public.klaim_bill(uuid, uuid)       from public, anon;
revoke all on function public.lepas_klaim_bill(uuid, uuid) from public, anon;
revoke all on function public.hapus_bill(uuid)             from public, anon;
grant execute on function public.klaim_bill(uuid, uuid)       to authenticated;
grant execute on function public.lepas_klaim_bill(uuid, uuid) to authenticated;
grant execute on function public.hapus_bill(uuid)             to authenticated;
revoke all on function public.jaga_status_bill() from public, anon, authenticated;

-- =====================================================================
--  PEMERIKSAAN SESUDAH DIJALANKAN
--
--    select column_name from information_schema.columns
--     where table_name = 'open_bills' and column_name = 'klaim_pada';
--    -- 1 baris
-- =====================================================================

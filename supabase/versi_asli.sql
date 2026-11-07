-- =====================================================================
--  VERSI ASLI KIRIMAN (audit 6 Nov 2026 nomor 11, 12, 13 & 19)
--
--  Jalankan lewat SQL Editor di dashboard Supabase SESUDAH
--  perangkat_bukti_owner.sql. Aman diulang. Tidak perlu APK baru.
--
--  ── MASALAH YANG DIPECAHKAN ──
--
--  `upsert` dari HP menjalankan trigger BEFORE INSERT dulu, juga untuk baris
--  yang sudah ada, lalu beralih ke UPDATE dengan hasil trigger tadi.
--
--  11. Kiriman ulang produk lama dicari kembarannya di tahap INSERT, lalu
--      digabung dan dihapus. Harga barunya hilang.
--  12. Trigger yang memajukan `updated_at` di tahap INSERT (kategori
--      terhapus, shift digabung) membuat penjaga versi mengira kiriman basi
--      lebih baru: Rp 20.000 lama menimpa Rp 22.000 baru di semua HP.
--  13. `hapus_bill` memberi cap now(); kalau cap bill dari HP yang jamnya
--      maju, penjaga versi membuang penghapusannya tapi fungsinya tetap
--      menjawab 'ok'.
--  19. `perangkat_hadir` mengosongkan shift yang sudah digabung, jadi HP lain
--      boleh menutup shift tujuan yang masih dipakai.
--
--  ── PERBAIKANNYA ──
--
--  - Trigger paling awal (`trg_<tabel>_aa_cap_asli`) mencatat cap asli
--    kiriman untuk baris yang sudah ada, dan penjaga versi membandingkan cap
--    itu. Penambalan per trigger tidak perlu lagi.
--  - Produk yang sudah ada hanya diperiksa kembarannya kalau ganti nama.
--  - `hapus_bill` memakai cap yang selalu lebih baru dari cap tersimpan.
--  - `perangkat_hadir` meneruskan shift yang digabung ke tujuannya.
-- =====================================================================

-- ---------------------------------------------------------------------
--  12. Cap asli kiriman
-- ---------------------------------------------------------------------
create or replace function public.kunci_cap_asli(p_tabel text, p_id uuid)
returns text
language sql
immutable
as $$
  select 'teras.cap_' || p_tabel || '_' || replace(p_id::text, '-', '');
$$;

create or replace function public.catat_cap_asli()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ada boolean;
begin
  execute format('select exists (select 1 from public.%I where id = $1)',
                 tg_table_name)
     into v_ada using new.id;
  if v_ada then
    -- Sama dengan aturan 2 di jaga_versi_terbaru: cap yang kelewat maju
    -- dianggap sekarang.
    perform set_config(
      public.kunci_cap_asli(tg_table_name, new.id),
      (case when new.updated_at > now() + interval '5 minutes'
            then now() else new.updated_at end)::text,
      true);
  end if;
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array[
    'users','user_permissions','categories','products','shifts',
    'transactions','transaction_items','expenses','open_bills'
  ] loop
    execute format('drop trigger if exists %I on public.%I',
                   'trg_'||t||'_aa_cap_asli', t);
    execute format(
      'create trigger %I before insert on public.%I '
      'for each row execute function public.catat_cap_asli()',
      'trg_'||t||'_aa_cap_asli', t);
  end loop;
end $$;

create or replace function public.jaga_versi_terbaru()
returns trigger
language plpgsql
as $$
declare
  v_kunci text;
  v_cap   timestamptz;
begin
  -- 2. Jam HP yang terlalu maju.
  if new.updated_at > now() + interval '5 minutes' then
    new.updated_at := now();
  end if;

  if tg_op <> 'UPDATE' then
    return new;
  end if;

  -- 3. Pembatalan bersifat satu arah dan selalu menang.
  if tg_table_name in ('transactions', 'expenses') then
    if old.deleted_at is not null and new.deleted_at is null then
      return old;
    end if;
    if old.deleted_at is null and new.deleted_at is not null then
      new.updated_at :=
        greatest(new.updated_at, old.updated_at + interval '1 second');
      return new;
    end if;
  end if;

  -- 1. Versi yang lebih tua tidak menimpa yang lebih baru. Dibandingkan
  --    dengan cap ASLI kiriman (lihat catat_cap_asli): trigger lain bisa
  --    sudah memajukan capnya di tahap INSERT (audit 6 Nov nomor 12).
  v_kunci := public.kunci_cap_asli(tg_table_name, new.id);
  v_cap := nullif(current_setting(v_kunci, true), '')::timestamptz;
  if v_cap is not null then
    perform set_config(v_kunci, '', true);
  end if;
  if coalesce(v_cap, new.updated_at) < old.updated_at then
    return old;
  end if;
  return new;
end $$;


-- ---------------------------------------------------------------------
--  11. Produk kembar
-- ---------------------------------------------------------------------
create or replace function public.gabung_produk_kembar()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_kunci text := lower(btrim(new.name));
  v_pakai public.products%rowtype;
  v_lama  public.products%rowtype;
begin
  if new.deleted_at is not null then
    return new;
  end if;
  -- `upsert` menjalankan tahap INSERT juga untuk produk yang SUDAH ada. Dulu
  -- kiriman ulang produk lama ikut dicari kembarannya, lalu digabung dan
  -- dihapus (audit 6 Nov nomor 11). Sama dengan pemeriksaan UPDATE di bawah:
  -- hanya produk baru atau ganti nama yang diperiksa.
  if tg_op = 'INSERT' then
    select * into v_lama from public.products where id = new.id;
    if found and v_lama.deleted_at is null
       and lower(btrim(v_lama.name)) = v_kunci then
      return new;
    end if;
  end if;
  -- Perubahan biasa tidak diperiksa, supaya kembar lama tidak ikut tergabung.
  if tg_op = 'UPDATE'
     and old.deleted_at is null
     and lower(btrim(old.name)) = v_kunci then
    return new;
  end if;

  -- Dua kiriman bernama sama yang bersamaan: yang kedua menunggu yang pertama.
  perform pg_advisory_xact_lock(hashtext('produk_kembar:' || v_kunci));

  select * into v_pakai
    from public.products p
   where p.id <> new.id
     and p.deleted_at is null
     and lower(btrim(p.name)) = v_kunci
   order by p.created_at, p.id
   limit 1;

  if not found then
    -- Hidup lagi dan tidak kembar: tidak lagi digabung ke mana pun.
    delete from public.produk_gabung where id_lama = new.id;
    return new;
  end if;

  insert into public.produk_gabung (id_lama, id_baru)
  values (new.id, v_pakai.id)
  on conflict (id_lama) do update set id_baru = excluded.id_baru;
  update public.produk_gabung set id_baru = v_pakai.id where id_baru = new.id;

  if v_pakai.image_path is null and new.image_path is not null then
    update public.products
       set image_path = new.image_path,
           updated_at = greatest(now(), updated_at) + interval '1 second'
     where id = v_pakai.id;
  end if;

  update public.transaction_items
     set product_id = v_pakai.id,
         updated_at = greatest(now(), updated_at) + interval '1 second'
   where product_id = new.id;

  -- Disentuh saja: pemetaannya dikerjakan trigger open_bills di bawah.
  update public.open_bills b
     set updated_at = greatest(now(), b.updated_at)
   where b.transaction_id is null
     and b.deleted_at is null
     and b.items @> jsonb_build_array(jsonb_build_object('p', new.id::text));

  new.deleted_at := now();
  new.updated_at := greatest(now(), new.updated_at) + interval '1 second';
  return new;
end $$;


-- ---------------------------------------------------------------------
--  13. Hapus bill
-- ---------------------------------------------------------------------
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
         updated_at = greatest(now(), updated_at + interval '1 second')
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
--  19. Kabar "HP masih aktif"
-- ---------------------------------------------------------------------
create or replace function public.perangkat_hadir(
  p_shift_id     uuid    default null,
  p_tarik_bersih boolean default false,
  p_tertahan     integer default null,
  p_gagal_kirim  integer default null,
  p_selisih_jam  integer default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_shift uuid;
begin
  -- Shift yang sudah digabung diteruskan ke tujuannya (audit 6 Nov nomor
  -- 19): dulu dikosongkan, jadi HP lain boleh menutup shift tujuan padahal
  -- HP ini masih berjualan ke sana.
  select s.id into v_shift
  from public.shifts s
  where s.id = public.ujung_gabungan(p_shift_id)
    and s.end_at is null and s.deleted_at is null;

  update public.perangkat
     set terakhir_aktif     = now(),
         shift_id           = v_shift,
         terakhir_tarik     = case when p_tarik_bersih then now()
                                   else terakhir_tarik end,
         -- Null = tidak dilaporkan (kabar dari sentuhan, APK lama).
         jumlah_tertahan    = greatest(coalesce(p_tertahan, jumlah_tertahan), 0),
         jumlah_gagal_kirim = greatest(
                                coalesce(p_gagal_kirim, jumlah_gagal_kirim), 0),
         selisih_jam_detik  = coalesce(p_selisih_jam, selisih_jam_detik)
   where id = auth.uid();
end $$;


-- HARUS bisa dipanggil HP: jaga_versi_terbaru berjalan atas nama HP yang
-- mengirim. Dulu dicabut, dan SEMUA perubahan baris yang sudah ada ditolak
-- `permission denied` (tutup shift, pembatalan, edit). Isinya hanya menyusun
-- nama kunci, tanpa rahasia.
revoke all on function public.kunci_cap_asli(text, uuid) from public, anon;
grant execute on function public.kunci_cap_asli(text, uuid) to authenticated;
revoke all on function public.catat_cap_asli() from public, anon, authenticated;
revoke all on function public.jaga_versi_terbaru() from public, anon, authenticated;
revoke all on function public.gabung_produk_kembar()
  from public, anon, authenticated;
revoke all on function public.hapus_bill(uuid) from public, anon;
grant execute on function public.hapus_bill(uuid) to authenticated;
revoke all on function public.perangkat_hadir(uuid, boolean, integer, integer, integer)
  from public, anon;
grant execute on function public.perangkat_hadir(uuid, boolean, integer, integer, integer)
  to authenticated;

-- =====================================================================
--  PEMERIKSAAN SESUDAH DIJALANKAN
--
--    select count(*) from pg_trigger where tgname like 'trg_%_aa_cap_asli';
--    -- 9
-- =====================================================================

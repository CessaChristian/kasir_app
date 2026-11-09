-- =====================================================================
--  INDEKS & KUNCI YANG LEBIH RINGAN (audit 6 Nov 2026 nomor 60)
--
--  Jalankan SEKALI lewat SQL Editor di dashboard Supabase, SESUDAH
--  `rls.sql`. Aman dijalankan ulang: indeks `if not exists`, fungsi
--  `create or replace`.
--
--  1. Dua pencarian tanpa indeks:
--     - `gabung_produk_kembar` (versi_asli.sql) mencari produk aktif
--       bernama sama setiap kali produk baru disimpan atau namanya diganti:
--       `lower(btrim(name))`. Tanpa indeks, seluruh tabel produk dibaca.
--     - Saat produk kembar digabung, item struknya dipindah:
--       `transaction_items where product_id = ...`. Tanpa indeks, seluruh
--       item struk sepanjang masa dibaca.
--
--  2. `ubah_kredensial_owner` dulu mengunci baris owner (`for update`)
--     SEBELUM PIN-nya dicocokkan. Pencocokannya sengaja berat (PBKDF2), jadi
--     selama itu baris owner tertahan — juga untuk PIN yang SALAH. Sekarang
--     PIN dicocokkan tanpa kunci; baris owner baru dikunci kalau memang akan
--     diubah, dan diperiksa ulang bahwa PIN/kode yang tadi cocok masih yang
--     berlaku (tidak diganti HP lain di sela itu).
--
--  Menggantikan definisi `ubah_kredensial_owner` di `kredensial_owner.sql`.
-- =====================================================================

create index if not exists idx_products_nama_aktif
  on public.products (lower(btrim(name)))
  where deleted_at is null;

create index if not exists idx_items_product
  on public.transaction_items (product_id);

create or replace function public.ubah_kredensial_owner(
  p_bukti text,
  p_jenis text,
  p_pin_hash text default null,
  p_salt text default null,
  p_recovery_hash text default null,
  p_recovery_salt text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  o public.users;
  k public.users;
  cocok boolean;
begin
  if not public.perangkat_aktif() then
    raise exception 'perangkat tidak terdaftar atau dicabut'
      using errcode = '42501';
  end if;

  -- Tanpa kunci: PIN salah tidak menahan apa pun.
  select * into o from public.users
   where role = 'owner' and deleted_at is null
   order by created_at
   limit 1;
  if not found then
    return 'belum_ada';
  end if;

  cocok := case p_jenis
    when 'pin' then public.cocok_pin(p_bukti, o.salt, o.pin_hash)
    when 'recovery' then public.cocok_pin(p_bukti, o.recovery_salt, o.recovery_hash)
    else false
  end;
  if not coalesce(cocok, false) then
    return 'salah';
  end if;
  if (p_pin_hash is null) <> (p_salt is null)
     or (p_recovery_hash is null) <> (p_recovery_salt is null) then
    raise exception 'hash dan garam harus berpasangan' using errcode = '22023';
  end if;

  -- Baru dikunci sekarang. Kalau PIN/kode yang tadi cocok sudah diganti HP
  -- lain di sela itu, bukti ini tidak berlaku lagi.
  select * into k from public.users where id = o.id for update;
  if not found
     or k.deleted_at is not null
     or k.role <> 'owner'
     or (p_jenis = 'pin'
         and (k.salt, k.pin_hash) is distinct from (o.salt, o.pin_hash))
     or (p_jenis = 'recovery'
         and (k.recovery_salt, k.recovery_hash)
             is distinct from (o.recovery_salt, o.recovery_hash)) then
    return 'salah';
  end if;

  perform set_config('teras.ubah_kredensial', 'ya', true);
  update public.users
     set pin_hash = coalesce(p_pin_hash, pin_hash),
         salt = coalesce(p_salt, salt),
         recovery_hash = coalesce(p_recovery_hash, recovery_hash),
         recovery_salt = coalesce(p_recovery_salt, recovery_salt),
         updated_at = greatest(updated_at, now())
   where id = o.id;
  perform set_config('teras.ubah_kredensial', '', true);
  return 'ok';
end $$;

revoke all on function public.ubah_kredensial_owner(text, text, text, text, text, text)
  from public, anon;
grant execute on function public.ubah_kredensial_owner(text, text, text, text, text, text)
  to authenticated;

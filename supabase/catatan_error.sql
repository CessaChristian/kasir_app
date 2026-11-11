-- =====================================================================
--  CATATAN ERROR DARI HP (audit 6 Nov 2026 nomor 62, keputusan 11 Nov)
--
--  Jalankan SEKALI lewat SQL Editor di dashboard Supabase. Di server yang
--  sudah berjalan cukup berkas ini saja; saat membangun dari nol, urutannya
--  sebelum `rls.sql` (lihat URUTAN.md). Aman diulang.
--
--  APK yang mengirim catatan tetap jalan tanpa berkas ini: catatannya
--  menunggu di HP dan terkirim sesudah berkas ini dijalankan.
--
--  ── MASALAH YANG DIPECAHKAN ──
--
--  Error yang tidak terduga di HP kasir hanya muncul di log HP itu dan
--  hilang. Selama uji coba kita tidak tahu ada yang salah kecuali kasirnya
--  bercerita.
--
--  ── ISINYA ──
--
--  Tabel `catatan_error` murni milik server: HP tidak punya hak apa pun
--  atasnya (tidak bisa membaca error HP lain, mengubah, atau menghapus).
--  HP hanya bisa memanggil `catat_error`, yang:
--    - menolak perangkat yang tidak terdaftar/aktif;
--    - menerima paling banyak 50 catatan per panggilan dan memotong teksnya;
--    - mengabaikan catatan yang sudah pernah diterima (kiriman ulang);
--    - membuang catatan yang lebih tua dari 30 hari.
--
--  Dibaca dari dashboard: Table Editor → catatan_error, atau
--    select * from public.catatan_error order by waktu desc;
-- =====================================================================

create table if not exists public.catatan_error (
  id            uuid primary key,
  perangkat_id  uuid,
  nama_perangkat text,
  -- Kapan terjadi menurut jam HP, dan kapan server menerimanya.
  waktu         timestamptz not null,
  diterima      timestamptz not null default now(),
  akun          text,
  peran         text,
  versi         text,
  -- 'tampilan', 'latar', atau 'tertangkap'.
  sumber        text,
  pesan         text not null,
  jejak         text,
  -- Berapa kali error yang sama terjadi sebelum dikirim.
  jumlah        integer not null default 1
);

create index if not exists idx_catatan_error_diterima
  on public.catatan_error (diterima);

alter table public.catatan_error enable row level security;
revoke all on public.catatan_error from anon, authenticated;

create or replace function public.catat_error(p_baris jsonb)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nama  text;
  v_masuk integer;
begin
  if not public.perangkat_aktif() then
    raise exception 'Perangkat tidak terdaftar' using errcode = '42501';
  end if;
  if jsonb_typeof(p_baris) <> 'array' then
    return 0;
  end if;

  select nama into v_nama from public.perangkat where id = auth.uid();

  delete from public.catatan_error
   where diterima < now() - interval '30 days';

  insert into public.catatan_error
    (id, perangkat_id, nama_perangkat, waktu, akun, peran, versi, sumber,
     pesan, jejak, jumlah)
  select (b->>'id')::uuid,
         auth.uid(),
         v_nama,
         coalesce((b->>'waktu')::timestamptz, now()),
         left(b->>'akun', 60),
         left(b->>'peran', 20),
         left(b->>'versi', 30),
         left(b->>'sumber', 20),
         left(coalesce(nullif(b->>'pesan', ''), '(kosong)'), 1000),
         left(b->>'jejak', 4000),
         greatest(coalesce((b->>'jumlah')::integer, 1), 1)
    from (select b from jsonb_array_elements(p_baris) b limit 50) s
  on conflict (id) do nothing;

  get diagnostics v_masuk = row_count;
  return v_masuk;
end $$;

revoke all on function public.catat_error(jsonb) from public, anon;
grant execute on function public.catat_error(jsonb) to authenticated;

-- =====================================================================
--  PEMERIKSAAN SESUDAH DIJALANKAN
--
--    select count(*) from pg_policies where tablename = 'catatan_error';
--    -- harus 0: HP tidak menyentuh tabelnya langsung
--
--    select grantee, privilege_type from information_schema.role_table_grants
--     where table_name = 'catatan_error' and grantee in ('anon','authenticated');
--    -- harus kosong
-- =====================================================================

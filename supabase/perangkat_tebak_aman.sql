-- =====================================================================
--  BATAS TEBAK KUNCI PEMASANGAN YANG TIDAK BISA DITEMBUS
--  (revisi QA kedua S3, 30 Okt 2026)
--
--  Jalankan lewat SQL Editor di dashboard Supabase SESUDAH
--  perangkat_aman.sql. Aman diulang. Tidak perlu APK baru.
--
--  ── MASALAH YANG DIPECAHKAN ──
--
--  1. Tebakan yang dikirim BERSAMAAN semuanya lolos pemeriksaan batas:
--     masing-masing menghitung percobaan sebelum yang lain sempat
--     mencatat. Terbukti di PostgreSQL lokal: 60 tebakan serentak, 60
--     diperiksa.
--     → Pemeriksaan diantrikan dengan kunci transaksi (advisory lock).
--
--  2. Batasnya satu untuk seluruh toko: orang luar yang salah 20 kali
--     membuat owner dengan kunci BENAR ditolak "terlalu banyak" selama
--     sejam — dan bisa diulang tiap jam.
--     → Batas per pemanggil (identitas HP) 5 salah per jam, ditambah batas
--       seluruh toko yang lebih longgar, 50 per jam, supaya penebak yang
--       berganti-ganti identitas tetap tertahan. Untuk memblokir owner,
--       orang luar sekarang harus terus-menerus membuat puluhan identitas
--       baru tiap jam, dan Supabase membatasi pembuatan identitas per
--       alamat internet.
--
--  Panjang kunci pemasangan sengaja tidak diatur di sini — itu keputusan
--  owner.
-- =====================================================================

alter table public.percobaan_kunci add column if not exists pemanggil uuid;
create index if not exists idx_percobaan_kunci_waktu
  on public.percobaan_kunci (waktu);

create or replace function public.daftarkan_perangkat(
  p_kunci text,
  p_nama  text
)
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_status text;
  v_n      integer;
begin
  if auth.uid() is null then
    return 'kunci_salah';
  end if;

  -- Satu per satu: tebakan bersamaan menunggu giliran, jadi masing-masing
  -- melihat percobaan yang sebelumnya. Dilepas otomatis di akhir transaksi.
  perform pg_advisory_xact_lock(hashtext('percobaan_kunci'));

  -- Selama batasnya terlampaui, kunci TIDAK diperiksa sama sekali — kalau
  -- diperiksa, jawabannya tetap membocorkan benar/salah.
  delete from public.percobaan_kunci where waktu < now() - interval '1 day';
  if (select count(*) from public.percobaan_kunci
       where waktu > now() - interval '1 hour'
         and pemanggil = auth.uid()) >= 5
     or (select count(*) from public.percobaan_kunci
          where waktu > now() - interval '1 hour') >= 50 then
    return 'terlalu_banyak';
  end if;

  if not exists (
    select 1 from public.rahasia
    where nama = 'kunci_pemasangan' and nilai = crypt(p_kunci, nilai)
  ) then
    insert into public.percobaan_kunci (pemanggil) values (auth.uid());
    return 'kunci_salah';
  end if;

  select status into v_status from public.perangkat where id = auth.uid();

  if v_status = 'dicabut' then
    return 'dicabut';
  end if;

  if v_status = 'aktif' then
    update public.perangkat set terakhir_aktif = now() where id = auth.uid();
    return 'ok';
  end if;

  -- Satu pernyataan: dua HP yang mendaftar bersamaan tidak mendapat kode
  -- yang sama (baris penanda terkunci sampai transaksi selesai).
  insert into public.nomor_terakhir (nama, nilai) values ('perangkat', 1)
  on conflict (nama) do update set nilai = public.nomor_terakhir.nilai + 1
  returning nilai into v_n;

  insert into public.perangkat (id, nama, kode)
  values (auth.uid(),
          coalesce(nullif(btrim(p_nama), ''), 'Perangkat'),
          public.kode_perangkat_ke(v_n));
  return 'ok';
end $$;

revoke all on function public.daftarkan_perangkat(text, text)
  from public, anon;
grant execute on function public.daftarkan_perangkat(text, text)
  to authenticated;

-- =====================================================================
--  PEMERIKSAAN SESUDAH DIJALANKAN
--
--    select column_name from information_schema.columns
--     where table_name = 'percobaan_kunci' and column_name = 'pemanggil';
--    -- 1 baris
-- =====================================================================

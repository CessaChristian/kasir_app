-- =====================================================================
--  PERANGKAT AMAN  —  kunci pemasangan tidak bisa ditebak, HP yang
--                     dicabut tidak bisa mengaktifkan dirinya sendiri
--
--  Jalankan lewat SQL Editor di dashboard Supabase. Aman diulang.
--  Jalankan SEBELUM memasang APK yang membawa perubahan ini.
--
--  ── YANG DITUTUP ──
--
--  1. Fungsi-fungsi di skema public bisa dipanggil `anon` — siapa pun di
--     internet, TANPA login, cukup dengan kunci publik yang tertanam di
--     APK. `revoke ... from public` tidak mencabutnya, karena Supabase
--     memberi hak ke `anon` secara langsung. Yang paling berbahaya
--     `daftarkan_perangkat`: kunci pemasangan bisa dicoba ribuan kali.
--
--  2. `daftarkan_perangkat` tanpa batas percobaan. Kini paling banyak 20
--     kunci salah per jam untuk SELURUH toko — batas per HP tidak berguna,
--     karena identitas HP baru bisa dibuat sepuasnya.
--
--  3. HP yang DICABUT owner bisa aktif lagi cukup dengan memasukkan kunci
--     pemasangan. Kini harus dipulihkan owner dari halaman Perangkat. HP
--     yang DILUPAKAN tetap bisa mendaftar ulang dengan kunci, karena
--     identitasnya sudah dihapus dan ia kembali seperti HP baru.
--
--  4. Daftar perangkat (nama HP, kode, shift yang dipegang, kapan terakhir
--     aktif) bisa dibaca siapa pun yang membuat identitas anonim. Kini
--     hanya HP aktif yang membaca seluruhnya; HP lain hanya barisnya
--     sendiri — itu yang dibutuhkan untuk tahu "aku belum terdaftar" atau
--     "aku dicabut".
--
--  ── ⚠ JAWABAN daftarkan_perangkat BERUBAH ──
--
--  Dulu kunci salah dilempar sebagai galat. Galat membatalkan semua yang
--  ditulis fungsinya — termasuk catatan "satu percobaan salah" — jadi
--  batas percobaan mustahil dihitung. Kini fungsinya MENJAWAB:
--    'ok' | 'kunci_salah' | 'terlalu_banyak' | 'dicabut'
--  APK lama yang mendaftar dengan kunci salah tidak lagi melihat pesan
--  "tidak valid" — ia kembali ke halaman pendaftaran. Perbarui semua HP.
-- =====================================================================

-- ---------------------------------------------------------------------
--  1. Tutup semua fungsi dari `anon`
-- ---------------------------------------------------------------------
--
--  Hak `anon` datang dari DUA arah: diberikan langsung oleh Supabase, dan
--  lewat PUBLIC (bawaan PostgreSQL untuk setiap fungsi baru). Keduanya
--  dicabut. HP yang sudah login (`authenticated`) diberi hak lagi secara
--  eksplisit — HANYA untuk fungsi yang memang sudah bisa dipanggilnya
--  sebelum ini, jadi tidak ada fitur yang putus.
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig,
           has_function_privilege('authenticated', p.oid, 'EXECUTE') as boleh
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prokind = 'f'
  loop
    if f.boleh then
      execute format('grant execute on function %s to authenticated', f.sig);
    end if;
    execute format('revoke execute on function %s from public, anon', f.sig);
  end loop;
end $$;

-- Hak langsung dari Supabase untuk fungsi yang dibuat sesudah ini.
--
-- ⚠ Hak lewat PUBLIC TIDAK bisa dicabut dengan cara ini — PostgreSQL
-- selalu memberikannya ke fungsi baru. Maka SETIAP fungsi baru di berkas
-- SQL project ini wajib menulis sendiri:
--    revoke all on function public.nama(...) from public, anon;
-- Dijaga test/arsitektur/fungsi_tertutup_test.dart.
alter default privileges in schema public
  revoke execute on functions from anon;

-- ---------------------------------------------------------------------
--  2. Catatan percobaan kunci yang salah
-- ---------------------------------------------------------------------
create table if not exists public.percobaan_kunci (
  id    bigserial primary key,
  waktu timestamptz not null default now()
);
alter table public.percobaan_kunci enable row level security;
-- Tanpa policy: tidak ada HP yang bisa membaca atau mengubahnya.
revoke all on public.percobaan_kunci from anon, authenticated;

-- ---------------------------------------------------------------------
--  3. daftarkan_perangkat — versi yang menjawab
-- ---------------------------------------------------------------------
drop function if exists public.daftarkan_perangkat(text, text);

create function public.daftarkan_perangkat(
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

  -- Selama batasnya terlampaui, kunci TIDAK diperiksa sama sekali — kalau
  -- diperiksa, jawabannya tetap membocorkan benar/salah.
  delete from public.percobaan_kunci where waktu < now() - interval '1 day';
  if (select count(*) from public.percobaan_kunci
       where waktu > now() - interval '1 hour') >= 20 then
    return 'terlalu_banyak';
  end if;

  if not exists (
    select 1 from public.rahasia
    where nama = 'kunci_pemasangan' and nilai = crypt(p_kunci, nilai)
  ) then
    insert into public.percobaan_kunci default values;
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

-- ---------------------------------------------------------------------
--  4. Daftar perangkat hanya untuk HP aktif (+ baris sendiri)
-- ---------------------------------------------------------------------
drop policy if exists baca_perangkat on public.perangkat;
create policy baca_perangkat on public.perangkat
  for select to authenticated
  using (id = auth.uid() or public.perangkat_aktif());

-- =====================================================================
--  PEMERIKSAAN SESUDAH DIJALANKAN
--
--    -- Tidak ada lagi fungsi yang bisa dipanggil tanpa login: harus 0.
--    select count(*) from pg_proc p
--      join pg_namespace n on n.oid = p.pronamespace
--     where n.nspname = 'public' and p.prokind = 'f'
--       and has_function_privilege('anon', p.oid, 'EXECUTE');
--
--    -- Jawaban baru: harus 'text'.
--    select pg_get_function_result(oid) from pg_proc
--     where proname = 'daftarkan_perangkat';
--
--  ── MEMBUAT KUNCI PEMASANGAN BARU ──
--
--  Sesudah berkas ini dijalankan. Ketik kunci barumu langsung di SQL
--  Editor, jalankan, lalu HAPUS kuerinya dari riwayat SQL Editor:
--
--    update public.rahasia
--       set nilai = extensions.crypt('KUNCI-BARU-DI-SINI',
--                                    extensions.gen_salt('bf', 10))
--     where nama = 'kunci_pemasangan';
--    -- harus "1 row affected"
--
--  HP yang sudah terdaftar tidak terpengaruh: kunci hanya dipakai saat
--  mendaftarkan HP baru (atau HP yang dilupakan).
-- =====================================================================

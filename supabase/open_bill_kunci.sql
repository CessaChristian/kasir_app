-- =====================================================================
--  OPEN BILL — KUNCI BAYAR/HAPUS & PENJAGA STATUS AKHIR
--
--  Jalankan lewat SQL Editor di dashboard Supabase SEBELUM memasang APK
--  yang memanggil klaim_bill / hapus_bill. Aman diulang. Database HP tidak
--  berubah (kolom baru hanya ada di server).
--
--  ── MASALAH YANG DIPECAHKAN ──
--
--  1. Dua HP memuat bill yang sama lalu menekan Bayar hampir bersamaan.
--     Keduanya bertanya "masih terbuka?" sebelum kiriman HP pertama sampai,
--     keduanya lolos, dan satu pesanan tercatat DUA transaksi (terbukti di
--     uji dua HP 2026-10-15). Internet lambat melebarkan celahnya.
--
--     Jawabannya klaim: sebelum menyimpan, HP meminta server menandai bill
--     itu dengan id transaksinya. Server mengerjakan "cek lalu tandai" dalam
--     SATU pernyataan UPDATE, jadi dari dua klaim yang bersamaan hanya satu
--     yang menang — yang lain menunggu kunci barisnya, lalu melihat bill
--     sudah ditandai.
--
--  2. Server menimpa baris bill dengan kiriman TERAKHIR. HP yang datanya
--     basi (belum tahu bill sudah lunas) lalu menekan Perbarui Bill akan
--     mengirim "belum dibayar" — dan bill yang sudah lunas TERBUKA LAGI di
--     semua HP, siap dibayar kedua kalinya.
--
--     Jawabannya penjaga (trigger): status akhir — lunas atau dihapus —
--     tidak bisa diubah lagi oleh kiriman mana pun. Kiriman itu TIDAK
--     ditolak (kalau ditolak, barisnya macet "pending" di HP selamanya),
--     cukup dikoreksi; waktu ubahnya dimajukan supaya semua HP menerima
--     versi server.
--
--  ── KOLOM BARU ──
--
--    open_bills.klaim_tx   transaksi yang sedang membayar bill ini. Sengaja
--                          TANPA foreign key: saat klaim, transaksinya baru
--                          ada di HP, belum terkirim.
-- =====================================================================

alter table public.open_bills add column if not exists klaim_tx uuid;

-- ---------------------------------------------------------------------
--  klaim_bill — dipanggil HP tepat sebelum menyimpan pembayaran bill.
--
--  'ok'        bill terbuka dan kini ditandai p_tx (atau memang sudah
--              ditandai p_tx — mengulang klaim yang sama aman).
--  'dibayar'   sudah lunas, atau sudah diklaim transaksi lain.
--  'dihapus'   sudah dihapus.
--  'belum_ada' bill belum pernah terkirim ke server (dibuat saat offline).
--              HP lain belum mungkin tahu bill ini, jadi aman dibayar.
--
--  SECURITY INVOKER: aturan akses tabel (perangkat_aktif) tetap berlaku.
-- ---------------------------------------------------------------------
create or replace function public.klaim_bill(p_bill uuid, p_tx uuid)
returns text
language plpgsql
security invoker
set search_path = public
as $$
declare
  b record;
begin
  update public.open_bills
     set klaim_tx = p_tx
   where id = p_bill
     and transaction_id is null
     and deleted_at is null
     and (klaim_tx is null or klaim_tx = p_tx);
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
--  lepas_klaim_bill — kalau penyimpanan di HP gagal SETELAH klaim berhasil,
--  tanda dilepas supaya bill tidak terkunci tanpa transaksi.
-- ---------------------------------------------------------------------
create or replace function public.lepas_klaim_bill(p_bill uuid, p_tx uuid)
returns void
language sql
security invoker
set search_path = public
as $$
  update public.open_bills
     set klaim_tx = null
   where id = p_bill
     and klaim_tx = p_tx
     and transaction_id is null;
$$;

-- ---------------------------------------------------------------------
--  hapus_bill — dipanggil HP sebelum menghapus bill. Hanya bill yang masih
--  terbuka DAN belum diklaim yang terhapus, dalam satu pernyataan.
--
--  'ok' | 'dibayar' | 'dihapus' (sudah terhapus sebelumnya) | 'belum_ada'
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
         updated_at = now()
   where id = p_bill
     and transaction_id is null
     and deleted_at is null
     and klaim_tx is null;
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

revoke all on function public.klaim_bill(uuid, uuid)       from public, anon;
revoke all on function public.lepas_klaim_bill(uuid, uuid) from public, anon;
revoke all on function public.hapus_bill(uuid)             from public, anon;
grant execute on function public.klaim_bill(uuid, uuid)       to authenticated;
grant execute on function public.lepas_klaim_bill(uuid, uuid) to authenticated;
grant execute on function public.hapus_bill(uuid)             to authenticated;

-- ---------------------------------------------------------------------
--  Penjaga status akhir.
--
--  1. Bill LUNAS atau DIHAPUS: transaction_id dan deleted_at dipertahankan.
--  2. Bill terklaim: transaction_id hanya boleh diisi transaksi pemegang
--     klaim, dan bill tidak boleh dihapus lewat kiriman biasa (hapus_bill
--     sendiri sudah menolak bill terklaim).
--
--  Kalau ada yang dikoreksi, updated_at dimajukan melewati nilai lama DAN
--  kiriman, +1 detik: HP hanya menerima baris server yang ≥1 detik lebih
--  baru dari miliknya (_serverMenang di sync_engine.dart). Tanpa ini HP
--  pengirim tetap memegang versi kirimannya yang salah.
-- ---------------------------------------------------------------------
create or replace function public.jaga_status_bill()
returns trigger
language plpgsql
as $$
declare
  dikoreksi boolean := false;
begin
  if old.transaction_id is not null or old.deleted_at is not null then
    if new.transaction_id is distinct from old.transaction_id
       or new.deleted_at is distinct from old.deleted_at then
      new.transaction_id := old.transaction_id;
      new.deleted_at := old.deleted_at;
      dikoreksi := true;
    end if;
  elsif old.klaim_tx is not null then
    if new.transaction_id is not null
       and new.transaction_id is distinct from old.klaim_tx then
      new.transaction_id := null;
      dikoreksi := true;
    end if;
    if new.deleted_at is not null and new.transaction_id is null then
      new.deleted_at := null;
      dikoreksi := true;
    end if;
  end if;

  if dikoreksi then
    new.updated_at :=
      greatest(new.updated_at, old.updated_at, now()) + interval '1 second';
  end if;
  return new;
end $$;

-- Nama "jaga" berjalan sebelum "server_urut" (trigger BEFORE berurutan
-- abjad) — urutannya tidak berpengaruh, keduanya menyentuh kolom berbeda.
drop trigger if exists trg_open_bills_jaga on public.open_bills;
create trigger trg_open_bills_jaga
  before update on public.open_bills
  for each row execute function public.jaga_status_bill();

-- =====================================================================
--  PEMERIKSAAN SESUDAH DIJALANKAN
--
--    select column_name from information_schema.columns
--     where table_name = 'open_bills' and column_name = 'klaim_tx';
--    -- harus 1 baris
--
--    select proname from pg_proc
--     where proname in ('klaim_bill','lepas_klaim_bill','hapus_bill',
--                       'jaga_status_bill');
--    -- harus 4 baris
--
--    select tgname from pg_trigger where tgname = 'trg_open_bills_jaga';
--    -- harus 1 baris
--
--  ── UJI PERILAKU ──
--
--  Jalankan blok DO di bawah ini sekaligus (hapus tanda "--" di depannya).
--  Blok ini SELALU berakhir dengan pesan galat — itu disengaja: galat
--  membatalkan semua yang dibuatnya, jadi tidak ada data uji yang tersisa.
--    · "UJI LULUS ..."      → semua perilaku benar.
--    · pesan lain           → langkah yang disebut gagal; kirim pesannya.
--
--  do $$
--  declare
--    s record;
--    b  uuid := gen_random_uuid();
--    ta uuid := gen_random_uuid();
--    tb uuid := gen_random_uuid();
--    r  text;
--  begin
--    select id, user_id into s from public.shifts limit 1;
--    insert into public.open_bills (id, name, shift_id, user_id)
--    values (b, 'UJI KUNCI', s.id, s.user_id);
--
--    r := public.klaim_bill(b, ta);
--    assert r = 'ok', '1. klaim pertama harus ok, dapat ' || r;
--    r := public.klaim_bill(b, tb);
--    assert r = 'dibayar', '2. klaim kedua harus dibayar, dapat ' || r;
--    r := public.hapus_bill(b);
--    assert r = 'dibayar', '3. hapus bill terklaim harus dibayar, dapat ' || r;
--
--    -- Kiriman HP lain mencoba mengisi transaksi selain pemegang klaim:
--    insert into public.transactions (id, total, payment_method, shift_id)
--    values (tb, 1000, 'cash', s.id), (ta, 1000, 'cash', s.id);
--    update public.open_bills set transaction_id = tb where id = b;
--    assert (select transaction_id from public.open_bills where id = b)
--      is null, '4. transaksi bukan pemegang klaim harus diabaikan';
--
--    -- Pemegang klaim melunasi, lalu kiriman basi mencoba membukanya lagi:
--    update public.open_bills set transaction_id = ta where id = b;
--    update public.open_bills set transaction_id = null where id = b;
--    assert (select transaction_id from public.open_bills where id = b)
--      = ta, '5. bill lunas tidak boleh terbuka lagi';
--
--    r := public.klaim_bill(gen_random_uuid(), ta);
--    assert r = 'belum_ada', '6. bill tak dikenal harus belum_ada, dapat ' || r;
--
--    raise exception 'UJI LULUS — semua perubahan uji sudah dibatalkan';
--  end $$;
-- =====================================================================

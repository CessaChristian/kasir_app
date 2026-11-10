-- =====================================================================
--  ITEM STRUK HANYA TERHAPUS BERSAMA NOTANYA (tes alur 10 Nov 2026)
--
--  Jalankan SEKALI lewat SQL Editor di dashboard Supabase. Di server yang
--  sudah berjalan cukup berkas ini saja; saat membangun dari nol, urutannya
--  sebelum `rls.sql` (lihat URUTAN.md). Aman diulang. Tidak perlu APK baru.
--
--  ── MASALAH YANG DIPECAHKAN ──
--
--  Kasir membatalkan nota di shift yang sudah ditutup. HP mengirim dua hal:
--  nota dibatalkan, dan item-itemnya dibatalkan. `batal_shift_tutup.sql`
--  mengembalikan NOTANYA (keputusan owner: setelah shift ditutup hanya owner
--  yang boleh membatalkan), tapi item-nya tidak dijaga dan tetap terhapus.
--  Akibatnya nota tetap dihitung di pendapatan, sedangkan isinya hilang dari
--  laporan per produk/kategori dan struk di Riwayat kosong. Ditemukan di
--  nota CS/02/011126/I-0003: pendapatan 30 hari Rp 1.503.500, per kategori
--  Rp 1.491.500.
--
--  ── PERBAIKANNYA ──
--
--  1. Item hanya boleh berubah dari hidup ke terhapus kalau NOTANYA di server
--     sudah dibatalkan. Aplikasi tidak pernah menghapus item tanpa
--     membatalkan notanya, dan nota selalu dikirim sebelum item (urutan
--     sinkron induk dulu), jadi pembatalan yang sah tetap diterima. Yang
--     ditolak dikembalikan seperti semula dan capnya dimajukan, supaya HP
--     pengirim menarik lagi item itu.
--  2. Data lama: item terhapus milik nota yang masih sah dihidupkan lagi.
--
--  Trigger `trg_transaction_items_sah_batal` berjalan SESUDAH `..._jaga_versi`,
--  `..._kunci_kolom`, `..._produk_gabung` dan SEBELUM `..._server_urut`
--  (abjad).
-- =====================================================================

create or replace function public.tolak_hapus_item_nota_sah()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (old.deleted_at is null and new.deleted_at is not null) then
    return new;
  end if;
  if exists (
    select 1 from public.transactions t
     where t.id = new.transaction_id
       and t.deleted_at is not null
  ) then
    return new;
  end if;
  -- Notanya masih sah: item dipertahankan, dan dimajukan supaya HP pengirim
  -- menarik versi ini.
  new := old;
  new.updated_at :=
    greatest(old.updated_at, now()) + interval '1 second';
  return new;
end $$;

drop trigger if exists trg_transaction_items_sah_batal on public.transaction_items;
create trigger trg_transaction_items_sah_batal
  before update on public.transaction_items
  for each row execute function public.tolak_hapus_item_nota_sah();

revoke all on function public.tolak_hapus_item_nota_sah()
  from public, anon, authenticated;

-- Data lama: item terhapus milik nota yang masih sah.
update public.transaction_items i
   set deleted_at = null,
       updated_at = greatest(i.updated_at, now()) + interval '1 second'
 where i.deleted_at is not null
   and exists (
     select 1 from public.transactions t
      where t.id = i.transaction_id
        and t.deleted_at is null
   );

-- =====================================================================
--  PEMERIKSAAN SESUDAH DIJALANKAN
--
--    select count(*) from pg_trigger
--     where tgname = 'trg_transaction_items_sah_batal';
--    -- 1
--
--    -- Nota sah yang itemnya terhapus (harus 0):
--    select count(*) from public.transaction_items i
--      join public.transactions t on t.id = i.transaction_id
--     where i.deleted_at is not null and t.deleted_at is null;
-- =====================================================================

-- =====================================================================
--  MODEL & JENIS PERANGKAT DI DAFTAR PERANGKAT
--
--  Jalankan lewat SQL Editor di dashboard Supabase. Aman diulang. Boleh
--  dijalankan sebelum atau sesudah APK baru dipasang: tanpa berkas ini,
--  halaman Daftar Perangkat hanya tidak menampilkan baris model.
--
--  ── MASALAH YANG DIPECAHKAN ──
--
--  Desain Daftar Perangkat menampilkan model HP di bawah namanya ("Xiaomi
--  Redmi Note 12 · Android 13") dan ikon tablet untuk tablet. Server baru
--  menyimpan `nama`, yang awalnya memang tebakan model — tapi begitu
--  pemilik menggantinya, modelnya hilang.
--
--  ── KENAPA LEWAT FUNGSI, BUKAN TULIS LANGSUNG ──
--
--  Tabel `perangkat` hanya boleh diubah lewat fungsi server (lihat
--  perangkat.sql). Fungsi di bawah hanya mengubah baris PERANGKAT ITU
--  SENDIRI (`auth.uid()`), dan hanya dua kolom ini — tidak bisa dipakai
--  memulihkan diri yang sudah dicabut.
--
--  Setiap HP mengirim modelnya sendiri sesudah sinkron, jadi HP yang sudah
--  terdaftar ikut terisi tanpa perlu mendaftar ulang. HP dengan APK lama
--  tidak mengirim apa-apa: kolomnya tetap kosong.
-- =====================================================================

alter table public.perangkat add column if not exists model  text;
alter table public.perangkat add column if not exists tablet boolean not null default false;

create or replace function public.catat_model_perangkat(
  p_model  text,
  p_tablet boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.perangkat
     set model  = nullif(btrim(left(p_model, 80)), ''),
         tablet = coalesce(p_tablet, false)
   where id = auth.uid();
end $$;

revoke all on function public.catat_model_perangkat(text, boolean) from public, anon;
grant execute on function public.catat_model_perangkat(text, boolean) to authenticated;

-- =====================================================================
--  PEMERIKSAAN SESUDAH DIJALANKAN (setelah HP baru sempat sinkron)
--
--    select nama, model, tablet, status from public.perangkat
--     order by terakhir_aktif desc;
-- =====================================================================

-- =====================================================================
--  SIAPA YANG SEDANG MEMEGANG SHIFT
--
--  Jalankan SEKALI lewat SQL Editor di dashboard Supabase.
--  Aman dijalankan ulang: `if not exists` / `or replace`.
--
--  ── MASALAH YANG DIPECAHKAN ──
--
--  Satu shift kini bisa dipegang lebih dari satu HP — itu memang disengaja,
--  supaya kasir yang berpindah perangkat tidak melahirkan shift kedua. Tapi
--  akibatnya: menekan "Akhiri Shift" di HP pinjaman ikut menutup shift yang
--  masih dipakai HP satunya, dan HP itu tetap bisa berjualan ke shift yang
--  sudah tutup. Rekap shiftnya jadi memuat transaksi yang terjadi SESUDAH
--  jam tutupnya sendiri.
--
--  Supaya bisa ditolak, server harus tahu HP mana saja yang sedang memegang
--  sebuah shift. Itu yang dicatat kolom di bawah.
--
--  ── KENAPA KOLOMNYA DI `perangkat`, BUKAN DI `shifts` ──
--
--    satu HP     -> memegang paling banyak SATU shift
--    satu shift  -> bisa dipegang BANYAK HP      <- inti masalahnya
--
--  Kolom tunggal di `shifts` hanya muat satu pemegang, sehingga keadaan yang
--  justru ingin dideteksi — "ada lebih dari satu HP di shift ini" — tidak
--  akan pernah terlihat. Di sisi `perangkat`, tiap HP menulis barisnya
--  sendiri dan pertanyaannya bisa dijawab dengan menghitung.
-- =====================================================================

-- ---------------------------------------------------------------------
--  1. Kolomnya
--
--  `on delete set null`, BUKAN `cascade`. Kalau suatu hari baris shiftnya
--  hilang, yang terjadi cukup penunjuknya dikosongkan — bukan baris
--  perangkatnya ikut terhapus. Project ini sudah pernah kena `cascade` yang
--  menembus perlindungan RLS lewat `permissions` -> `user_permissions`;
--  jangan diulang.
-- ---------------------------------------------------------------------
alter table public.perangkat
  add column if not exists shift_id uuid
    references public.shifts(id) on delete set null;

-- Dipakai untuk menjawab "ada HP lain di shift ini?" — tanpa indeks,
-- pertanyaan itu memindai seluruh daftar perangkat tiap kali.
create index if not exists idx_perangkat_shift
  on public.perangkat (shift_id) where shift_id is not null;

-- ---------------------------------------------------------------------
--  2. `perangkat_hadir` sekarang ikut melaporkan shift yang dipegang
--
--  Dipanggil aplikasi sesudah SETIAP sinkron berhasil, jadi tidak ada jalur
--  baru maupun timer baru — cukup dititipi satu nilai.
--
--  Parameternya diberi nilai bawaan `null` supaya pemanggilan lama
--  `perangkat_hadir()` tetap sah. Versi tanpa parameter DIBUANG lebih dulu:
--  kalau dibiarkan, dua fungsi bernama sama akan membuat pemanggilan tanpa
--  argumen jadi ambigu dan ditolak Postgres.
--
--  ── KENAPA KEBERADAAN SHIFTNYA DIPERIKSA DULU ──
--
--  Kasir bisa login saat internet mati; shiftnya lahir di HP dan baru sampai
--  ke server belakangan. Mesin sinkron memang mendorong tabel `shifts`
--  sebelum memanggil fungsi ini, tapi kalau dorongan itu kebetulan gagal,
--  foreign key akan menolak — dan galat itu tidak bisa diperbuat apa-apa
--  oleh kasir yang sedang melayani pembeli.
--
--  Maka kolomnya cukup dibiarkan kosong, dan sinkron berikutnya mencoba lagi
--  sesudah shiftnya sampai.
-- ---------------------------------------------------------------------
drop function if exists public.perangkat_hadir();

create or replace function public.perangkat_hadir(p_shift_id uuid default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_shift uuid;
begin
  select s.id into v_shift
  from public.shifts s
  where s.id = p_shift_id and s.end_at is null and s.deleted_at is null;

  update public.perangkat
     set terakhir_aktif = now(),
         shift_id       = v_shift
   where id = auth.uid();
end $$;

revoke all on function public.perangkat_hadir(uuid) from public;
grant execute on function public.perangkat_hadir(uuid) to authenticated;

-- ---------------------------------------------------------------------
--  3. "Boleh tidak aku mengakhiri shift ini?"
--
--  Dijawab server, bukan dihitung perangkat, supaya jawabannya sama untuk
--  siapa pun yang bertanya dan tidak bisa dipintas dengan mengarang angka.
--
--  Perangkat yang sudah DICABUT tidak dihitung: ia memang tidak boleh
--  menyentuh data toko lagi, jadi tidak masuk akal kalau ia masih bisa
--  menyandera shift orang lain.
--
--  `security definer` supaya tetap bisa membaca daftar perangkat sepenuhnya
--  walau kelak policy bacanya diperketat.
-- ---------------------------------------------------------------------
create or replace function public.shift_dipegang_perangkat_lain(p_shift_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.perangkat
    where shift_id = p_shift_id
      and id <> auth.uid()
      and status = 'aktif'
  );
$$;

revoke all on function public.shift_dipegang_perangkat_lain(uuid) from public;
grant execute on function public.shift_dipegang_perangkat_lain(uuid) to authenticated;

-- =====================================================================
--  PEMERIKSAAN SESUDAH DIJALANKAN
--
--    select column_name, data_type
--    from information_schema.columns
--    where table_schema = 'public' and table_name = 'perangkat';
--
--  Harus ada baris `shift_id` bertipe `uuid`.
--
--    select id, nama, status, shift_id, terakhir_aktif
--    from public.perangkat order by nama;
--
--  Sesudah kedua HP dipakai: `shift_id` terisi untuk HP yang kasirnya
--  sedang login, dan KOSONG untuk HP owner (owner tidak menjalankan shift).
-- =====================================================================

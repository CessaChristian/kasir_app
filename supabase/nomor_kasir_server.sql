-- =====================================================================
--  NOMOR KASIR HANYA DIBAGIKAN SERVER (revisi QA kedua S9, 30 Okt 2026)
--
--  Jalankan lewat SQL Editor di dashboard Supabase SESUDAH nomor_nota.sql.
--  Aman diulang.
--
--  ── MASALAH YANG DIPECAHKAN ──
--
--  Dulu HP menebak nomor kasir sendiri (terbesar di server + 1) lalu
--  mengirimnya:
--
--    1. Owner membuat kasir di dua HP hampir bersamaan → nomornya sama →
--       kiriman kedua ditolak indeks unik → akun itu dan SEMUA penjualannya
--       macet "belum terkirim".
--    2. Satu kiriman berisi akun bernomor dan akun tanpa nomor → kolomnya
--       terkirim kosong → nomor berubah, awalan nota ikut berubah
--       (CS/05 → CS/07).
--
--  Sekarang:
--    - Nomor yang dikirim HP DIABAIKAN. Server membagikan nomor berikutnya
--      dari penanda `nomor_terakhir` ('kasir'); baris penanda terkunci
--      sampai transaksi selesai, jadi dua kasir yang dibuat bersamaan
--      mendapat nomor berbeda.
--    - Nomor yang sudah ada TIDAK BISA diubah lewat update apa pun.
--    - updated_at dimajukan +1 detik saat nomor dibagikan, supaya HP
--      pembuatnya menarik nomor yang sebenarnya.
-- =====================================================================

-- Penanda mulai dari nomor terbesar yang sudah dibagikan.
insert into public.nomor_terakhir (nama, nilai)
select 'kasir', coalesce(max(nomor_kasir), 0) from public.users
on conflict (nama) do update
  set nilai = greatest(public.nomor_terakhir.nilai, excluded.nilai);

create or replace function public.isi_nomor_kasir()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ada  boolean;
  v_lama integer;
begin
  if tg_op = 'UPDATE' then
    -- Nomor yang sudah dibagikan tetap. Yang baru terisi (dari INSERT di
    -- bawah, lewat ON CONFLICT DO UPDATE) dibiarkan.
    if old.nomor_kasir is not null then
      new.nomor_kasir := old.nomor_kasir;
      return new;
    end if;
    if new.nomor_kasir is not null then
      return new;
    end if;
  else
    -- Kiriman HP berupa upsert: INSERT ... ON CONFLICT DO UPDATE melewati
    -- trigger INSERT ini dulu, juga untuk akun yang SUDAH ada. Akun lama
    -- memakai nomornya sendiri, tidak mengambil nomor baru.
    select true, nomor_kasir into v_ada, v_lama
      from public.users where id = new.id;
    if v_ada then
      new.nomor_kasir := v_lama;
      if v_lama is not null then
        return new;
      end if;
    end if;
  end if;

  if new.role = 'owner' then
    new.nomor_kasir := 0;
  else
    insert into public.nomor_terakhir (nama, nilai)
    values ('kasir',
            coalesce((select max(nomor_kasir) from public.users), 0) + 1)
    on conflict (nama) do update
      set nilai = greatest(
            public.nomor_terakhir.nilai,
            coalesce((select max(nomor_kasir) from public.users), 0)) + 1
    returning nilai into new.nomor_kasir;
  end if;
  new.updated_at := greatest(new.updated_at, now()) + interval '1 second';
  return new;
end $$;

-- Hanya untuk trigger; tidak boleh dipanggil langsung.
revoke all on function public.isi_nomor_kasir() from public, anon, authenticated;

drop trigger if exists trg_users_nomor_kasir on public.users;
create trigger trg_users_nomor_kasir
  before insert or update on public.users
  for each row execute function public.isi_nomor_kasir();

-- =====================================================================
--  PEMERIKSAAN SESUDAH DIJALANKAN
--
--    select nilai from public.nomor_terakhir where nama = 'kasir';
--    -- sama dengan nomor kasir terbesar
--
--    select username, nomor_kasir from public.users order by nomor_kasir;
--    -- tidak ada yang kembar, owner 0
-- =====================================================================

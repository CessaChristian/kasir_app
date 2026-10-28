-- =====================================================================
--  CABUT HAK SISA (revisi QA C10, 28 Okt 2026)
--
--  Jalankan lewat SQL Editor di dashboard Supabase. Aman diulang.
--  Isinya sama dengan tambahan terbaru di rls.sql — dipisah supaya tidak
--  perlu menjalankan ulang seluruh rls.sql.
--
--  Dari DDL server 28 Okt 2026:
--  - anon & authenticated masih punya TRUNCATE, TRIGGER, REFERENCES di
--    semua tabel data. Aplikasi tidak memakai satu pun. TRUNCATE (kosongkan
--    tabel sekaligus) bahkan melewati RLS. Lewat REST API perintahnya tidak
--    tersedia, jadi risikonya kecil — tapi pintunya tidak perlu terbuka.
--  - `nomor_terakhir` masih memberi INSERT/UPDATE/DELETE ke anon. RLS tanpa
--    policy tetap menahan; dicabut supaya penolakannya tidak bergantung pada
--    satu lapis saja.
-- =====================================================================

do $$
declare t text;
begin
  foreach t in array array[
    'users','permissions','user_permissions','categories','products',
    'shifts','transactions','transaction_items','expenses','open_bills',
    'perangkat'
  ] loop
    execute format(
      'revoke delete, truncate, trigger, references on public.%I '
      'from anon, authenticated', t);
  end loop;
end $$;

revoke all on public.nomor_terakhir from anon, authenticated;
revoke all on public.percobaan_kunci from anon, authenticated;

-- =====================================================================
--  PEMERIKSAAN SESUDAH DIJALANKAN — harus kosong:
--
--    select table_name, grantee, privilege_type
--      from information_schema.role_table_grants
--     where table_schema = 'public'
--       and grantee in ('anon', 'authenticated')
--       and (privilege_type in ('DELETE', 'TRUNCATE', 'TRIGGER', 'REFERENCES')
--            or table_name in ('nomor_terakhir', 'percobaan_kunci', 'rahasia'));
-- =====================================================================

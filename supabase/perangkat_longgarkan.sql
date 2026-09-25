-- =====================================================================
--  RENCANA MUNDUR — melonggarkan kembali penegakan daftar perangkat
--
--  Dipakai kalau setelah penegakan dinyalakan ada HP yang terkunci padahal
--  seharusnya boleh. Mengembalikan keadaan ke sebelum penegakan: perangkat
--  mana pun yang berhasil login boleh baca-tulis.
--
--  Daftar perangkatnya sendiri TIDAK dihapus — tinggal dinyalakan lagi nanti
--  setelah penyebabnya dibereskan.
-- =====================================================================
do $$
declare t text;
begin
  foreach t in array array[
    'users','user_permissions','categories','products','shifts',
    'transactions','transaction_items','expenses'
  ] loop
    execute format('drop policy if exists %I on public.%I', 'baca_'||t, t);
    execute format('drop policy if exists %I on public.%I', 'tambah_'||t, t);
    execute format('drop policy if exists %I on public.%I', 'ubah_'||t, t);

    execute format(
      'create policy %I on public.%I for select to authenticated using (true)',
      'baca_'||t, t);
    execute format(
      'create policy %I on public.%I for insert to authenticated with check (true)',
      'tambah_'||t, t);
    execute format(
      'create policy %I on public.%I for update to authenticated '
      'using (true) with check (true)', 'ubah_'||t, t);
  end loop;
end $$;

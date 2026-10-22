import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Menjaga `supabase/tolak_versi_lama.sql`: server menyimpan versi TERBARU
/// setiap baris, bukan kiriman yang tiba terakhir.
///
/// Perilakunya sudah diuji di PostgreSQL sungguhan saat berkas ini ditulis
/// (versi lama ditolak, jam HP 2030 dipotong, pembatalan selalu menang).
/// Yang dikunci di sini adalah hal yang gampang rusak tanpa gejala saat
/// berkasnya disunting kelak.
void main() {
  final sql = File('supabase/tolak_versi_lama.sql').readAsStringSync();
  final kode = sql
      .split('\n')
      .where((b) => !b.trimLeft().startsWith('--'))
      .join('\n');

  Set<String> tabelDi(String isi) {
    final larik = RegExp(r"array\[([^\]]+)\]").firstMatch(isi)!.group(1)!;
    return {
      for (final m in RegExp(r"'(\w+)'").allMatches(larik)) m.group(1)!,
    };
  }

  test('menjaga SEMUA tabel yang disinkron — sama dengan server_urut', () {
    final urut = File('supabase/sync_urutan.sql').readAsStringSync();
    expect(tabelDi(kode), tabelDi(urut));
    expect(tabelDi(kode), hasLength(9));
  });

  test('berjalan sebelum stempel server_urut (urutan abjad nama trigger)',
      () {
    for (final t in tabelDi(kode)) {
      expect(
        'trg_${t}_jaga_versi'.compareTo('trg_${t}_server_urut'),
        lessThan(0),
        reason: 'baris yang dipertahankan harus tetap dicap kedatangannya, '
            'supaya HP pengirim menarik versi yang menang',
      );
    }
    expect(kode, contains("'trg_'||t||'_jaga_versi'"));
  });

  test('versi lama dipertahankan TANPA galat', () {
    // Kiriman yang ditolak dengan galat membuat barisnya di HP macet
    // "belum terkirim" selamanya.
    expect(kode.toLowerCase(), isNot(contains('raise')));
    expect(kode, contains('if new.updated_at < old.updated_at then'));
    expect(kode, contains('return old;'));
  });

  test('pembatalan transaksi & pengeluaran satu arah', () {
    expect(kode, contains("tg_table_name in ('transactions', 'expenses')"));
    expect(
      kode,
      contains('if old.deleted_at is not null and new.deleted_at is null'),
    );
  });

  test('fungsi trigger tidak bisa dipanggil lewat API', () {
    expect(
      kode,
      contains('revoke all on function public.jaga_versi_terbaru()\n'
          '  from public, anon, authenticated;'),
    );
  });
}

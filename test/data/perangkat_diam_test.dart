import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/perangkat/perangkat_repository.dart';

/// HP aktif yang lama tidak sinkron menahan buang sampah selamanya, dan
/// owner tidak punya cara tahu kecuali diberi tanda. Ini pernah terjadi
/// betulan: identitas lama emulator yang dipasang ulang dan lupa
/// di-"Lupakan" diam-diam menahan pembuangan.
void main() {
  final kini = DateTime(2026, 10, 3, 12);

  Perangkat hp(Duration diam, {bool aktif = true, String id = 'hp-lain'}) =>
      Perangkat(
        id: id,
        nama: 'HP kasir',
        aktif: aktif,
        terakhirAktif: kini.subtract(diam),
      );

  bool dicek(Perangkat p) => p.perluDicek(sekarang: kini, idSaya: 'hp-owner');

  test('batasnya tepat 7 hari', () {
    expect(Perangkat.batasDiam, const Duration(days: 7));
    expect(dicek(hp(const Duration(days: 6, hours: 23, minutes: 59))), isFalse,
        reason: 'libur akhir pekan tidak boleh membuat owner kaget');
    expect(dicek(hp(const Duration(days: 7))), isTrue);
    expect(dicek(hp(const Duration(days: 40))), isTrue);
  });

  test('HP yang sedang dipakai owner tidak pernah ditandai', () {
    expect(dicek(hp(const Duration(days: 30), id: 'hp-owner')), isFalse);
  });

  test('HP yang sudah dicabut tidak ditandai — ia tidak menahan apa pun', () {
    expect(dicek(hp(const Duration(days: 30), aktif: false)), isFalse);
  });

  test('jumlah hari diam yang ditulis di tanda', () {
    expect(hp(const Duration(days: 9, hours: 5)).hariDiam(sekarang: kini), 9);
  });
}

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/supabase/supabase_service.dart';
import 'package:kasir_app/data/sync/kemajuan_sync.dart';
import 'package:kasir_app/data/sync/sync_engine.dart';
import 'package:kasir_app/shared/ui/segarkan/pengendali_segarkan.dart';

/// Tombol refresh di header (komponen bersama UI baru).
void main() {
  test('berjalan → selesai → pita menutup sendiri', () {
    fakeAsync((waktu) {
      final selesai = Completer<HasilSync>();
      final p = PengendaliSegarkan(jalankan: () => selesai.future);

      p.segarkan();
      expect(p.keadaan, KeadaanSegarkan.berjalan);
      expect(p.pitaTerlihat, isTrue);

      selesai.complete(const HasilSync(berubah: 3));
      waktu.flushMicrotasks();
      expect(p.keadaan, KeadaanSegarkan.selesai);

      waktu.elapse(const Duration(milliseconds: 1499));
      expect(p.pitaTerlihat, isTrue, reason: 'hasil sempat terbaca');
      waktu.elapse(const Duration(milliseconds: 2));
      expect(p.keadaan, KeadaanSegarkan.diam);
      expect(p.pitaTerlihat, isFalse);
    });
  });

  test('ditekan berulang saat masih berjalan tidak memulai putaran kedua', () {
    fakeAsync((waktu) {
      var dipanggil = 0;
      final selesai = Completer<HasilSync>();
      final p = PengendaliSegarkan(jalankan: () {
        dipanggil++;
        return selesai.future;
      });

      p.segarkan();
      p.segarkan();
      p.segarkan();
      expect(dipanggil, 1);

      selesai.complete(const HasilSync());
      waktu.flushMicrotasks();
      waktu.elapse(const Duration(seconds: 2));
    });
  });

  test('gagal tersambung → keadaan gagal', () {
    fakeAsync((waktu) {
      final p = PengendaliSegarkan(
        jalankan: () async =>
            const HasilSync(error: 'x', sebabTerputus: SebabTerputus.jaringan),
      );
      p.segarkan();
      waktu.flushMicrotasks();
      expect(p.keadaan, KeadaanSegarkan.gagal);
      waktu.elapse(const Duration(seconds: 2));
    });
  });

  test('dibuang di tengah sinkron tidak melempar galat', () {
    fakeAsync((waktu) {
      final selesai = Completer<HasilSync>();
      final p = PengendaliSegarkan(jalankan: () => selesai.future);
      p.segarkan();
      p.dispose();
      selesai.complete(const HasilSync());
      waktu.flushMicrotasks();
      waktu.elapse(const Duration(seconds: 2));
    });
  });

  group('teksPita', () {
    const k = KemajuanSync(
      tahap: 'menarik',
      entitas: 'products',
      entitasKe: 5,
      totalEntitas: 9,
      baris: 0,
      totalBaris: 0,
    );

    test('berjalan: menghubungi dulu, lalu persen', () {
      expect(teksPita(KeadaanSegarkan.berjalan, null, null).keterangan,
          'Menghubungi server');
      final t = teksPita(KeadaanSegarkan.berjalan, null, k);
      expect(t.judul, 'Menyinkronkan data…');
      expect(t.keterangan, '44%');
    });

    test('selesai memakai jumlah yang BERUBAH, bukan yang diperiksa', () {
      String judul(HasilSync h) =>
          teksPita(KeadaanSegarkan.selesai, h, null).judul;
      expect(judul(const HasilSync(diperiksa: 14)), 'Data sudah terbaru');
      expect(judul(const HasilSync(diperiksa: 14, berubah: 2)),
          '2 data diperbarui');
      expect(judul(const HasilSync(didorong: 3)), '3 data terkirim');
      expect(teksPita(KeadaanSegarkan.selesai, const HasilSync(), null).ikon,
          Icons.check_circle_rounded);
      expect(
          teksPita(KeadaanSegarkan.selesai, const HasilSync(), null).keterangan,
          'Selesai');
    });

    test('gagal: sebab sebenarnya, bukan selalu "periksa koneksi"', () {
      TeksPita gagal(HasilSync h) => teksPita(KeadaanSegarkan.gagal, h, null);
      expect(
          gagal(const HasilSync(
                  error: 'x', sebabTerputus: SebabTerputus.jaringan))
              .keterangan,
          'Periksa koneksi');
      expect(
          gagal(const HasilSync(
                  error: 'x', sebabTerputus: SebabTerputus.ditolak))
              .keterangan,
          'perangkat ini tidak dikenali server');
      expect(gagal(const HasilSync(error: 'x', berubah: 4)).judul,
          'Sebagian data belum tersinkron');
    });
  });
}

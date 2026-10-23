import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/supabase/supabase_service.dart';
import 'package:kasir_app/data/perangkat/perangkat_repository.dart';
import 'package:kasir_app/features/perangkat/pages/daftarkan_perangkat_page.dart';

/// Daftarkan Perangkat (desain): galat satu baris merah, tombol pil yang
/// memudar saat memproses, dan toast "Perangkat berhasil didaftarkan".
/// Server diganti tiruan.
void main() {
  late List<String> catatan;
  late Completer<HasilKunci> jawabanKunci;
  late bool lanjut;

  setUp(() {
    catatan = [];
    lanjut = false;
  });

  Future<void> pasang(
    WidgetTester t, {
    bool lengkapiSaja = false,
    HasilDaftarPerangkat hasilIdentitas = HasilDaftarPerangkat.berhasil,
    Future<void> Function()? sesudahBerhasil,
  }) async {
    // Dibuat di dalam test supaya jawabannya berjalan di jam tiruan test.
    jawabanKunci = Completer<HasilKunci>();
    await t.pumpWidget(
      MaterialApp(
        home: DaftarkanPerangkatPage(
          lengkapiSaja: lengkapiSaja,
          sesudahBerhasil: sesudahBerhasil ?? () async => lanjut = true,
          buatIdentitas: () async {
            catatan.add('buat');
            return hasilIdentitas;
          },
          periksaKunci: (k) {
            catatan.add('periksa:$k');
            return jawabanKunci.future;
          },
          lepaskanIdentitas: () async => catatan.add('lepas'),
        ),
      ),
    );
  }

  Future<void> isi(WidgetTester t, String kunci) =>
      t.enterText(find.byType(TextField), kunci);

  Future<void> tekan(WidgetTester t) async {
    await t.tap(find.text('Daftarkan Perangkat').last);
    await t.pump();
  }

  testWidgets('Tampilan awal sesuai desain', (t) async {
    await pasang(t);
    expect(find.text('Daftarkan Perangkat'), findsNWidgets(2));
    expect(find.textContaining('HP ini belum terdaftar.'), findsOneWidget);
    expect(find.text('Kunci pemasangan'), findsOneWidget);
    expect(find.bySemanticsLabel('Tampilkan kunci'), findsOneWidget);
    expect(find.byIcon(Icons.how_to_reg_rounded), findsOneWidget);
    expect(
      t.widget<TextField>(find.byType(TextField)).style!.letterSpacing,
      0,
      reason: 'tidak serenggang kolom PIN',
    );
  });

  testWidgets('Kolom kosong: galat, server tidak dihubungi', (t) async {
    await pasang(t);
    await tekan(t);
    expect(find.text('Kunci pemasangan wajib diisi'), findsOneWidget);
    expect(catatan, isEmpty);

    await isi(t, 'a');
    await t.pump();
    expect(
      find.text('Kunci pemasangan wajib diisi'),
      findsNothing,
      reason: 'galat hilang saat mengetik',
    );
  });

  testWidgets('Kunci salah: "tidak valid", identitas dilepas', (t) async {
    await pasang(t);
    await isi(t, 'salah');
    await tekan(t);
    jawabanKunci.complete(HasilKunci.salah);
    await t.pumpAndSettle();
    expect(find.text('Kunci pemasangan tidak valid'), findsOneWidget);
    expect(catatan, ['buat', 'periksa:salah', 'lepas']);
    expect(lanjut, isFalse);
  });

  testWidgets('Tanpa internet: pesan koneksi, kunci tidak diperiksa', (
    t,
  ) async {
    await pasang(t, hasilIdentitas: HasilDaftarPerangkat.jaringan);
    await isi(t, 'kunci');
    await tekan(t);
    await t.pumpAndSettle();
    expect(find.textContaining('Tidak bisa menghubungi server.'), findsOne);
    expect(catatan, ['buat']);
  });

  testWidgets('Memproses: pudar, jam pasir, tidak bisa ditekan dua kali', (
    t,
  ) async {
    await pasang(t);
    await isi(t, 'benar');
    await tekan(t);
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Mendaftarkan...'), findsOneWidget);
    expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);
    expect(
      t
          .widget<AnimatedOpacity>(
            find.ancestor(
              of: find.text('Mendaftarkan...'),
              matching: find.byType(AnimatedOpacity),
            ),
          )
          .opacity,
      lessThan(1),
    );

    await t.tap(find.text('Mendaftarkan...'));
    await t.pump();
    expect(
      catatan.where((c) => c == 'buat'),
      hasLength(1),
      reason: 'ketukan kedua diabaikan',
    );

  });

  testWidgets('Berhasil: toast baru muncul setelah halaman Login tampil', (
    t,
  ) async {
    // Meniru main.dart: setelah daftar, data toko ditarik dulu (lama), lalu
    // halaman ini DIGANTI halaman Login.
    final keLogin = ValueNotifier(false);
    final tarikData = Completer<void>();
    jawabanKunci = Completer<HasilKunci>();
    await t.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: keLogin,
          builder: (_, login, _) => login
              ? const Scaffold(body: Text('Halaman Login'))
              : DaftarkanPerangkatPage(
                  sesudahBerhasil: () async {
                    await tarikData.future;
                    keLogin.value = true;
                    // Seperti main.dart: kembali setelah Login sudah
                    // menggantikan halaman ini.
                    await SchedulerBinding.instance.endOfFrame;
                  },
                  buatIdentitas: () async => HasilDaftarPerangkat.berhasil,
                  periksaKunci: (_) => jawabanKunci.future,
                  lepaskanIdentitas: () async {},
                ),
        ),
      ),
    );
    await isi(t, 'benar');
    await tekan(t);
    jawabanKunci.complete(HasilKunci.diterima);
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    expect(
      find.text('Perangkat berhasil didaftarkan'),
      findsNothing,
      reason: 'data toko masih ditarik, Login belum tampil',
    );

    tarikData.complete();
    await t.pump();
    await t.pump();
    await t.pump();
    expect(find.text('Halaman Login'), findsOneWidget);
    expect(find.text('Perangkat berhasil didaftarkan'), findsOneWidget);
    await t.pump(const Duration(seconds: 3));
  });

  testWidgets('Lengkapi Pendaftaran: identitas tidak dibuat ulang', (t) async {
    await pasang(t, lengkapiSaja: true);
    expect(find.text('Lengkapi Pendaftaran'), findsOneWidget);
    await isi(t, 'salah');
    await tekan(t);
    jawabanKunci.complete(HasilKunci.salah);
    await t.pumpAndSettle();
    expect(catatan, ['periksa:salah'], reason: 'tanpa buat & tanpa lepas');
    expect(find.text('Kunci pemasangan tidak valid'), findsOneWidget);
  });

  testWidgets('20 kunci salah sejam: pesan "terlalu banyak", identitas dilepas',
      (t) async {
    await pasang(t);
    await isi(t, 'apa-saja');
    await tekan(t);
    jawabanKunci.complete(HasilKunci.terlaluBanyak);
    await t.pumpAndSettle();
    expect(find.textContaining('Terlalu banyak percobaan'), findsOneWidget);
    expect(catatan, ['buat', 'periksa:apa-saja', 'lepas']);
  });

  testWidgets('HP yang dicabut tidak bisa aktif lagi lewat kunci', (t) async {
    await pasang(t, lengkapiSaja: true);
    await isi(t, 'benar');
    await tekan(t);
    jawabanKunci.complete(HasilKunci.dicabut);
    await t.pumpAndSettle();
    expect(find.textContaining('dicabut pemilik'), findsOneWidget);
    expect(lanjut, isFalse);
  });

  testWidgets('HP yang dilupakan: identitas baru dibuat, kunci diperiksa ulang',
      (t) async {
    final jawaban = [HasilKunci.identitasHilang, HasilKunci.diterima];
    await t.pumpWidget(
      MaterialApp(
        home: DaftarkanPerangkatPage(
          lengkapiSaja: true,
          sesudahBerhasil: () async => lanjut = true,
          buatIdentitas: () async {
            catatan.add('buat');
            return HasilDaftarPerangkat.berhasil;
          },
          periksaKunci: (k) async {
            catatan.add('periksa:$k');
            return jawaban.removeAt(0);
          },
          lepaskanIdentitas: () async => catatan.add('lepas'),
        ),
      ),
    );
    await isi(t, 'kunci-baru');
    await tekan(t);
    await t.pumpAndSettle();
    expect(catatan, ['periksa:kunci-baru', 'buat', 'periksa:kunci-baru']);
    expect(lanjut, isTrue);
    await t.pump(const Duration(seconds: 3));
  });

  test('jawaban server → HasilKunci (termasuk server lama)', () {
    expect(PerangkatRepository.hasilKunciDari('ok'), HasilKunci.diterima);
    expect(PerangkatRepository.hasilKunciDari(null), HasilKunci.diterima,
        reason: 'server sebelum perangkat_aman.sql tidak menjawab apa pun');
    expect(PerangkatRepository.hasilKunciDari('kunci_salah'), HasilKunci.salah);
    expect(PerangkatRepository.hasilKunciDari('terlalu_banyak'),
        HasilKunci.terlaluBanyak);
    expect(PerangkatRepository.hasilKunciDari('dicabut'), HasilKunci.dicabut);
    expect(PerangkatRepository.hasilKunciDari('aneh'), HasilKunci.gagal);
  });
}

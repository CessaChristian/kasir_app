import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/features/sales/models/keranjang.dart';
import 'package:kasir_app/features/sales/models/simpanan_keranjang.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tes alur 10 Nov: keranjang tidak hilang kalau aplikasinya dimatikan,
/// tapi tetap kosong sesudah keluar akun.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  Keranjang isi() => Keranjang()
    ..tambah(
      idProduk: 'mie',
      nama: 'Mie Goreng',
      harga: 16000,
      catatan: 'Pedas',
    )
    ..tambah(
      idProduk: 'mie',
      nama: 'Mie Goreng',
      harga: 16000,
      catatan: 'Pedas',
    )
    ..tambah(idProduk: 'teh', nama: 'Teh Panas', harga: 4500);

  test('kasir & shift yang sama: isi dan open bill kembali utuh', () async {
    final lama = isi()
      ..muatBill((id: 'b1', nama: 'Meja 5', isiAwal: '[]'), isi().baris);
    await SimpananKeranjang.simpan(lama, userId: 'k1', shiftId: 's1');

    final baru = Keranjang();
    expect(
      await SimpananKeranjang.pulihkan(baru, userId: 'k1', shiftId: 's1'),
      isTrue,
    );
    expect(baru.total, lama.total);
    expect(baru.baris.first.qty, 2);
    expect(baru.baris.first.notes, 'Pedas');
    expect(baru.bill?.nama, 'Meja 5');
  });

  test('kasir atau shift lain: tidak dipulihkan, simpanan dibuang', () async {
    await SimpananKeranjang.simpan(isi(), userId: 'k1', shiftId: 's1');
    expect(
      await SimpananKeranjang.pulihkan(
        Keranjang(),
        userId: 'k2',
        shiftId: 's1',
      ),
      isFalse,
    );
    await SimpananKeranjang.simpan(isi(), userId: 'k1', shiftId: 's1');
    expect(
      await SimpananKeranjang.pulihkan(
        Keranjang(),
        userId: 'k1',
        shiftId: 's2',
      ),
      isFalse,
    );
    expect(
      (await SharedPreferences.getInstance()).getString(
        SimpananKeranjang.kunci,
      ),
      isNull,
    );
  });

  test('keranjang kosong (sudah dibayar) menghapus simpanan', () async {
    await SimpananKeranjang.simpan(isi(), userId: 'k1', shiftId: 's1');
    await SimpananKeranjang.simpan(Keranjang(), userId: 'k1', shiftId: 's1');
    expect(
      await SimpananKeranjang.pulihkan(
        Keranjang(),
        userId: 'k1',
        shiftId: 's1',
      ),
      isFalse,
    );
  });

  test('pesanan yang sudah mulai disusun tidak ditimpa simpanan', () async {
    await SimpananKeranjang.simpan(isi(), userId: 'k1', shiftId: 's1');
    final k = Keranjang()..tambah(idProduk: 'kopi', nama: 'Kopi', harga: 8000);
    expect(
      await SimpananKeranjang.pulihkan(k, userId: 'k1', shiftId: 's1'),
      isFalse,
    );
    expect(k.baris.single.productId, 'kopi');
  });

  test('keluar akun menghapus simpanan', () async {
    await SessionManager.instance.setSession(
      AuthSession.create(
        userId: 'k1',
        username: 'sari',
        role: 'cashier',
        shiftId: 's1',
        permissions: const ['create_transaction'],
      ),
    );
    await SimpananKeranjang.simpan(isi(), userId: 'k1', shiftId: 's1');
    await SessionManager.instance.clearSession();
    expect(
      (await SharedPreferences.getInstance()).getString(
        SimpananKeranjang.kunci,
      ),
      isNull,
    );
  });

  test('simpanan rusak tidak membuat galat', () async {
    SharedPreferences.setMockInitialValues({SimpananKeranjang.kunci: '{rusak'});
    expect(
      await SimpananKeranjang.pulihkan(
        Keranjang(),
        userId: 'k1',
        shiftId: 's1',
      ),
      isFalse,
    );
  });
}

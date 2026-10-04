import '../../data/supabase/supabase_service.dart';
import '../../data/sync/sync_engine.dart';

/// Kalimat untuk kegagalan menyambung yang TIDAK akan pulih sendiri, atau
/// null kalau kegagalannya jenis yang cukup ditunggu.
///
/// Null berarti pemanggil memakai pesannya yang biasa ("periksa koneksi",
/// "akan terkirim saat online") — pesan itu benar untuk jaringan yang putus.
/// Yang tidak benar adalah memakainya untuk perangkat yang ditolak server:
/// kasir akan memburu masalah internet yang tidak ada.
///
/// Satu tempat untuk semua layar, supaya tiga layar yang melaporkan hal yang
/// sama tidak pelan-pelan berbeda bunyi. Sengaja tanpa `default`: menambah
/// sebab baru di [SebabTerputus] akan gagal dikompilasi di sini sampai
/// kalimatnya ikut ditulis.
///
/// Kalimatnya tidak menyebut siapa yang harus dihubungi, karena pembacanya
/// bisa kasir atau pemilik sendiri.
String? alasanTakPulihSendiri(SebabTerputus? sebab) => switch (sebab) {
  SebabTerputus.ditolak => 'perangkat ini tidak dikenali server',
  SebabTerputus.belumDisiapkan => 'aplikasi ini belum disiapkan untuk sinkron',
  SebabTerputus.jaringan => null,
  null => null,
};

/// Pesan gagal sinkron untuk AppToast — satu tempat untuk tombol ⟳ di
/// header dan tarik-untuk-refresh di halaman lama.
///
/// [sebagian] = sebagian tabel sudah berhasil (cukup peringatan, bukan
/// galat): data yang lolos memang sudah tersimpan.
({String pesan, bool sebagian}) pesanGagalSinkron(HasilSync hasil) {
  if (hasil.sebagian) {
    return (
      pesan: 'Sebagian data belum tersinkron — akan dicoba lagi',
      sebagian: true,
    );
  }
  final alasan = alasanTakPulihSendiri(hasil.sebabTerputus);
  return (
    pesan: alasan == null
        ? 'Gagal menyambungkan ke server'
        : 'Gagal menyegarkan — $alasan',
    sebagian: false,
  );
}

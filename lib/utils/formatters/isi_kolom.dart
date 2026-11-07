import 'package:flutter/widgets.dart';

/// Isi [kolom] dengan [teks] dan taruh kursornya di akhir.
///
/// `controller.text = ...` membuat posisi kursor tidak jelas: ketikan
/// berikutnya bisa masuk ke DEPAN angka, mis. tombol Rp 20.000 lalu angka 5
/// jadi 520.000, dan Hapus tidak bekerja sampai kolomnya diketuk (audit 6 Nov
/// nomor 33).
void isiKolom(TextEditingController kolom, String teks) {
  kolom.value = TextEditingValue(
    text: teks,
    selection: TextSelection.collapsed(offset: teks.length),
  );
}

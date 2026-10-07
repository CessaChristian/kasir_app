import 'dart:async';

import 'supabase_service.dart';

/// Benarkah server bisa dihubungi SEKARANG?
///
/// [SupabaseService.online] hanya berarti "klien sudah disiapkan dan sesinya
/// masih berlaku" — HP tanpa sinyal pun bisa bernilai true. Untuk halaman
/// yang wajib online (Kelola Kasir), yang ditanyakan harus server sungguhan:
/// satu permintaan kecil dengan batas waktu.
Future<bool> serverTerjangkau({
  Duration batas = const Duration(seconds: 5),
}) async {
  final supabase = SupabaseService.instance;
  if (!supabase.online) return false;
  try {
    await supabase.client!.from('users').select('id').limit(1).timeout(batas);
    return true;
  } catch (_) {
    return false;
  }
}

import 'package:flutter/widgets.dart';

import '../auth/session_manager.dart';

/// Setiap sentuhan di layar mana pun — termasuk lembar bawah dan dialog —
/// dihitung kabar "masih dipakai" ([SessionManager.catatSentuhan]).
///
/// Dipasang di atas Navigator (`MaterialApp.builder`) supaya semua rute
/// ikut. Sentuhannya tetap diteruskan apa adanya.
class PencatatSentuhan extends StatelessWidget {
  final Widget child;

  const PencatatSentuhan({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (_) => SessionManager.instance.catatSentuhan(),
    child: child,
  );
}

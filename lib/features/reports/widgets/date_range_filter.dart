import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class DateRangeFilter extends StatelessWidget {
  final DateTime startDate;
  final DateTime endDate;
  final void Function(DateTime start, DateTime end) onChanged;

  const DateRangeFilter({
    super.key,
    required this.startDate,
    required this.endDate,
    required this.onChanged,
  });

  String _fmt(DateTime d) => DateFormat('dd MMM yyyy', 'id_ID').format(d);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _pick(context),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
          color: Colors.white,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calendar_today_outlined,
                size: 16, color: Colors.grey),
            const SizedBox(width: 8),
            Text(
              '${_fmt(startDate)} — ${_fmt(endDate)}',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.arrow_drop_down, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: startDate, end: endDate),
      locale: const Locale('id', 'ID'),
    );
    if (picked != null) {
      onChanged(picked.start, picked.end);
    }
  }
}

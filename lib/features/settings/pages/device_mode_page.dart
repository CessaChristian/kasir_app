import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../data/business_context.dart';

/// Settings page untuk owner lock device ke 1 business (Cashier Mode)
/// atau biarkan bebas pilih business (Owner Mode).
///
/// Hanya bisa diakses kalau user punya permission 'manage_business'.
/// Cashier mode: widget BusinessSwitcher tidak tampil, device
/// otomatis masuk ke business yang di-lock.
class DeviceModePage extends StatefulWidget {
  const DeviceModePage({super.key});

  @override
  State<DeviceModePage> createState() => _DeviceModePageState();
}

class _DeviceModePageState extends State<DeviceModePage> {
  static const _modeKey = 'device_mode'; // 'owner' | 'cashier'
  static const _lockedBizKey = 'device_locked_business_id';

  String _mode = 'owner';
  String? _lockedBusinessId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _mode = prefs.getString(_modeKey) ?? 'owner';
      _lockedBusinessId = prefs.getString(_lockedBizKey);
      _loading = false;
    });
  }

  Future<void> _saveMode(String mode, {String? lockedBizId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, mode);
    if (lockedBizId != null) {
      await prefs.setString(_lockedBizKey, lockedBizId);
    } else {
      await prefs.remove(_lockedBizKey);
    }
    setState(() {
      _mode = mode;
      _lockedBusinessId = lockedBizId;
    });
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final businesses = BusinessContext.instance.availableBusinesses;

    final lockedBizName = _lockedBusinessId != null && businesses.isNotEmpty
        ? businesses
            .firstWhere(
              (b) => b.id == _lockedBusinessId,
              orElse: () => businesses.first,
            )
            .name
        : null;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F5F0),
      appBar: AppBar(
        title: const Text('Mode Device'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: RadioGroup<String>(
                    groupValue: _mode,
                    onChanged: (value) {
                      if (value == 'cashier') {
                        if (businesses.isEmpty) return;
                        _showBizPicker(businesses);
                      } else {
                        _saveMode('owner');
                      }
                    },
                    child: Column(
                      children: [
                        RadioListTile<String>(
                          title: const Text('Owner Mode'),
                          subtitle:
                              const Text('Device bisa switch antar business'),
                          value: 'owner',
                          activeColor: primary,
                        ),
                        Divider(
                          height: 1,
                          color: Colors.grey.shade200,
                          indent: 16,
                          endIndent: 16,
                        ),
                        RadioListTile<String>(
                          title: const Text('Cashier Mode'),
                          subtitle: Text(lockedBizName != null
                              ? 'Terkunci ke: $lockedBizName'
                              : 'Pilih business untuk dikunci'),
                          value: 'cashier',
                          activeColor: primary,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Cashier Mode mengunci device ke 1 business. Kasir tidak bisa ganti business. Owner bisa ubah mode ini kapan saja.',
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
    );
  }

  void _showBizPicker(List businesses) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Lock ke business mana?',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          ...businesses.map(
            (b) => ListTile(
              title: Text(b.name as String),
              onTap: () {
                Navigator.pop(context);
                _saveMode('cashier', lockedBizId: b.id as String);
              },
            ),
          ),
        ],
      ),
    );
  }
}

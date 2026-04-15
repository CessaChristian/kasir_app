import 'package:flutter/material.dart';
import '../../../data/db.dart';
import '../../../data/app_database.dart';
import '../../auth/repositories/permission_repository.dart';

/// Page to manage permissions for a specific user (cashier)
class UserPermissionsPage extends StatefulWidget {
  final User user;

  const UserPermissionsPage({
    super.key,
    required this.user,
  });

  @override
  State<UserPermissionsPage> createState() => _UserPermissionsPageState();
}

class _UserPermissionsPageState extends State<UserPermissionsPage> {
  final _permissionRepo = PermissionRepository(db);
  
  List<Permission> _allPermissions = [];
  Map<String, bool> _userPermissions = {};
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final allPerms = await _permissionRepo.getAllPermissions();
      final userPerms = await _permissionRepo.getUserPermissions(widget.user.id);

      setState(() {
        _allPermissions = allPerms;
        _userPermissions = userPerms;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading permissions: $e')),
      );
    }
  }

  Future<void> _savePermissions() async {
    setState(() => _isSaving = true);

    try {
      await _permissionRepo.setUserPermissions(
        userId: widget.user.id,
        permissions: _userPermissions,
      );

      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Permissions updated successfully'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Permissions: ${widget.user.username}'),
        centerTitle: true,
        actions: [
          if (!_isLoading)
            TextButton(
              onPressed: _isSaving ? null : _savePermissions,
              child: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('SAVE'),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _allPermissions.length,
              itemBuilder: (context, index) {
                final perm = _allPermissions[index];
                final isEnabled = _userPermissions[perm.code] ?? false;

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: SwitchListTile(
                    value: isEnabled,
                    onChanged: (newValue) {
                      setState(() {
                        _userPermissions[perm.code] = newValue;
                      });
                    },
                    title: Text(
                      perm.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      perm.description,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    secondary: Icon(
                      _getIconForPermission(perm.code),
                      color: isEnabled
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              },
            ),
    );
  }

  IconData _getIconForPermission(String code) {
    switch (code) {
      case 'open_close_shift':
        return Icons.access_time;
      case 'create_transaction':
        return Icons.point_of_sale;
      case 'view_history':
        return Icons.history;
      case 'view_report':
        return Icons.analytics;
      case 'manage_products':
        return Icons.inventory;
      case 'manage_cashiers':
        return Icons.people;
      default:
        return Icons.security;
    }
  }
}

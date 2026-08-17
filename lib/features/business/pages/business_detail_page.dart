import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../data/app_database.dart';
import '../../../data/business_context.dart';
import '../../../data/db.dart';
import '../../../shared/auth/session_manager.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/business_logo.dart';

/// Profil business: edit alamat & telepon (dipakai di nota) serta ganti/hapus
/// logo. Nama business read-only — hardcode dari kode (spec REVISI 2 D5).
///
/// Bagian "Aktivasi" dihapus saat aplikasi difokuskan ke satu business.
/// Struktur datanya (tabel `businesses`, kolom `business_id`, BusinessContext)
/// SENGAJA dipertahankan supaya business kedua tinggal dinyalakan kembali
/// tanpa migrasi apa pun.
class BusinessDetailPage extends StatefulWidget {
  final String businessId;
  const BusinessDetailPage({super.key, required this.businessId});

  @override
  State<BusinessDetailPage> createState() => _BusinessDetailPageState();
}

class _BusinessDetailPageState extends State<BusinessDetailPage> {
  BusinessesData? _business;
  final _addressC = TextEditingController();
  final _phoneC = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _addressC.dispose();
    _phoneC.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final b = await (db.select(db.businesses)
          ..where((t) => t.id.equals(widget.businessId)))
        .getSingleOrNull();
    if (!mounted || b == null) return;
    setState(() {
      _business = b;
      _addressC.text = b.address ?? '';
      _phoneC.text = b.phone ?? '';
    });
  }

  Future<void> _saveInfo() async {
    setState(() => _saving = true);
    try {
      await db.updateBusiness(
        id: widget.businessId,
        address: _addressC.text.trim(),
        phone: _phoneC.text.trim(),
      );
      await _refreshContext();
      if (!mounted) return;
      AppToast.success(context, 'Informasi business disimpan');
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Gagal menyimpan: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _refreshContext() async {
    final userId = SessionManager.instance.currentUserId;
    if (userId != null) {
      await BusinessContext.instance.refreshActiveBusiness(userId: userId);
    }
    await _load();
  }

  Future<void> _pickLogo() async {
    try {
      final picked =
          await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null) return;

      final docsDir = await getApplicationDocumentsDirectory();
      final logosDir = Directory('${docsDir.path}/logos');
      if (!logosDir.existsSync()) logosDir.createSync(recursive: true);
      final ext = picked.path.split('.').last;
      final target = File(
          '${logosDir.path}/${widget.businessId}_${DateTime.now().millisecondsSinceEpoch}.$ext');
      await File(picked.path).copy(target.path);

      await db.updateBusiness(
        id: widget.businessId,
        logoPath: target.path,
        logoPathSet: true,
      );
      await _refreshContext();
      if (!mounted) return;
      AppToast.success(context, 'Logo diganti');
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Gagal mengganti logo: $e');
    }
  }

  Future<void> _removeLogo() async {
    try {
      await db.updateBusiness(
        id: widget.businessId,
        logoPath: null,
        logoPathSet: true,
      );
      await _refreshContext();
      if (!mounted) return;
      AppToast.success(context, 'Logo dihapus');
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Gagal menghapus logo: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final b = _business;
    if (b == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Business')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(b.name)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Logo ──
            _sectionCard(
              title: 'Logo',
              child: Column(
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.all(8),
                    child: BusinessLogo(business: b, size: 80),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _pickLogo,
                        icon: const Icon(Icons.photo_library_rounded, size: 18),
                        label: const Text('Ganti Logo'),
                      ),
                      if (b.logoPath != null) ...[
                        const SizedBox(width: 10),
                        TextButton(
                          onPressed: _removeLogo,
                          child: const Text('Hapus Logo',
                              style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ── Info nota ──
            _sectionCard(
              title: 'Informasi Nota',
              child: Column(
                children: [
                  TextField(
                    controller: _addressC,
                    decoration: const InputDecoration(
                      labelText: 'Alamat (tampil di nota)',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phoneC,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'No. Telepon',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saving ? null : _saveInfo,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(_saving ? 'Menyimpan...' : 'Simpan'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

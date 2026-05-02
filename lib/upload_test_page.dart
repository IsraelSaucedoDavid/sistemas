import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_theme.dart';
import 'assets_page.dart';
import 'maintenance_page.dart';

class UploadTestPage extends StatefulWidget {
  const UploadTestPage({super.key});

  @override
  State<UploadTestPage> createState() => _UploadTestPageState();
}

class _UploadTestPageState extends State<UploadTestPage> {
  final _emailCtrl = TextEditingController(text: 'test@ti.local');
  final _passwordCtrl = TextEditingController();
  final _bucketCtrl = TextEditingController(text: 'assets-photos');
  final _descriptionCtrl = TextEditingController();

  List<_AssetOption> _assets = [];
  String? _selectedAssetId;
  Uint8List? _selectedBytes;
  String? _selectedName;
  bool _loading = false;
  bool _loadingAssets = false;
  String _status = 'Sin acciones por ahora.';

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _bucketCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (_client.auth.currentSession != null) {
      _loadAssets();
    }
  }

  Future<void> _signIn() async {
    setState(() {
      _loading = true;
      _status = 'Iniciando sesion...';
    });

    try {
      final response = await _client.auth.signInWithPassword(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );

      if (response.session != null) {
        setState(() => _status = 'Login correcto. Cargando activos...');
        await _loadAssets();
      } else {
        setState(() => _status = 'No se pudo iniciar sesion.');
      }
    } on AuthException catch (e) {
      setState(() => _status = 'Error auth: ${e.message}');
    } catch (e) {
      setState(() => _status = 'Error inesperado: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    final file = result?.files.single;

    if (file == null || file.bytes == null) {
      setState(() => _status = 'No se selecciono archivo.');
      return;
    }

    setState(() {
      _selectedBytes = file.bytes;
      _selectedName = file.name;
      _status = 'Archivo listo: ${file.name}';
    });
  }

  Future<void> _loadAssets() async {
    if (_client.auth.currentSession == null) {
      setState(() => _status = 'Inicia sesion para cargar activos.');
      return;
    }

    setState(() => _loadingAssets = true);
    try {
      final response = await _client
          .schema('sistema')
          .from('assets')
          .select('id, asset_tag, serial_number')
          .order('asset_tag');

      final items = (response as List<dynamic>)
          .map((item) => _AssetOption.fromMap(item as Map<String, dynamic>))
          .toList();

      setState(() {
        _assets = items;
        if (_assets.isNotEmpty) {
          final exists = _assets.any((x) => x.id == _selectedAssetId);
          _selectedAssetId = exists ? _selectedAssetId : _assets.first.id;
          _status = 'Activos cargados: ${_assets.length}.';
        } else {
          _selectedAssetId = null;
          _status = 'No hay activos en sistema.assets.';
        }
      });
    } on PostgrestException catch (e) {
      setState(() => _status = 'Error cargando activos: ${e.message}');
    } catch (e) {
      setState(() => _status = 'Error inesperado cargando activos: $e');
    } finally {
      if (mounted) {
        setState(() => _loadingAssets = false);
      }
    }
  }

  Future<void> _uploadFile() async {
    if (_selectedBytes == null || _selectedName == null) {
      setState(() => _status = 'Primero selecciona un archivo.');
      return;
    }

    if (_client.auth.currentSession == null) {
      setState(() => _status = 'Primero inicia sesion.');
      return;
    }

    if (_selectedAssetId == null) {
      setState(() => _status = 'Selecciona un activo antes de subir.');
      return;
    }

    setState(() {
      _loading = true;
      _status = 'Subiendo archivo...';
    });

    try {
      final safeName = _selectedName!.replaceAll(' ', '_');
      final normalizedBucket = _bucketCtrl.text.trim().toLowerCase();
      final path =
          'assets/test/${DateTime.now().millisecondsSinceEpoch}_$safeName';

      await _client.storage.from(normalizedBucket).uploadBinary(
            path,
            _selectedBytes!,
            fileOptions: const FileOptions(upsert: false),
          );

      final docType = normalizedBucket == 'assets-docs' ? 'documento' : 'foto';
      await _client.schema('sistema').from('asset_documents').insert({
        'asset_id': _selectedAssetId,
        'file_path': path,
        'file_type': docType,
        'description': _descriptionCtrl.text.trim().isEmpty
            ? null
            : _descriptionCtrl.text.trim(),
      });

      setState(() => _status = 'Subida OK y registro guardado en BD.');
    } on StorageException catch (e) {
      setState(() => _status = 'Error storage: ${e.message}');
    } on PostgrestException catch (e) {
      setState(() => _status = 'Error BD: ${e.message}');
    } catch (e) {
      setState(() => _status = 'Error inesperado: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _signOut() async {
    await _client.auth.signOut();
    setState(() => _status = 'Sesion cerrada.');
  }

  Future<void> _openAssetsPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AssetsPage()),
    );
    await _loadAssets();
  }

  Future<void> _openMaintenancePage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MaintenancePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Centro de Servicio TI'),
        actions: [
          const ThemeToggleButton(),
          IconButton(
            onPressed: (_loading || _loadingAssets) ? null : _openMaintenancePage,
            tooltip: 'Mantenimientos',
            icon: const Icon(Icons.build_circle_outlined),
          ),
          IconButton(
            onPressed: (_loading || _loadingAssets) ? null : _openAssetsPage,
            tooltip: 'Gestionar activos',
            icon: const Icon(Icons.inventory_2_outlined),
          ),
        ],
      ),
      body: GradientBody(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SectionCard(
              child: Column(
                children: [
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _bucketCtrl,
                    decoration: const InputDecoration(labelText: 'Bucket'),
                  ),
                  const SizedBox(height: 12),
                  InputDecorator(
                    decoration: const InputDecoration(labelText: 'Activo'),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _selectedAssetId,
                        hint: const Text('Selecciona un activo'),
                        items: _assets
                            .map(
                              (asset) => DropdownMenuItem<String>(
                                value: asset.id,
                                child: Text(asset.label),
                              ),
                            )
                            .toList(),
                        onChanged: (_loading || _loadingAssets)
                            ? null
                            : (value) => setState(() => _selectedAssetId = value),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _descriptionCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Descripcion del archivo (opcional)',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton(
                        onPressed: _loading ? null : _signIn,
                        child: const Text('1) Login'),
                      ),
                      ElevatedButton(
                        onPressed: (_loading || _loadingAssets) ? null : _loadAssets,
                        child: const Text('Recargar activos'),
                      ),
                      ElevatedButton(
                        onPressed: _loading ? null : _pickFile,
                        child: const Text('2) Elegir archivo'),
                      ),
                      ElevatedButton(
                        onPressed: _loading ? null : _uploadFile,
                        child: const Text('3) Subir'),
                      ),
                      OutlinedButton(
                        onPressed: _loading ? null : _signOut,
                        child: const Text('Cerrar sesion'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Activos disponibles: ${_assets.length}'),
                  const SizedBox(height: 8),
                  Text('Archivo seleccionado: ${_selectedName ?? 'ninguno'}'),
                  const SizedBox(height: 8),
                  Text('Estado: $_status'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssetOption {
  final String id;
  final String label;

  const _AssetOption({
    required this.id,
    required this.label,
  });

  factory _AssetOption.fromMap(Map<String, dynamic> map) {
    final id = map['id']?.toString() ?? '';
    final tag = map['asset_tag']?.toString() ?? 'Sin tag';
    final serial = map['serial_number']?.toString();
    final label = (serial == null || serial.isEmpty) ? tag : '$tag - $serial';

    return _AssetOption(
      id: id,
      label: label,
    );
  }
}

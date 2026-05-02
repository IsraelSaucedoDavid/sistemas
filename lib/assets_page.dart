import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';

import 'app_theme.dart';
import 'photo_manager_page.dart';
import 'photo_upload_helper.dart';

class AssetsPage extends StatefulWidget {
  const AssetsPage({super.key});

  @override
  State<AssetsPage> createState() => _AssetsPageState();
}

class _AssetsPageState extends State<AssetsPage> {
  final _assetTagCtrl = TextEditingController();
  final _serialCtrl = TextEditingController();
  final _brandCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  final List<String> _statusOptions = ['activo', 'mantenimiento', 'baja'];

  List<_AssetTypeOption> _assetTypes = [];
  List<_AssetItem> _assets = [];
  List<DraftPhoto> _pendingPhotos = [];
  String? _selectedTypeId;
  String _selectedStatus = 'activo';
  bool _loading = false;
  bool _saving = false;
  String _statusText = 'Carga de activos pendiente.';

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _assetTagCtrl.dispose();
    _serialCtrl.dispose();
    _brandCtrl.dispose();
    _modelCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (_client.auth.currentSession == null) {
      setState(() => _statusText = 'Inicia sesion para gestionar activos.');
      return;
    }

    setState(() => _loading = true);
    try {
      final typesResponse = await _client
          .schema('sistema')
          .from('asset_types')
          .select('id, name')
          .order('name');
      final assetsResponse = await _client
          .schema('sistema')
          .from('assets')
          .select(
            'id, asset_tag, serial_number, brand, model, status, '
            'asset_type_id, notes',
          )
          .order('created_at', ascending: false);

      final types = (typesResponse as List<dynamic>)
          .map((e) => _AssetTypeOption.fromMap(e as Map<String, dynamic>))
          .toList();
      final assets = (assetsResponse as List<dynamic>)
          .map((e) => _AssetItem.fromMap(e as Map<String, dynamic>))
          .toList();

      setState(() {
        _assetTypes = types;
        _assets = assets;
        if (_assetTypes.isNotEmpty) {
          final exists = _assetTypes.any((t) => t.id == _selectedTypeId);
          _selectedTypeId = exists ? _selectedTypeId : _assetTypes.first.id;
        } else {
          _selectedTypeId = null;
        }
        _statusText = 'Activos cargados: ${_assets.length}.';
      });
    } on PostgrestException catch (e) {
      setState(() => _statusText = 'Error cargando datos: ${e.message}');
    } catch (e) {
      setState(() => _statusText = 'Error inesperado: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<bool> _createAsset() async {
    final typeId = _selectedTypeId;
    final tag = _assetTagCtrl.text.trim();
    final serial = _serialCtrl.text.trim();

    if (typeId == null) {
      setState(() => _statusText = 'No hay tipos de activo disponibles.');
      return false;
    }
    if (tag.isEmpty) {
      setState(() => _statusText = 'Captura al menos el Asset Tag.');
      return false;
    }

    setState(() => _saving = true);
    try {
      final created = await _client.schema('sistema').from('assets').insert({
        'asset_tag': tag,
        'serial_number': serial.isEmpty ? null : serial,
        'asset_type_id': typeId,
        'brand': _brandCtrl.text.trim().isEmpty ? null : _brandCtrl.text.trim(),
        'model': _modelCtrl.text.trim().isEmpty ? null : _modelCtrl.text.trim(),
        'status': _selectedStatus,
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      }).select('id').single();
      final createdId = created['id']?.toString();

      _assetTagCtrl.clear();
      _serialCtrl.clear();
      _brandCtrl.clear();
      _modelCtrl.clear();
      _notesCtrl.clear();

      var statusMsg = 'Activo creado correctamente.';
      if (createdId != null && _pendingPhotos.isNotEmpty) {
        final uploadResult = await PhotoUploadHelper.uploadDraftPhotos(
          assetId: createdId,
          photos: _pendingPhotos,
          description: 'Foto inicial del activo',
        );
        statusMsg = uploadResult.ok
            ? '$statusMsg ${uploadResult.message}'
            : '$statusMsg Error en fotos: ${uploadResult.message}';
        if (uploadResult.ok) {
          _pendingPhotos = [];
        }
      }

      setState(() => _statusText = statusMsg);
      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Activo creado y listado actualizado.')),
        );
      }
      return true;
    } on PostgrestException catch (e) {
      setState(() => _statusText = 'Error al crear activo: ${e.message}');
    } catch (e) {
      setState(() => _statusText = 'Error inesperado: $e');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
    return false;
  }

  void _resetCreateForm() {
    _assetTagCtrl.clear();
    _serialCtrl.clear();
    _brandCtrl.clear();
    _modelCtrl.clear();
    _notesCtrl.clear();
    _pendingPhotos = [];
    _selectedStatus = 'activo';
    if (_assetTypes.isNotEmpty) {
      _selectedTypeId = _assetTypes.first.id;
    }
  }

  Future<void> _openCreateAssetDialog() async {
    _resetCreateForm();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> pickPhotos() async {
              final result = await FilePicker.platform.pickFiles(
                withData: true,
                allowMultiple: true,
              );
              final files = result?.files.where((f) => f.bytes != null).toList() ?? [];
              if (files.isEmpty) return;
              setState(() {
                _pendingPhotos.addAll(
                  files.map(
                    (f) => DraftPhoto(
                      bytes: f.bytes!,
                      fileName: f.name.isEmpty ? 'foto.jpg' : f.name,
                    ),
                  ),
                );
              });
              setSheetState(() {});
            }

            Future<void> takePhoto() async {
              final picker = ImagePicker();
              final image = await picker.pickImage(
                source: ImageSource.camera,
                imageQuality: 85,
              );
              if (image == null) return;
              final bytes = await image.readAsBytes();
              setState(() {
                _pendingPhotos.add(
                  DraftPhoto(
                    bytes: bytes,
                    fileName: image.name.isEmpty ? 'camera.jpg' : image.name,
                  ),
                );
              });
              setSheetState(() {});
            }

            void removePhoto(int index) {
              setState(() => _pendingPhotos.removeAt(index));
              setSheetState(() {});
            }

            Future<void> submit() async {
              final ok = await _createAsset();
              if (!mounted) return;
              if (ok) {
                Navigator.of(this.context).pop();
              }
              setSheetState(() {});
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                  top: 8,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nuevo activo',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _assetTagCtrl,
                        decoration: const InputDecoration(labelText: 'Asset Tag *'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _serialCtrl,
                        decoration: const InputDecoration(labelText: 'Numero de serie'),
                      ),
                      const SizedBox(height: 12),
                      InputDecorator(
                        decoration: const InputDecoration(labelText: 'Tipo de activo *'),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: _selectedTypeId,
                            hint: const Text('Selecciona tipo'),
                            items: _assetTypes
                                .map(
                                  (type) => DropdownMenuItem<String>(
                                    value: type.id,
                                    child: Text(type.name),
                                  ),
                                )
                                .toList(),
                            onChanged: _saving
                                ? null
                                : (value) {
                                    setState(() => _selectedTypeId = value);
                                    setSheetState(() {});
                                  },
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _brandCtrl,
                        decoration: const InputDecoration(labelText: 'Marca'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _modelCtrl,
                        decoration: const InputDecoration(labelText: 'Modelo'),
                      ),
                      const SizedBox(height: 12),
                      InputDecorator(
                        decoration: const InputDecoration(labelText: 'Estatus'),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: _selectedStatus,
                            items: _statusOptions
                                .map(
                                  (status) => DropdownMenuItem<String>(
                                    value: status,
                                    child: Text(_statusLabel(status)),
                                  ),
                                )
                                .toList(),
                            onChanged: _saving
                                ? null
                                : (value) {
                                    if (value != null) {
                                      setState(() => _selectedStatus = value);
                                      setSheetState(() {});
                                    }
                                  },
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _notesCtrl,
                        minLines: 2,
                        maxLines: 3,
                        decoration: const InputDecoration(labelText: 'Notas'),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Fotos (${_pendingPhotos.length})',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _saving ? null : pickPhotos,
                            icon: const Icon(Icons.photo_library_outlined),
                            label: const Text('Agregar 1 o mas'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _saving ? null : takePhoto,
                            icon: const Icon(Icons.photo_camera_outlined),
                            label: const Text('Tomar foto'),
                          ),
                        ],
                      ),
                      if (_pendingPhotos.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: List.generate(
                            _pendingPhotos.length,
                            (index) => Stack(
                              clipBehavior: Clip.none,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.memory(
                                    _pendingPhotos[index].bytes,
                                    width: 64,
                                    height: 64,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned(
                                  top: -8,
                                  right: -8,
                                  child: Material(
                                    color: Colors.red.shade600,
                                    shape: const CircleBorder(),
                                    child: InkWell(
                                      customBorder: const CircleBorder(),
                                      onTap: _saving ? null : () => removePhoto(index),
                                      child: const Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Icon(
                                          Icons.close,
                                          size: 14,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _saving ? null : submit,
                        icon: const Icon(Icons.add),
                        label: Text(_saving ? 'Guardando...' : 'Crear activo'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _updateAsset({
    required _AssetItem asset,
    required String assetTag,
    required String serialNumber,
    required String brand,
    required String model,
    required String status,
    required String? assetTypeId,
    required String notes,
  }) async {
    if (assetTag.trim().isEmpty) {
      setState(() => _statusText = 'El Asset Tag no puede estar vacio.');
      return;
    }
    if (assetTypeId == null || assetTypeId.isEmpty) {
      setState(() => _statusText = 'Selecciona un tipo de activo.');
      return;
    }

    setState(() => _saving = true);
    try {
      await _client.schema('sistema').from('assets').update({
        'asset_tag': assetTag.trim(),
        'serial_number': serialNumber.trim().isEmpty ? null : serialNumber.trim(),
        'brand': brand.trim().isEmpty ? null : brand.trim(),
        'model': model.trim().isEmpty ? null : model.trim(),
        'status': status,
        'asset_type_id': assetTypeId,
        'notes': notes.trim().isEmpty ? null : notes.trim(),
      }).eq('id', asset.id);

      setState(() => _statusText = 'Activo actualizado: ${asset.assetTag}.');
      await _loadData();
    } on PostgrestException catch (e) {
      setState(() => _statusText = 'Error al actualizar: ${e.message}');
    } catch (e) {
      setState(() => _statusText = 'Error inesperado: $e');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _markAssetAsBaja(_AssetItem asset) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Marcar como fuera de uso'),
          content: Text(
            'El activo ${asset.assetTag} no se eliminara. '
            'Solo se marcara como baja.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Marcar baja'),
            ),
          ],
        );
      },
    );

    if (confirm != true) {
      return;
    }

    final currentNotes = asset.notes?.trim();
    final marker = 'Marcado como baja/fuera de uso (${DateTime.now()})';
    final mergedNotes = (currentNotes == null || currentNotes.isEmpty)
        ? marker
        : '$currentNotes\n$marker';

    await _updateAsset(
      asset: asset,
      assetTag: asset.assetTag,
      serialNumber: asset.serialNumber ?? '',
      brand: asset.brand ?? '',
      model: asset.model ?? '',
      status: 'baja',
      assetTypeId: asset.assetTypeId,
      notes: mergedNotes,
    );
  }

  Future<void> _openEditDialog(_AssetItem asset) async {
    final formKey = GlobalKey<FormState>();
    final tagCtrl = TextEditingController(text: asset.assetTag);
    final serialCtrl = TextEditingController(text: asset.serialNumber ?? '');
    final brandCtrl = TextEditingController(text: asset.brand ?? '');
    final modelCtrl = TextEditingController(text: asset.model ?? '');
    final notesCtrl = TextEditingController(text: asset.notes ?? '');
    String currentStatus = asset.status;
    String? currentTypeId = asset.assetTypeId;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: Text('Editar ${asset.assetTag}'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: tagCtrl,
                        decoration: const InputDecoration(labelText: 'Asset Tag *'),
                        validator: (value) => (value == null || value.trim().isEmpty)
                            ? 'Requerido'
                            : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: serialCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Numero de serie',
                        ),
                      ),
                      const SizedBox(height: 10),
                      InputDecorator(
                        decoration: const InputDecoration(labelText: 'Tipo de activo'),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: currentTypeId,
                            isExpanded: true,
                            hint: const Text('Selecciona tipo'),
                            items: _assetTypes
                                .map(
                                  (type) => DropdownMenuItem<String>(
                                    value: type.id,
                                    child: Text(type.name),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              setLocalState(() => currentTypeId = value);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: brandCtrl,
                        decoration: const InputDecoration(labelText: 'Marca'),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: modelCtrl,
                        decoration: const InputDecoration(labelText: 'Modelo'),
                      ),
                      const SizedBox(height: 10),
                      InputDecorator(
                        decoration: const InputDecoration(labelText: 'Estatus'),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: currentStatus,
                            isExpanded: true,
                            items: _statusOptions
                                .map(
                                  (status) => DropdownMenuItem<String>(
                                    value: status,
                                    child: Text(_statusLabel(status)),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setLocalState(() => currentStatus = value);
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: notesCtrl,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(labelText: 'Notas'),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    if (formKey.currentState?.validate() == true) {
                      Navigator.of(context).pop(true);
                    }
                  },
                  child: const Text('Guardar cambios'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved == true) {
      await _updateAsset(
        asset: asset,
        assetTag: tagCtrl.text,
        serialNumber: serialCtrl.text,
        brand: brandCtrl.text,
        model: modelCtrl.text,
        status: currentStatus,
        assetTypeId: currentTypeId,
        notes: notesCtrl.text,
      );
    }

    tagCtrl.dispose();
    serialCtrl.dispose();
    brandCtrl.dispose();
    modelCtrl.dispose();
    notesCtrl.dispose();
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'activo':
        return 'Activo';
      case 'mantenimiento':
        return 'Descompuesto / Mantenimiento';
      case 'baja':
        return 'Fuera de uso / Baja';
      default:
        return status;
    }
  }

  Future<void> _openAssetPhotoManager(_AssetItem asset) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhotoManagerPage(
          title: 'Fotos de ${asset.assetTag}',
          assetId: asset.id,
        ),
      ),
    );
    setState(() => _statusText = 'Gestor de fotos cerrado.');
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'activo':
        return Colors.green.shade700;
      case 'mantenimiento':
        return Colors.orange.shade700;
      case 'baja':
        return Colors.red.shade700;
      default:
        return Colors.grey.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activos TI'),
        actions: [
          const ThemeToggleButton(),
          IconButton(
            onPressed: (_loading || _saving) ? null : _loadData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: GradientBody(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SectionCard(
              child: Text(
                _statusText,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          Text(
            'Listado de activos (${_assets.length})',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (_assets.isEmpty)
            const Text('No hay activos para mostrar.')
          else
            ..._assets.map(
              (asset) => Card(
                child: ListTile(
                  leading: Icon(
                    Icons.computer,
                    color: _statusColor(asset.status),
                  ),
                  title: Text(asset.assetTag),
                  subtitle: Text(
                    'Serie: ${asset.serialNumber ?? '-'} | '
                    'Marca: ${asset.brand ?? '-'} | '
                    'Modelo: ${asset.model ?? '-'}\n'
                    'Estatus: ${_statusLabel(asset.status)}',
                  ),
                  isThreeLine: true,
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'editar') {
                        _openEditDialog(asset);
                      } else if (value == 'baja') {
                        _markAssetAsBaja(asset);
                      } else if (value == 'foto') {
                        _openAssetPhotoManager(asset);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem<String>(
                        value: 'foto',
                        child: Text('Gestionar fotos'),
                      ),
                      PopupMenuItem<String>(
                        value: 'editar',
                        child: Text('Editar'),
                      ),
                      PopupMenuItem<String>(
                        value: 'baja',
                        child: Text('Marcar fuera de uso (baja)'),
                      ),
                    ],
                  ),
                  onTap: () => _openEditDialog(asset),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Agregar activo',
        onPressed: (_loading || _saving) ? null : _openCreateAssetDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _AssetTypeOption {
  final String id;
  final String name;

  const _AssetTypeOption({
    required this.id,
    required this.name,
  });

  factory _AssetTypeOption.fromMap(Map<String, dynamic> map) {
    return _AssetTypeOption(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? 'Sin nombre',
    );
  }
}

class _AssetItem {
  final String id;
  final String assetTag;
  final String? serialNumber;
  final String? brand;
  final String? model;
  final String status;
  final String? assetTypeId;
  final String? notes;

  const _AssetItem({
    required this.id,
    required this.assetTag,
    required this.serialNumber,
    required this.brand,
    required this.model,
    required this.status,
    required this.assetTypeId,
    required this.notes,
  });

  factory _AssetItem.fromMap(Map<String, dynamic> map) {
    return _AssetItem(
      id: map['id']?.toString() ?? '',
      assetTag: map['asset_tag']?.toString() ?? 'Sin tag',
      serialNumber: map['serial_number']?.toString(),
      brand: map['brand']?.toString(),
      model: map['model']?.toString(),
      status: map['status']?.toString() ?? 'activo',
      assetTypeId: map['asset_type_id']?.toString(),
      notes: map['notes']?.toString(),
    );
  }
}

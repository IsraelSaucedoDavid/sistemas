import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';

import 'app_theme.dart';
import 'asset_models.dart';
import 'asset_details_page.dart';
import 'asset_edit_page.dart';
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

  final List<String> _statusOptions = [
    'activo',
    'libre',
    'mantenimiento',
    'descompuesto',
    'baja'
  ];

  List<AssetTypeOption> _assetTypes = [];
  List<AssetItem> _assets = [];
  List<DraftPhoto> _pendingPhotos = [];
  String? _selectedTypeId;
  String _selectedStatus = 'libre';
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
          .map((e) => AssetTypeOption.fromMap(e as Map<String, dynamic>))
          .toList();
      final assets = (assetsResponse as List<dynamic>)
          .map((e) => AssetItem.fromMap(e as Map<String, dynamic>))
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

  Future<bool> _createAsset({void Function(double)? onProgress}) async {
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
          description: 'Carga inicial de multimedia',
          onProgress: onProgress,
        );
        statusMsg = uploadResult.ok
            ? '$statusMsg ${uploadResult.message}'
            : '$statusMsg Error en archivos: ${uploadResult.message}';
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
            Future<void> pickMedia() async {
              final result = await FilePicker.platform.pickFiles(
                withData: true,
                allowMultiple: true,
                type: FileType.media,
              );
              final files = result?.files.where((f) => f.bytes != null).toList() ?? [];
              if (files.isEmpty) return;
              setState(() {
                _pendingPhotos.addAll(
                  files.map(
                    (f) => DraftPhoto(
                      bytes: f.bytes!,
                      fileName: f.name.isEmpty ? 'media.bin' : f.name,
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
              final progressNotifier = ValueNotifier<double>(0.0);
              showDialog(
                context: this.context,
                barrierDismissible: false,
                builder: (BuildContext c) {
                  return AlertDialog(
                    elevation: 0,
                    backgroundColor: Colors.transparent,
                    content: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(color: Colors.white),
                          const SizedBox(height: 24),
                          ValueListenableBuilder<double>(
                            valueListenable: progressNotifier,
                            builder: (context, val, child) {
                              return Column(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: LinearProgressIndicator(
                                      value: val,
                                      minHeight: 10,
                                      color: Colors.white,
                                      backgroundColor: Colors.white24,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Subiendo multimedia... ${(val * 100).toInt()}%',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );

              final ok = await _createAsset(onProgress: (p) => progressNotifier.value = p);
              if (!mounted) return;
              
              Navigator.of(this.context, rootNavigator: true).pop();

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
                            onPressed: _saving ? null : pickMedia,
                            icon: const Icon(Icons.perm_media_outlined),
                            label: const Text('Multimedia / Videos'),
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
                            (index) {
                              final name = _pendingPhotos[index].fileName.toLowerCase();
                              final isVideo = name.endsWith('.mp4') || name.endsWith('.mov') || name.endsWith('.avi');
                              return Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      width: 64,
                                      height: 64,
                                      color: Colors.black12,
                                      child: isVideo 
                                        ? const Icon(Icons.videocam, color: Colors.blueGrey)
                                        : Image.memory(
                                            _pendingPhotos[index].bytes,
                                            width: 64,
                                            height: 64,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => const Icon(Icons.insert_drive_file_outlined),
                                          ),
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
                              );
                            },
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
    required AssetItem asset,
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

  Future<void> _openQuickStatusDialog(AssetItem asset) async {
    String localStatus = asset.status;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text('Estado de ${asset.assetTag}'),
          content: DropdownButtonFormField<String>(
            value: localStatus,
            decoration: const InputDecoration(labelText: 'Selecciona el nuevo estatus'),
            items: _statusOptions
                .map((s) => DropdownMenuItem(value: s, child: Text(_statusLabel(s))))
                .toList(),
            onChanged: (v) {
              if (v != null) setLocalState(() => localStatus = v);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Actualizar'),
            ),
          ],
        ),
      ),
    );

    if (saved == true && localStatus != asset.status) {
      await _updateAsset(
        asset: asset,
        assetTag: asset.assetTag,
        serialNumber: asset.serialNumber ?? '',
        brand: asset.brand ?? '',
        model: asset.model ?? '',
        status: localStatus,
        assetTypeId: asset.assetTypeId,
        notes: asset.notes ?? '',
      );
    }
  }

  Future<void> _deleteAsset(AssetItem asset) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Eliminar permanentemente', style: TextStyle(color: Colors.red)),
          content: Text(
            'Estas a punto de eliminar el activo ${asset.assetTag}.\n\n'
            'Esta accion no se puede deshacer y borrara completamente el registro de la base de datos.\n\n'
            '¿Deseas continuar?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Si, eliminar'),
            ),
          ],
        );
      },
    );

    if (confirm != true) {
      return;
    }

    setState(() => _saving = true);
    try {
      final assignments = await _client
          .schema('sistema')
          .from('assignments')
          .select('id')
          .eq('asset_id', asset.id)
          .limit(1);

      if ((assignments as List).isNotEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se puede eliminar. El activo tiene historial de asignaciones. Utiliza la opcion de "Marcar como baja".'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
        setState(() => _saving = false);
        return;
      }

      await _client.schema('sistema').from('assets').delete().eq('id', asset.id);

      setState(() => _statusText = 'Activo ${asset.assetTag} eliminado permanentemente.');
      await _loadData();
    } on PostgrestException catch (e) {
      setState(() => _statusText = 'Error al eliminar: ${e.message}');
    } catch (e) {
      setState(() => _statusText = 'Error inesperado: $e');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _openEditPage(AssetItem asset) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AssetEditPage(
          asset: asset,
          assetTypes: _assetTypes,
          statusOptions: _statusOptions,
        ),
      ),
    );

    if (updated == true) {
      await _loadData();
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'funcionando':
        return 'Funcionando';
      case 'libre':
        return 'Libre';
      case 'asignado':
        return 'Asignado';
      case 'mantenimiento':
        return 'En Mantenimiento';
      case 'descompuesto':
        return 'Descompuesto';
      case 'baja':
        return 'Fuera de uso / Baja';
      case 'activo':
        return 'Activo (Antiguo)';
      default:
        return status;
    }
  }

  Future<void> _openAssetPhotoManager(AssetItem asset) async {
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
      case 'funcionando':
        return Colors.green.shade700;
      case 'libre':
        return Colors.blue.shade700;
      case 'asignado':
        return Colors.deepPurple.shade700;
      case 'mantenimiento':
        return Colors.orange.shade700;
      case 'descompuesto':
        return Colors.red.shade700;
      case 'baja':
        return Colors.blueGrey.shade800;
      case 'activo':
        return Colors.green.shade700;
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
              (asset) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
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
                        _openEditPage(asset);
                      } else if (value == 'estatus') {
                        _openQuickStatusDialog(asset);
                      } else if (value == 'eliminar') {
                        _deleteAsset(asset);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem<String>(
                        value: 'editar',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 20),
                            SizedBox(width: 8),
                            Text('Editar información'),
                          ],
                        ),
                      ),
                      PopupMenuItem<String>(
                        value: 'estatus',
                        child: Row(
                          children: [
                            Icon(Icons.sync_alt, size: 20),
                            SizedBox(width: 8),
                            Text('Cambiar estatus'),
                          ],
                        ),
                      ),
                      PopupMenuDivider(),
                      PopupMenuItem<String>(
                        value: 'eliminar',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, size: 20, color: Colors.red),
                            SizedBox(width: 8),
                            Text(
                              'Eliminar definitivamente',
                              style: TextStyle(color: Colors.red),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  onTap: () {
                    final type = _assetTypes.cast<AssetTypeOption?>().firstWhere(
                      (t) => t?.id == asset.assetTypeId,
                      orElse: () => null,
                    );
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AssetDetailsPage(
                          asset: asset,
                          typeName: type?.name,
                          assetTypes: _assetTypes,
                          statusOptions: _statusOptions,
                        ),
                      ),
                    );
                  },
                ),
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


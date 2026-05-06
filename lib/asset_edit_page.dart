import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_theme.dart';
import 'asset_models.dart';
import 'photo_upload_helper.dart';

class AssetEditPage extends StatefulWidget {
  final AssetItem asset;
  final List<AssetTypeOption> assetTypes;
  final List<String> statusOptions;

  const AssetEditPage({
    super.key,
    required this.asset,
    required this.assetTypes,
    required this.statusOptions,
  });

  @override
  State<AssetEditPage> createState() => _AssetEditPageState();
}

class _AssetEditPageState extends State<AssetEditPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _tagCtrl;
  late TextEditingController _serialCtrl;
  late TextEditingController _brandCtrl;
  late TextEditingController _modelCtrl;
  late TextEditingController _notesCtrl;
  late String _selectedStatus;
  late String? _selectedTypeId;
  late List<AssetTypeOption> _localAssetTypes;

  List<PhotoDocument> _photos = [];
  bool _loadingPhotos = false;
  bool _saving = false;
  String _statusMsg = '';

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _tagCtrl = TextEditingController(text: widget.asset.assetTag);
    _serialCtrl = TextEditingController(text: widget.asset.serialNumber ?? '');
    _brandCtrl = TextEditingController(text: widget.asset.brand ?? '');
    _modelCtrl = TextEditingController(text: widget.asset.model ?? '');
    _notesCtrl = TextEditingController(text: widget.asset.notes ?? '');
    _selectedStatus = widget.asset.status;
    _selectedTypeId = widget.asset.assetTypeId;
    _localAssetTypes = List.from(widget.assetTypes);
    _loadPhotos();
  }

  Future<void> _refreshAssetTypes() async {
    try {
      final response = await _client.schema('sistema').from('asset_types').select('id, name').order('name');
      setState(() {
        _localAssetTypes = (response as List<dynamic>)
            .map((e) => AssetTypeOption.fromMap(e as Map<String, dynamic>))
            .toList();
      });
    } catch (e) {
      debugPrint('Error refreshing types: $e');
    }
  }

  Future<void> _showAddAssetTypeDialog() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nuevo tipo de activo'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Nombre del tipo',
            hintText: 'Ej: Laptop, Monitor...',
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Agregar'),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      setState(() => _saving = true);
      try {
        final result = await _client.schema('sistema').from('asset_types').insert({
          'name': name,
        }).select().single();

        final newType = AssetTypeOption.fromMap(result);
        
        await _refreshAssetTypes();
        setState(() {
          _selectedTypeId = newType.id;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Tipo "$name" agregado')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      } finally {
        setState(() => _saving = false);
      }
    }
  }

  @override
  void dispose() {
    _tagCtrl.dispose();
    _serialCtrl.dispose();
    _brandCtrl.dispose();
    _modelCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPhotos() async {
    setState(() => _loadingPhotos = true);
    try {
      final photos = await PhotoUploadHelper.fetchPhotos(assetId: widget.asset.id);
      setState(() => _photos = photos);
    } catch (e) {
      debugPrint('Error loading photos: $e');
    } finally {
      if (mounted) {
        setState(() => _loadingPhotos = false);
      }
    }
  }

  Future<void> _uploadPhotos() async {
    setState(() => _statusMsg = 'Subiendo fotos...');
    final result = await PhotoUploadHelper.uploadPhotosFromPicker(
      assetId: widget.asset.id,
    );
    if (!mounted) return;
    setState(() => _statusMsg = result.message);
    if (result.ok) {
      await _loadPhotos();
    }
  }

  Future<void> _takePhoto() async {
    setState(() => _statusMsg = 'Abriendo camara...');
    final result = await PhotoUploadHelper.captureAndUploadPhoto(
      assetId: widget.asset.id,
    );
    if (!mounted) return;
    setState(() => _statusMsg = result.message);
    if (result.ok) {
      await _loadPhotos();
    }
  }

  Future<void> _deletePhoto(PhotoDocument doc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar foto'),
        content: const Text('¿Deseas eliminar esta foto permanentemente?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _statusMsg = 'Eliminando foto...');
    final result = await PhotoUploadHelper.deletePhoto(
      documentId: doc.id,
      filePath: doc.filePath,
    );
    if (!mounted) return;
    setState(() => _statusMsg = result.message);
    if (result.ok) {
      await _loadPhotos();
    }
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      await _client.schema('sistema').from('assets').update({
        'asset_tag': _tagCtrl.text.trim(),
        'serial_number': _serialCtrl.text.trim().isEmpty ? null : _serialCtrl.text.trim(),
        'brand': _brandCtrl.text.trim().isEmpty ? null : _brandCtrl.text.trim(),
        'model': _modelCtrl.text.trim().isEmpty ? null : _modelCtrl.text.trim(),
        'status': _selectedStatus,
        'asset_type_id': _selectedTypeId,
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      }).eq('id', widget.asset.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Activo actualizado correctamente')),
        );
        Navigator.pop(context, true);
      }
    } on PostgrestException catch (e) {
      setState(() => _statusMsg = 'Error DB: ${e.message}');
    } catch (e) {
      setState(() => _statusMsg = 'Error: $e');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'funcionando': return 'Funcionando';
      case 'libre': return 'Libre';
      case 'asignado': return 'Asignado';
      case 'mantenimiento': return 'En Mantenimiento';
      case 'descompuesto': return 'Descompuesto';
      case 'baja': return 'Fuera de uso / Baja';
      case 'activo': return 'Activo (Antiguo)';
      default: return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Editar ${widget.asset.assetTag}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _saving ? null : _saveChanges,
            tooltip: 'Guardar cambios',
          ),
        ],
      ),
      body: GradientBody(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionCard(
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _tagCtrl,
                        decoration: const InputDecoration(labelText: 'Asset Tag *'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _serialCtrl,
                        decoration: const InputDecoration(labelText: 'Numero de serie'),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _selectedTypeId,
                              decoration: const InputDecoration(labelText: 'Tipo de activo'),
                              items: _localAssetTypes
                                  .map((t) => DropdownMenuItem(value: t.id, child: Text(t.name)))
                                  .toList(),
                              onChanged: (v) => setState(() => _selectedTypeId = v),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: IconButton.filledTonal(
                              onPressed: _saving ? null : _showAddAssetTypeDialog,
                              icon: const Icon(Icons.add),
                              tooltip: 'Agregar nuevo tipo',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _brandCtrl,
                        decoration: const InputDecoration(labelText: 'Marca'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _modelCtrl,
                        decoration: const InputDecoration(labelText: 'Modelo'),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedStatus,
                        decoration: const InputDecoration(labelText: 'Estatus'),
                        items: widget.statusOptions
                            .map((s) => DropdownMenuItem(value: s, child: Text(_statusLabel(s))))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _selectedStatus = v);
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _notesCtrl,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(labelText: 'Notas'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Gestión de Fotografías',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SectionCard(
                  child: Column(
                    children: [
                      if (_statusMsg.isNotEmpty) ...[
                        Text(_statusMsg, style: TextStyle(color: theme.colorScheme.primary, fontSize: 12)),
                        const SizedBox(height: 8),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _uploadPhotos,
                              icon: const Icon(Icons.photo_library),
                              label: const Text('Subir'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _takePhoto,
                              icon: const Icon(Icons.camera_alt),
                              label: const Text('Cámara'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_loadingPhotos)
                        const CircularProgressIndicator()
                      else if (_photos.isEmpty)
                        const Text('No hay fotos cargadas')
                      else
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          itemCount: _photos.length,
                          itemBuilder: (context, index) {
                            final photo = _photos[index];
                            return FutureBuilder<String>(
                              future: PhotoUploadHelper.getSignedPhotoUrl(photo.filePath),
                              builder: (context, snapshot) {
                                final url = snapshot.data;
                                return ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      if (url == null)
                                        Container(color: theme.colorScheme.surfaceContainerHighest)
                                      else
                                        Image.network(url, fit: BoxFit.cover),
                                      Positioned(
                                        top: 2,
                                        right: 2,
                                        child: Material(
                                          color: Colors.black54,
                                          shape: const CircleBorder(),
                                          child: InkWell(
                                            onTap: () => _deletePhoto(photo),
                                            child: const Padding(
                                              padding: EdgeInsets.all(4),
                                              child: Icon(Icons.close, size: 16, color: Colors.white),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
                ElevatedButton.icon(
                  onPressed: _saving ? null : _saveChanges,
                  icon: const Icon(Icons.save),
                  label: Text(_saving ? 'Guardando...' : 'Guardar todos los cambios'),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

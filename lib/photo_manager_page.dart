import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'photo_upload_helper.dart';

class PhotoManagerPage extends StatefulWidget {
  final String title;
  final String assetId;
  final String? maintenanceEventId;

  const PhotoManagerPage({
    super.key,
    required this.title,
    required this.assetId,
    this.maintenanceEventId,
  });

  @override
  State<PhotoManagerPage> createState() => _PhotoManagerPageState();
}

class _PhotoManagerPageState extends State<PhotoManagerPage> {
  List<PhotoDocument> _photos = [];
  bool _loading = false;
  String _status = 'Carga de fotos pendiente.';
  final _descriptionCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPhotos() async {
    setState(() => _loading = true);
    try {
      final photos = await PhotoUploadHelper.fetchPhotos(
        assetId: widget.assetId,
        maintenanceEventId: widget.maintenanceEventId,
      );
      setState(() {
        _photos = photos;
        _status = 'Fotos cargadas: ${_photos.length}.';
      });
    } catch (e) {
      setState(() => _status = 'Error al cargar fotos: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _uploadMany() async {
    setState(() => _status = 'Subiendo fotos...');
    final result = await PhotoUploadHelper.uploadPhotosFromPicker(
      assetId: widget.assetId,
      maintenanceEventId: widget.maintenanceEventId,
      description: _descriptionCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _status = result.message);
    if (result.ok) {
      await _loadPhotos();
    }
  }

  Future<void> _takePhoto() async {
    setState(() => _status = 'Abriendo camara...');
    final result = await PhotoUploadHelper.captureAndUploadPhoto(
      assetId: widget.assetId,
      maintenanceEventId: widget.maintenanceEventId,
      description: _descriptionCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _status = result.message);
    if (result.ok) {
      await _loadPhotos();
    }
  }

  Future<void> _deletePhoto(PhotoDocument doc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Eliminar foto'),
          content: const Text('Esta accion quitara la foto del servicio/activo.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );

    if (confirm != true) {
      return;
    }

    setState(() => _status = 'Eliminando foto...');
    final result = await PhotoUploadHelper.deletePhoto(
      documentId: doc.id,
      filePath: doc.filePath,
    );
    setState(() => _status = result.message);
    if (result.ok) {
      await _loadPhotos();
    }
  }

  void _openPreview(String url, String title) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              InteractiveViewer(
                child: Image.network(url, fit: BoxFit.contain),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          const ThemeToggleButton(),
          IconButton(
            onPressed: _loading ? null : _loadPhotos,
            icon: const Icon(Icons.refresh),
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
                    controller: _descriptionCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Descripcion para nuevas fotos (opcional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _loading ? null : _uploadMany,
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Subir una o mas'),
                      ),
                      ElevatedButton.icon(
                        onPressed: _loading ? null : _takePhoto,
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: const Text('Tomar foto'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Estado: $_status'),
                  const SizedBox(height: 12),
                  Text(
                    'Fotos (${_photos.length})',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_photos.isEmpty)
              const SectionCard(child: Text('No hay fotos guardadas.'))
            else
              ..._photos.map(
                (photo) => FutureBuilder<String>(
                key: ValueKey(photo.id),
                future: PhotoUploadHelper.getSignedPhotoUrl(photo.filePath),
                builder: (context, snapshot) {
                  final url = snapshot.data;
                  return Card(
                    child: ListTile(
                      leading: SizedBox(
                        width: 56,
                        height: 56,
                        child: (url == null)
                            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                            : Image.network(url, fit: BoxFit.cover),
                      ),
                      title: Text(photo.description ?? 'Sin descripcion'),
                      subtitle: Text(photo.filePath),
                      onTap: url == null ? null : () => _openPreview(url, photo.filePath),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: _loading ? null : () => _deletePhoto(photo),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

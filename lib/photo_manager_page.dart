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
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) {
          return Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              title: Text(title, style: const TextStyle(fontSize: 16)),
              iconTheme: const IconThemeData(color: Colors.white),
            ),
            body: Center(
              child: InteractiveViewer(
                minScale: 1.0,
                maxScale: 5.0,
                child: Image.network(
                  url, 
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
            ),
          );
        },
      ),
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
                    key: ValueKey(photo.id),
                    future: PhotoUploadHelper.getSignedPhotoUrl(photo.filePath),
                    builder: (context, snapshot) {
                      final url = snapshot.data;
                      return GestureDetector(
                        onTap: url == null ? null : () => _openPreview(url, photo.description ?? 'Foto del activo'),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (url == null)
                                Container(
                                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                  child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                )
                              else
                                Image.network(url, fit: BoxFit.cover),
                              
                              // Botón de eliminar en la esquina
                              Positioned(
                                top: 4,
                                right: 4,
                                child: Material(
                                  color: Colors.black54,
                                  shape: const CircleBorder(),
                                  child: InkWell(
                                    customBorder: const CircleBorder(),
                                    onTap: _loading ? null : () => _deletePhoto(photo),
                                    child: const Padding(
                                      padding: EdgeInsets.all(6),
                                      child: Icon(Icons.delete_outline, size: 18, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ),
                              
                              // Descripción difuminada en la parte inferior si existe
                              if (photo.description != null && photo.description!.isNotEmpty)
                                Positioned(
                                  bottom: 0,
                                  left: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.fromLTRB(6, 12, 6, 4),
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.bottomCenter,
                                        end: Alignment.topCenter,
                                        colors: [Colors.black87, Colors.transparent],
                                      ),
                                    ),
                                    child: Text(
                                      photo.description!,
                                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

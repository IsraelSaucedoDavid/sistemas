import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'app_theme.dart';
import 'photo_upload_helper.dart';

class AssignmentEvidencePage extends StatefulWidget {
  final String assignmentId;
  final String assetId;
  final String assetLabel;

  const AssignmentEvidencePage({
    super.key,
    required this.assignmentId,
    required this.assetId,
    required this.assetLabel,
  });

  @override
  State<AssignmentEvidencePage> createState() => _AssignmentEvidencePageState();
}

class _AssignmentEvidencePageState extends State<AssignmentEvidencePage> {
  final _descriptionCtrl = TextEditingController();
  String _phaseFilter = 'all';
  String _uploadPhase = 'entrega';
  bool _loading = false;
  String _status = 'Carga de evidencias pendiente.';
  List<AssignmentPhotoDocument> _photos = [];

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
      final photos = await PhotoUploadHelper.fetchAssignmentPhotos(
        assignmentId: widget.assignmentId,
        phase: _phaseFilter == 'all' ? null : _phaseFilter,
      );
      setState(() {
        _photos = photos;
        _status = 'Evidencias cargadas: ${_photos.length}.';
      });
    } catch (e) {
      setState(() => _status = 'Error al cargar evidencias: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _uploadFromGallery() async {
    final picked = await FilePicker.platform.pickFiles(
      withData: true,
      allowMultiple: true,
    );
    final files = picked?.files.where((f) => f.bytes != null).toList() ?? [];
    if (files.isEmpty) {
      setState(() => _status = 'No se seleccionaron fotos.');
      return;
    }
    setState(() => _loading = true);
    final result = await PhotoUploadHelper.uploadAssignmentDraftPhotos(
      assignmentId: widget.assignmentId,
      assetId: widget.assetId,
      phase: _uploadPhase,
      description: _descriptionCtrl.text.trim(),
      photos: files
          .map(
            (f) => DraftPhoto(
              bytes: f.bytes!,
              fileName: f.name.isEmpty ? 'foto.jpg' : f.name,
            ),
          )
          .toList(),
    );
    if (!mounted) return;
    setState(() => _status = result.message);
    await _loadPhotos();
  }

  Future<void> _takePhoto() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (image == null) {
      setState(() => _status = 'No se tomo ninguna foto.');
      return;
    }
    final bytes = await image.readAsBytes();
    setState(() => _loading = true);
    final result = await PhotoUploadHelper.uploadAssignmentDraftPhotos(
      assignmentId: widget.assignmentId,
      assetId: widget.assetId,
      phase: _uploadPhase,
      description: _descriptionCtrl.text.trim(),
      photos: [
        DraftPhoto(
          bytes: bytes,
          fileName: image.name.isEmpty ? 'camera.jpg' : image.name,
        ),
      ],
    );
    if (!mounted) return;
    setState(() => _status = result.message);
    await _loadPhotos();
  }

  Future<void> _deletePhoto(AssignmentPhotoDocument doc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar evidencia'),
        content: const Text('Esta accion eliminara la foto de la asignacion.'),
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
      ),
    );
    if (confirm != true) return;

    setState(() => _loading = true);
    final result = await PhotoUploadHelper.deleteAssignmentPhoto(
      documentId: doc.id,
      filePath: doc.filePath,
    );
    if (!mounted) return;
    setState(() => _status = result.message);
    await _loadPhotos();
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
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
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

  String _formatDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '-';
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return raw;
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Evidencias de asignacion'),
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.assetLabel,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  InputDecorator(
                    decoration: const InputDecoration(labelText: 'Filtro por fase'),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _phaseFilter,
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('Todas')),
                          DropdownMenuItem(value: 'entrega', child: Text('Entrega')),
                          DropdownMenuItem(
                            value: 'devolucion',
                            child: Text('Devolucion'),
                          ),
                        ],
                        onChanged: _loading
                            ? null
                            : (value) async {
                                if (value == null) return;
                                setState(() => _phaseFilter = value);
                                await _loadPhotos();
                              },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SectionCard(
              child: Column(
                children: [
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Subir a fase',
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _uploadPhase,
                        items: const [
                          DropdownMenuItem(value: 'entrega', child: Text('Entrega')),
                          DropdownMenuItem(
                            value: 'devolucion',
                            child: Text('Devolucion'),
                          ),
                        ],
                        onChanged: _loading
                            ? null
                            : (value) {
                                if (value != null) {
                                  setState(() => _uploadPhase = value);
                                }
                              },
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _descriptionCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Descripcion para nuevas fotos (opcional)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _loading ? null : _uploadFromGallery,
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
              child: Text(
                _status,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 12),
            if (_photos.isEmpty)
              const SectionCard(child: Text('No hay evidencias guardadas.'))
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _photos.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.82,
                ),
                itemBuilder: (context, index) {
                  final photo = _photos[index];
                  final isEntrega = photo.phase.toLowerCase() == 'entrega';
                  return FutureBuilder<String>(
                    key: ValueKey(photo.id),
                    future: PhotoUploadHelper.getSignedAssignmentPhotoUrl(
                      photo.filePath,
                    ),
                    builder: (context, snapshot) {
                      final url = snapshot.data;
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: url == null
                              ? null
                              : () => _openPreview(url, photo.filePath),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: (url == null)
                                          ? Container(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .surfaceContainerHighest
                                                  .withValues(alpha: 0.4),
                                              child: const Center(
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                ),
                                              ),
                                            )
                                          : Image.network(
                                              url,
                                              fit: BoxFit.cover,
                                              errorBuilder: (context, error, stackTrace) {
                                                return Container(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .surfaceContainerHighest
                                                      .withValues(alpha: 0.4),
                                                  child: const Center(
                                                    child: Icon(
                                                      Icons.broken_image_outlined,
                                                      size: 28,
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                    ),
                                    Positioned(
                                      top: 8,
                                      left: 8,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(999),
                                          color: isEntrega
                                              ? Colors.blue.withValues(alpha: 0.82)
                                              : Colors.green.withValues(alpha: 0.82),
                                        ),
                                        child: Text(
                                          isEntrega ? 'ENTREGA' : 'DEVOLUCION',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      right: 6,
                                      top: 6,
                                      child: Material(
                                        color: Colors.black.withValues(alpha: 0.35),
                                        shape: const CircleBorder(),
                                        child: IconButton(
                                          onPressed: _loading
                                              ? null
                                              : () => _deletePhoto(photo),
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                          tooltip: 'Eliminar',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (photo.description == null ||
                                              photo.description!.trim().isEmpty)
                                          ? 'Sin descripcion'
                                          : photo.description!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _formatDate(photo.createdAt),
                                      style: Theme.of(context).textTheme.bodySmall,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
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

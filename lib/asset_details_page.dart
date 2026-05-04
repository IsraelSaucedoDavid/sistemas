import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'asset_models.dart';
import 'asset_edit_page.dart';
import 'photo_upload_helper.dart';

class AssetDetailsPage extends StatefulWidget {
  final AssetItem asset;
  final String? typeName;
  final List<AssetTypeOption> assetTypes;
  final List<String> statusOptions;

  const AssetDetailsPage({
    super.key,
    required this.asset,
    this.typeName,
    required this.assetTypes,
    required this.statusOptions,
  });

  @override
  State<AssetDetailsPage> createState() => _AssetDetailsPageState();
}

class _AssetDetailsPageState extends State<AssetDetailsPage> {
  List<PhotoDocument> _photos = [];
  bool _loadingPhotos = false;

  @override
  void initState() {
    super.initState();
    _loadPhotos();
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

  void _openFullScreenImage(String url, String title) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(title, style: const TextStyle(color: Colors.white)),
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.network(
                url,
                fit: BoxFit.contain,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
          ),
        ),
      ),
    );
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

  Color _statusColor(String status) {
    switch (status) {
      case 'funcionando': return Colors.green.shade600;
      case 'libre': return Colors.blue.shade600;
      case 'asignado': return Colors.deepPurple.shade600;
      case 'mantenimiento': return Colors.orange.shade600;
      case 'descompuesto': return Colors.red.shade600;
      case 'baja': return Colors.blueGrey.shade700;
      case 'activo': return Colors.green.shade600;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final asset = widget.asset;

    return Scaffold(
      appBar: AppBar(
        title: Text(asset.assetTag),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final updated = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => AssetEditPage(
                    asset: asset,
                    assetTypes: widget.assetTypes,
                    statusOptions: widget.statusOptions,
                  ),
                ),
              );
              if (updated == true && mounted) {
                // Since AssetItem is immutable, we'd ideally fetch the updated asset here
                // or use a callback to refresh the parent list.
                // For now, we refresh the photos and suggest returning to the list.
                _loadPhotos();
              }
            },
            tooltip: 'Editar activo',
          ),
          const ThemeToggleButton(),
        ],
      ),
      body: GradientBody(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Card with Main Info
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            asset.assetTag,
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: _statusColor(asset.status).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: _statusColor(asset.status).withValues(alpha: 0.5)),
                          ),
                          child: Text(
                            _statusLabel(asset.status),
                            style: TextStyle(
                              color: _statusColor(asset.status),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (widget.typeName != null)
                      Text(
                        widget.typeName!,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    const Divider(height: 32),
                    _InfoRow(label: 'Marca', value: asset.brand),
                    _InfoRow(label: 'Modelo', value: asset.model),
                    _InfoRow(label: 'N° de Serie', value: asset.serialNumber),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Notes Section
              if (asset.notes != null && asset.notes!.isNotEmpty) ...[
                Text(
                  'Notas',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SectionCard(
                  child: Text(
                    asset.notes!,
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Photos Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Fotografías',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  if (_loadingPhotos)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              
              if (!_loadingPhotos && _photos.isEmpty)
                const SectionCard(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('No hay fotos disponibles para este activo.'),
                    ),
                  ),
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1,
                  ),
                  itemCount: _photos.length,
                  itemBuilder: (context, index) {
                    final photo = _photos[index];
                    return FutureBuilder<String>(
                      future: PhotoUploadHelper.getSignedPhotoUrl(photo.filePath),
                      builder: (context, snapshot) {
                        final url = snapshot.data;
                        return GestureDetector(
                          onTap: url != null ? () => _openFullScreenImage(url, photo.description ?? 'Foto del activo') : null,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (url == null)
                                  Container(
                                    color: theme.colorScheme.surfaceContainerHighest,
                                    child: const Center(child: CircularProgressIndicator()),
                                  )
                                else
                                  Image.network(
                                    url,
                                    fit: BoxFit.cover,
                                    loadingBuilder: (context, child, loadingProgress) {
                                      if (loadingProgress == null) return child;
                                      return Container(
                                        color: theme.colorScheme.surfaceContainerHighest,
                                        child: const Center(child: CircularProgressIndicator()),
                                      );
                                    },
                                  ),
                                if (photo.description != null && photo.description!.isNotEmpty)
                                  Positioned(
                                    bottom: 0,
                                    left: 0,
                                    right: 0,
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: const BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.bottomCenter,
                                          end: Alignment.topCenter,
                                          colors: [Colors.black87, Colors.transparent],
                                        ),
                                      ),
                                      child: Text(
                                        photo.description!,
                                        style: const TextStyle(color: Colors.white, fontSize: 12),
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
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String? value;

  const _InfoRow({required this.label, this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          Expanded(
            child: Text(
              (value == null || value!.isEmpty) ? '-' : value!,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

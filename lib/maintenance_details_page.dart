import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'app_theme.dart';
import 'photo_upload_helper.dart';
import 'maintenance_page.dart';
import 'maintenance_edit_page.dart';

class MaintenanceDetailsPage extends StatefulWidget {
  final MaintenanceItem event;
  final String assetName;
  final List<MaintenanceAssetOption> assets;
  final List<String> statusOptions;
  final List<String> typeOptions;

  const MaintenanceDetailsPage({
    super.key,
    required this.event,
    required this.assetName,
    required this.assets,
    required this.statusOptions,
    required this.typeOptions,
  });

  @override
  State<MaintenanceDetailsPage> createState() => _MaintenanceDetailsPageState();
}

class _MaintenanceDetailsPageState extends State<MaintenanceDetailsPage> {
  late MaintenanceItem _currentEvent;
  List<PhotoDocument> _photos = [];
  bool _loadingPhotos = false;

  @override
  void initState() {
    super.initState();
    _currentEvent = widget.event;
    _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    setState(() => _loadingPhotos = true);
    try {
      final photos = await PhotoUploadHelper.fetchPhotos(
        assetId: _currentEvent.assetId ?? '',
        maintenanceEventId: _currentEvent.id,
      );
      setState(() => _photos = photos);
    } catch (e) {
      debugPrint('Error loading maintenance photos: $e');
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
      case 'pendiente': return 'Pendiente';
      case 'en_proceso': return 'En proceso';
      case 'concluido': return 'Concluido';
      case 'perdida': return 'Perdida / Inutilizable';
      default: return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pendiente': return Colors.orange;
      case 'en_proceso': return Colors.blue;
      case 'concluido': return Colors.green;
      case 'perdida': return Colors.red;
      default: return Colors.grey;
    }
  }

  String _formatDateTime(String? dbValue) {
    if (dbValue == null || dbValue.isEmpty) return '-';
    try {
      final date = DateTime.parse(dbValue).toLocal();
      return DateFormat('dd/MM/yyyy HH:mm').format(date);
    } catch (_) {
      return dbValue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final event = _currentEvent;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle de Mantenimiento'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final updated = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => MaintenanceEditPage(
                    event: _currentEvent,
                    assets: widget.assets,
                    statusOptions: widget.statusOptions,
                    typeOptions: widget.typeOptions,
                  ),
                ),
              );
              if (updated == true) {
                // Refresh local state
                final client = Supabase.instance.client;
                final response = await client.schema('sistema').from('maintenance_events').select().eq('id', _currentEvent.id).single();
                setState(() {
                  _currentEvent = MaintenanceItem.fromMap(response);
                });
                _loadPhotos();
              }
            },
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
              // Header Card
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            widget.assetName,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _statusColor(event.status).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _statusColor(event.status).withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            _statusLabel(event.status),
                            style: TextStyle(
                              color: _statusColor(event.status),
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tipo: ${event.type.toUpperCase()}',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                    ),
                    const Divider(height: 32),
                    _InfoRow(label: 'Técnico', value: event.technician),
                    _InfoRow(label: 'Costo', value: event.cost != null ? '\$${event.cost}' : '-'),
                    const Divider(height: 32),
                    _InfoRow(label: 'Programado', value: _formatDateTime(event.scheduledDate)),
                    _InfoRow(label: 'Realizado', value: _formatDateTime(event.performedDate)),
                    _InfoRow(label: 'Término', value: _formatDateTime(event.completedDate)),
                    _InfoRow(label: 'Próximo', value: _formatDateTime(event.nextDueDate)),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Description & Result
              Text('Descripción del Servicio', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SectionCard(
                child: Text(event.description, style: theme.textTheme.bodyLarge),
              ),
              const SizedBox(height: 16),
              
              if (event.result != null && event.result!.isNotEmpty) ...[
                Text('Resultado / Hallazgos', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SectionCard(
                  child: Text(event.result!, style: theme.textTheme.bodyLarge),
                ),
                const SizedBox(height: 24),
              ],

              // Photos Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Evidencias Fotográficas', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  if (_loadingPhotos)
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ),
              const SizedBox(height: 12),
              
              if (!_loadingPhotos && _photos.isEmpty)
                const SectionCard(child: Center(child: Text('No hay fotos para este mantenimiento.')))
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: _photos.length,
                  itemBuilder: (context, index) {
                    final photo = _photos[index];
                    return FutureBuilder<String>(
                      future: PhotoUploadHelper.getSignedPhotoUrl(photo.filePath),
                      builder: (context, snapshot) {
                        final url = snapshot.data;
                        return GestureDetector(
                          onTap: url != null ? () => _openFullScreenImage(url, photo.description ?? 'Evidencia') : null,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: url == null
                                ? Container(color: theme.colorScheme.surfaceContainerHighest)
                                : Image.network(url, fit: BoxFit.cover),
                          ),
                        );
                      },
                    );
                  },
                ),
              const SizedBox(height: 40),
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
        children: [
          SizedBox(width: 100, child: Text('$label:', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)))),
          Expanded(child: Text(value ?? '-', style: const TextStyle(fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}

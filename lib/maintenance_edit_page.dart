import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'app_theme.dart';
import 'maintenance_page.dart';
import 'photo_upload_helper.dart';

class MaintenanceEditPage extends StatefulWidget {
  final MaintenanceItem event;
  final List<MaintenanceAssetOption> assets;
  final List<String> statusOptions;
  final List<String> typeOptions;

  const MaintenanceEditPage({
    super.key,
    required this.event,
    required this.assets,
    required this.statusOptions,
    required this.typeOptions,
  });

  @override
  State<MaintenanceEditPage> createState() => _MaintenanceEditPageState();
}

class _MaintenanceEditPageState extends State<MaintenanceEditPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _descriptionCtrl;
  late TextEditingController _technicianCtrl;
  late TextEditingController _resultCtrl;
  late TextEditingController _costCtrl;

  late String? _selectedAssetId;
  late String _selectedStatus;
  late String _selectedType;
  DateTime? _scheduledDate;
  DateTime? _performedDate;
  DateTime? _nextDueDate;
  DateTime? _completedDate;
  int _reminderDays = 0;
  String _repeatInterval = 'none';

  List<PhotoDocument> _existingPhotos = [];
  List<DraftPhoto> _newPhotos = [];
  bool _loadingPhotos = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _descriptionCtrl = TextEditingController(text: widget.event.description);
    _technicianCtrl = TextEditingController(text: widget.event.technician ?? '');
    _resultCtrl = TextEditingController(text: widget.event.result ?? '');
    _costCtrl = TextEditingController(text: widget.event.cost ?? '');

    _selectedAssetId = widget.event.assetId;
    _reminderDays = widget.event.reminderDays;
    _repeatInterval = widget.event.repeatInterval;
    _selectedStatus = widget.event.status;
    _selectedType = widget.event.type;
    _scheduledDate = _parseDbDate(widget.event.scheduledDate);
    _performedDate = _parseDbDate(widget.event.performedDate);
    _nextDueDate = _parseDbDate(widget.event.nextDueDate);
    _completedDate = _parseDbDate(widget.event.completedDate);

    _loadExistingPhotos();
  }

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    _technicianCtrl.dispose();
    _resultCtrl.dispose();
    _costCtrl.dispose();
    super.dispose();
  }

  DateTime? _parseDbDate(String? value) {
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  String? _toDbDate(DateTime? value) {
    if (value == null) return null;
    return value.toIso8601String();
  }

  Future<void> _loadExistingPhotos() async {
    setState(() => _loadingPhotos = true);
    try {
      final photos = await PhotoUploadHelper.fetchPhotos(
        assetId: widget.event.assetId ?? '',
        maintenanceEventId: widget.event.id,
      );
      setState(() => _existingPhotos = photos);
    } catch (e) {
      debugPrint('Error loading photos: $e');
    } finally {
      if (mounted) setState(() => _loadingPhotos = false);
    }
  }

  Future<void> _pickPhotos() async {
    final result = await FilePicker.platform.pickFiles(withData: true, allowMultiple: true);
    final files = result?.files.where((f) => f.bytes != null).toList() ?? [];
    if (files.isEmpty) return;
    setState(() {
      _newPhotos.addAll(files.map((f) => DraftPhoto(bytes: f.bytes!, fileName: f.name)));
    });
  }

  Future<void> _takePhoto() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (image == null) return;
    final bytes = await image.readAsBytes();
    setState(() {
      _newPhotos.add(DraftPhoto(bytes: bytes, fileName: image.name));
    });
  }

  Future<void> _deleteExistingPhoto(PhotoDocument photo) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar foto'),
        content: const Text('¿Estás seguro de eliminar esta evidencia?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      final ok = await PhotoUploadHelper.deletePhoto(
        documentId: photo.id,
        filePath: photo.filePath,
      );
      if (ok.ok) _loadExistingPhotos();
    }
  }

  Future<void> _pickDateTime(String field) async {
    DateTime? current;
    if (field == 'scheduled') current = _scheduledDate;
    if (field == 'performed') current = _performedDate;
    if (field == 'next') current = _nextDueDate;
    if (field == 'completed') current = _completedDate;

    final base = current ?? DateTime.now();

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (pickedDate != null) {
      if (!mounted) return;
      final pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(base),
      );

      if (pickedTime != null) {
        setState(() {
          final fullDate = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            pickedTime.hour,
            pickedTime.minute,
          );
          if (field == 'scheduled') _scheduledDate = fullDate;
          if (field == 'performed') _performedDate = fullDate;
          if (field == 'next') _nextDueDate = fullDate;
          if (field == 'completed') _completedDate = fullDate;
        });
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedAssetId == null) return;

    setState(() => _saving = true);
    try {
      final client = Supabase.instance.client;
      final costText = _costCtrl.text.trim();
      final cost = costText.isEmpty ? null : double.tryParse(costText);

      await client.schema('sistema').from('maintenance_events').update({
        'asset_id': _selectedAssetId,
        'type': _selectedType,
        'status': _selectedStatus,
        'scheduled_date': _toDbDate(_scheduledDate),
        'performed_date': _toDbDate(_performedDate),
        'technician': _technicianCtrl.text.trim().isEmpty ? null : _technicianCtrl.text.trim(),
        'description': _descriptionCtrl.text.trim(),
        'result': _resultCtrl.text.trim().isEmpty ? null : _resultCtrl.text.trim(),
        'next_due_date': _toDbDate(_nextDueDate),
        'completed_date': _toDbDate(_selectedStatus == 'concluido' ? (_completedDate ?? DateTime.now()) : null),
        'cost': cost,
        'reminder_days': _reminderDays,
        'repeat_interval': _repeatInterval,
      }).eq('id', widget.event.id);

      if (_newPhotos.isNotEmpty) {
        await PhotoUploadHelper.uploadDraftPhotos(
          assetId: _selectedAssetId!,
          maintenanceEventId: widget.event.id,
          photos: _newPhotos,
          description: 'Evidencia adicional de mantenimiento',
        );
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al guardar: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar Mantenimiento'),
        actions: [
          IconButton(
            onPressed: _saving ? null : _save,
            icon: _saving ? const CircularProgressIndicator(strokeWidth: 2) : const Icon(Icons.check),
          ),
        ],
      ),
      body: GradientBody(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Información General', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _selectedAssetId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Activo *'),
                      items: widget.assets.map((a) => DropdownMenuItem(value: a.id, child: Text(a.label))).toList(),
                      onChanged: _saving ? null : (v) => setState(() => _selectedAssetId = v),
                      validator: (v) => v == null ? 'Selecciona un activo' : null,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _technicianCtrl,
                            style: const TextStyle(fontSize: 14),
                            decoration: const InputDecoration(
                              labelText: 'Técnico',
                              prefixIcon: Icon(Icons.person_outline, size: 20),
                              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _costCtrl,
                            style: const TextStyle(fontSize: 14),
                            decoration: const InputDecoration(
                              labelText: 'Costo',
                              prefixIcon: Icon(Icons.attach_money, size: 20),
                              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: _reminderDays,
                            style: const TextStyle(fontSize: 14),
                            decoration: const InputDecoration(
                              labelText: 'Recordatorio',
                              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            ),
                            items: const [
                              DropdownMenuItem(value: 0, child: Text('Hoy', style: TextStyle(fontSize: 13))),
                              DropdownMenuItem(value: 1, child: Text('1 día', style: TextStyle(fontSize: 13))),
                              DropdownMenuItem(value: 3, child: Text('3 días', style: TextStyle(fontSize: 13))),
                              DropdownMenuItem(value: 7, child: Text('1 sem', style: TextStyle(fontSize: 13))),
                            ],
                            onChanged: _saving ? null : (v) => setState(() => _reminderDays = v!),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _repeatInterval,
                            style: const TextStyle(fontSize: 14),
                            decoration: const InputDecoration(
                              labelText: 'Repetir',
                              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'none', child: Text('No', style: TextStyle(fontSize: 13))),
                              DropdownMenuItem(value: 'hourly', child: Text('Hora', style: TextStyle(fontSize: 13))),
                              DropdownMenuItem(value: 'daily', child: Text('Día', style: TextStyle(fontSize: 13))),
                              DropdownMenuItem(value: 'weekly', child: Text('Sem', style: TextStyle(fontSize: 13))),
                            ],
                            onChanged: _saving ? null : (v) => setState(() => _repeatInterval = v!),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _selectedType,
                            isExpanded: true,
                            style: const TextStyle(fontSize: 14),
                            decoration: const InputDecoration(
                              labelText: 'Tipo',
                              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            ),
                            items: widget.typeOptions.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 13)))).toList(),
                            onChanged: _saving ? null : (v) => setState(() => _selectedType = v!),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _selectedStatus,
                            isExpanded: true,
                            style: const TextStyle(fontSize: 14),
                            decoration: const InputDecoration(
                              labelText: 'Estatus',
                              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            ),
                            items: widget.statusOptions.map((s) => DropdownMenuItem(value: s, child: Text(_statusLabel(s), style: const TextStyle(fontSize: 13)))).toList(),
                            onChanged: _saving ? null : (v) {
                              setState(() {
                                _selectedStatus = v!;
                                if (_selectedStatus == 'concluido' && _completedDate == null) _completedDate = DateTime.now();
                                if (_selectedStatus != 'concluido') _completedDate = null;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Descripción y Resultados', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _descriptionCtrl,
                      decoration: const InputDecoration(labelText: 'Descripción del problema / trabajo *'),
                      minLines: 3,
                      maxLines: 6,
                      validator: (v) => v == null || v.trim().isEmpty ? 'Ingresa una descripción' : null,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _resultCtrl,
                      decoration: const InputDecoration(labelText: 'Resultado / Hallazgos finales'),
                      minLines: 2,
                      maxLines: 4,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cronograma', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    _DateTile(label: 'Programado', date: _scheduledDate, onTap: () => _pickDateTime('scheduled')),
                    _DateTile(label: 'Realizado', date: _performedDate, onTap: () => _pickDateTime('performed')),
                    _DateTile(label: 'Término', date: _completedDate, onTap: () => _pickDateTime('completed'), enabled: _selectedStatus == 'concluido'),
                    _DateTile(label: 'Próximo Servicio', date: _nextDueDate, onTap: () => _pickDateTime('next')),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Evidencias Fotográficas', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    if (_loadingPhotos) const Center(child: CircularProgressIndicator())
                    else ...[
                      if (_existingPhotos.isNotEmpty) ...[
                        const Text('Fotos actuales:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 100,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _existingPhotos.length,
                            itemBuilder: (context, index) {
                              final p = _existingPhotos[index];
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Stack(
                                  children: [
                                    FutureBuilder<String>(
                                      future: PhotoUploadHelper.getSignedPhotoUrl(p.filePath),
                                      builder: (context, snap) => ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: snap.data != null ? Image.network(snap.data!, width: 100, height: 100, fit: BoxFit.cover) : Container(width: 100, height: 100, color: Colors.grey[300]),
                                      ),
                                    ),
                                    Positioned(top: 0, right: 0, child: IconButton(icon: const Icon(Icons.remove_circle, color: Colors.red), onPressed: () => _deleteExistingPhoto(p))),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      const Text('Agregar nuevas:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: OutlinedButton.icon(onPressed: _pickPhotos, icon: const Icon(Icons.photo_library), label: const Text('Galería'))),
                          const SizedBox(width: 8),
                          Expanded(child: OutlinedButton.icon(onPressed: _takePhoto, icon: const Icon(Icons.camera_alt), label: const Text('Cámara'))),
                        ],
                      ),
                      if (_newPhotos.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _newPhotos.asMap().entries.map((entry) => Stack(
                            children: [
                              ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(entry.value.bytes, width: 60, height: 60, fit: BoxFit.cover)),
                              Positioned(top: -10, right: -10, child: IconButton(icon: const Icon(Icons.cancel, size: 20), onPressed: () => setState(() => _newPhotos.removeAt(entry.key)))),
                            ],
                          )).toList(),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save),
                label: Text(_saving ? 'Guardando cambios...' : 'Guardar Cambios'),
                style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  final String label;
  final DateTime? date;
  final VoidCallback onTap;
  final bool enabled;

  const _DateTile({required this.label, required this.date, required this.onTap, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: const TextStyle(fontSize: 14)),
      subtitle: Text(
        date == null 
          ? 'No seleccionada' 
          : DateFormat('dd/MM/yyyy HH:mm').format(date!.toLocal()), 
        style: TextStyle(color: date == null ? Colors.grey : null),
      ),
      trailing: const Icon(Icons.calendar_today, size: 18),
      onTap: enabled ? onTap : null,
      enabled: enabled,
    );
  }
}

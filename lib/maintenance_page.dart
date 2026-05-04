import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

import 'app_theme.dart';
import 'photo_manager_page.dart';
import 'photo_upload_helper.dart';
import 'maintenance_details_page.dart';
import 'maintenance_edit_page.dart';
import 'maintenance_calendar_page.dart';
import 'notification_service.dart';

class MaintenancePage extends StatefulWidget {
  const MaintenancePage({super.key});

  @override
  State<MaintenancePage> createState() => _MaintenancePageState();
}

class _MaintenancePageState extends State<MaintenancePage> {
  final List<String> _typeOptions = ['preventivo', 'correctivo'];
  final List<String> _statusOptions = ['pendiente', 'en_proceso', 'concluido', 'perdida'];

  List<MaintenanceAssetOption> _assets = [];
  List<MaintenanceAssetOption> _urgentAssets = [];
  List<MaintenanceItem> _events = [];
  String _filterStatus = 'todos';
  bool _loading = false;
  bool _saving = false;
  String _status = 'Carga de mantenimientos pendiente.';

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (_client.auth.currentSession == null) {
      setState(() => _status = 'Inicia sesion para gestionar mantenimientos.');
      return;
    }

    setState(() => _loading = true);
    try {
      final assetsResponse = await _client
          .schema('sistema')
          .from('assets')
          .select('id, asset_tag, serial_number, status')
          .neq('status', 'baja')
          .order('asset_tag');

      final eventsResponse = await _client
          .schema('sistema')
          .from('maintenance_events')
          .select(
            'id, asset_id, type, scheduled_date, performed_date, '
            'technician, description, result, next_due_date, cost, created_at, '
            'status, completed_date, reminder_days, repeat_interval',
          )
          .order('created_at', ascending: false)
          .limit(100);

      final assets = (assetsResponse as List<dynamic>)
          .map((e) => MaintenanceAssetOption.fromMap(e as Map<String, dynamic>))
          .toList();
      final events = (eventsResponse as List<dynamic>)
          .map((e) => MaintenanceItem.fromMap(e as Map<String, dynamic>))
          .toList();

      setState(() {
        _assets = assets;
        _events = events;
        _urgentAssets = _assets.where((a) {
          final isUrgent = a.status == 'mantenimiento' || a.status == 'descompuesto';
          if (!isUrgent) return false;
          final hasActiveEvent = _events.any((e) => e.assetId == a.id && (e.status == 'pendiente' || e.status == 'en_proceso'));
          return !hasActiveEvent;
        }).toList();
        _status = 'Mantenimientos cargados: ${_events.length}.';
      });
    } on PostgrestException catch (e) {
      setState(() => _status = 'Error al cargar datos: ${e.message}');
    } catch (e) {
      setState(() => _status = 'Error inesperado: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String? _toDbDate(DateTime? value) {
    if (value == null) return null;
    // Use ISO 8601 format to include time
    return value.toIso8601String();
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

  List<MaintenanceItem> _filteredEvents() {
    var result = _events;
    if (_filterStatus != 'todos') {
      result = result.where((event) => event.status == _filterStatus).toList();
    }
    return result;
  }

  DateTime? _parseDbDate(String? value) {
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  Future<void> _openEditPage(MaintenanceItem event) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MaintenanceEditPage(
          event: event,
          assets: _assets,
          statusOptions: _statusOptions,
          typeOptions: _typeOptions,
        ),
      ),
    );

    if (updated == true) {
      await _loadData();
    }
  }

  String _assetLabelById(String? assetId) {
    if (assetId == null) return 'Sin activo';
    for (final item in _assets) {
      if (item.id == assetId) return item.label;
    }
    return assetId;
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

  _SemaforoState _semaforoState(MaintenanceItem event) {
    if (event.status == 'concluido') {
      return const _SemaforoState(id: 'concluido', label: 'Concluido', color: Colors.green);
    }

    final dueDate = _parseDbDate(event.nextDueDate);
    if (dueDate == null) {
      return const _SemaforoState(id: 'sin_fecha', label: 'Sin fecha compromiso', color: Colors.grey);
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final days = due.difference(today).inDays;

    if (days < 0) return const _SemaforoState(id: 'vencido', label: 'Vencido', color: Colors.red);
    if (days <= 2) return const _SemaforoState(id: 'por_vencer', label: 'Por vencer', color: Colors.orange);
    return const _SemaforoState(id: 'en_tiempo', label: 'En tiempo', color: Colors.blue);
  }

  Future<void> _confirmDeleteMaintenance(MaintenanceItem event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Eliminar mantenimiento?'),
        content: const Text('Esta acción no se puede deshacer y eliminará el registro histórico.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirmed == true) {
      _deleteMaintenance(event);
    }
  }

  Future<void> _deleteMaintenance(MaintenanceItem event) async {
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.schema('sistema').from('maintenance_events').delete().eq('id', event.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Registro eliminado correctamente')));
        _loadData();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al eliminar: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openCreateMaintenanceDialog({String? preSelectedAssetId}) async {
    final descriptionCtrl = TextEditingController();
    String? selectedAssetId = preSelectedAssetId;
    String selectedType = 'preventivo';
    DateTime? scheduledDate = DateTime.now().add(const Duration(days: 1));
    scheduledDate = DateTime(scheduledDate.year, scheduledDate.month, scheduledDate.day, 8, 0);
    int reminderDays = 1;
    String repeatInterval = 'none';

    final res = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Registrar Servicio'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedAssetId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Activo *'),
                  items: _assets.map((a) => DropdownMenuItem(value: a.id, child: Text(a.label))).toList(),
                  onChanged: (v) => setLocalState(() => selectedAssetId = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedType,
                  decoration: const InputDecoration(labelText: 'Tipo'),
                  items: const [
                    DropdownMenuItem(value: 'preventivo', child: Text('Preventivo')),
                    DropdownMenuItem(value: 'correctivo', child: Text('Correctivo')),
                  ],
                  onChanged: (v) => setLocalState(() => selectedType = v!),
                ),
                const SizedBox(height: 12),
                ListTile(
                  title: Text(scheduledDate == null ? 'Seleccionar fecha *' : 'Fecha: ${DateFormat('dd/MM/yyyy').format(scheduledDate!)}'),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime.now(),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) setLocalState(() => scheduledDate = DateTime(picked.year, picked.month, picked.day, scheduledDate?.hour ?? 8, scheduledDate?.minute ?? 0));
                  },
                ),
                const SizedBox(height: 12),
                ListTile(
                  title: Text(scheduledDate == null ? 'Seleccionar hora' : 'Hora: ${DateFormat('HH:mm').format(scheduledDate!)}'),
                  trailing: const Icon(Icons.access_time),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay(hour: scheduledDate?.hour ?? 8, minute: scheduledDate?.minute ?? 0),
                    );
                    if (picked != null) {
                      setLocalState(() {
                        final base = scheduledDate ?? DateTime.now();
                        scheduledDate = DateTime(base.year, base.month, base.day, picked.hour, picked.minute);
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: repeatInterval,
                  decoration: const InputDecoration(labelText: 'Repetir alerta'),
                  items: const [
                    DropdownMenuItem(value: 'none', child: Text('No repetir')),
                    DropdownMenuItem(value: 'hourly', child: Text('Cada Hora')),
                    DropdownMenuItem(value: 'daily', child: Text('Diario')),
                    DropdownMenuItem(value: 'weekly', child: Text('Semanal')),
                  ],
                  onChanged: (v) => setLocalState(() => repeatInterval = v!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: reminderDays,
                  decoration: const InputDecoration(labelText: 'Recordatorio'),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('Mismo día')),
                    DropdownMenuItem(value: 1, child: Text('1 día antes')),
                    DropdownMenuItem(value: 3, child: Text('3 días antes')),
                    DropdownMenuItem(value: 7, child: Text('1 semana antes')),
                  ],
                  onChanged: (v) => setLocalState(() => reminderDays = v!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionCtrl,
                  decoration: const InputDecoration(labelText: 'Descripción *'),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                if (selectedAssetId == null || scheduledDate == null || descriptionCtrl.text.trim().isEmpty) return;
                
                try {
                  final dateStr = _toDbDate(scheduledDate);
                  await Supabase.instance.client.schema('sistema').from('maintenance_events').insert({
                    'asset_id': selectedAssetId,
                    'type': selectedType,
                    'status': 'pendiente',
                    'scheduled_date': dateStr,
                    'description': descriptionCtrl.text.trim(),
                    'reminder_days': reminderDays,
                    'repeat_interval': repeatInterval,
                  });

                  // Notificación remota (segura)
                  NotificationService().sendRemoteNotification(
                    title: '🛠️ Nuevo Mantenimiento',
                    body: 'Se agendó servicio para: ${_assetLabelById(selectedAssetId)}\nFecha: ${DateFormat('dd/MM/yyyy HH:mm').format(scheduledDate!)}',
                  );

                  if (context.mounted) Navigator.pop(context, true);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (res == true) {
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mantenimiento registrado con éxito')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mantenimientos'),
        actions: [
          const ThemeToggleButton(),
          IconButton(
            tooltip: 'Calendario',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MaintenanceCalendarPage())),
            icon: const Icon(Icons.calendar_month),
          ),
          IconButton(onPressed: (_loading || _saving) ? null : _loadData, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: GradientBody(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SectionCard(child: Text(_status, style: const TextStyle(fontWeight: FontWeight.w600))),
            const SizedBox(height: 16),
            if (_urgentAssets.isNotEmpty) ...[
              Text('Equipos que requieren atención (${_urgentAssets.length})', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _urgentAssets.map((asset) {
                    final isMaint = asset.status == 'mantenimiento';
                    return Container(
                      width: 220,
                      margin: const EdgeInsets.only(right: 12),
                      child: SectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(isMaint ? Icons.build_circle_outlined : Icons.error_outline, color: isMaint ? Colors.orange : Colors.red, size: 24),
                                const SizedBox(width: 8),
                                Expanded(child: Text(asset.label, style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(isMaint ? 'Requiere mantenimiento' : 'Reportado descompuesto', style: TextStyle(fontSize: 12, color: isMaint ? Colors.orange.shade700 : Colors.red.shade700, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: () => _openCreateMaintenanceDialog(preSelectedAssetId: asset.id),
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text('Registrar Servicio', style: TextStyle(fontSize: 12)),
                                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8), visualDensity: VisualDensity.compact),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 24),
            ],
            const Divider(),
            const SizedBox(height: 8),
            Text('Historial de Mantenimientos (${_filteredEvents().length})', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Filtrar por estatus', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _FilterPill(label: 'Todos', selected: _filterStatus == 'todos', onTap: () => setState(() => _filterStatus = 'todos')),
                        _FilterPill(label: 'Pendiente', selected: _filterStatus == 'pendiente', onTap: () => setState(() => _filterStatus = 'pendiente')),
                        _FilterPill(label: 'En proceso', selected: _filterStatus == 'en_proceso', onTap: () => setState(() => _filterStatus = 'en_proceso')),
                        _FilterPill(label: 'Concluido', selected: _filterStatus == 'concluido', onTap: () => setState(() => _filterStatus = 'concluido')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (_filteredEvents().isEmpty) const Text('Aun no hay mantenimientos registrados.')
            else ..._filteredEvents().map((event) {
              final semaforo = _semaforoState(event);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SectionCard(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MaintenanceDetailsPage(event: event, assetName: _assetLabelById(event.assetId), assets: _assets, statusOptions: _statusOptions, typeOptions: _typeOptions))),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(padding: const EdgeInsets.only(top: 2), child: Icon(event.type == 'correctivo' ? Icons.warning_amber_rounded : Icons.handyman_outlined, color: semaforo.color)),
                            const SizedBox(width: 10),
                            Expanded(child: Text('${event.type.toUpperCase()} - ${_assetLabelById(event.assetId)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 19))),
                            PopupMenuButton<String>(
                              onSelected: (val) => val == 'editar' ? _openEditPage(event) : _confirmDeleteMaintenance(event),
                              itemBuilder: (_) => const [PopupMenuItem(value: 'editar', child: Text('Editar mantenimiento')), PopupMenuItem(value: 'eliminar', child: Text('Eliminar registro', style: TextStyle(color: Colors.red)))],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('Programado: ${_formatDateTime(event.scheduledDate)}'),
                        Text('Realizado: ${_formatDateTime(event.performedDate)}'),
                        Text('Tecnico: ${event.technician ?? '-'} | Costo: ${event.cost ?? '-'}'),
                        Text('Proximo: ${_formatDateTime(event.nextDueDate)} | Termino: ${_formatDateTime(event.completedDate)}'),
                        Text('Estatus: ${_statusLabel(event.status)} | Semaforo: ${semaforo.label}'),
                        const SizedBox(height: 6),
                        Text(event.description),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(tooltip: 'Agregar mantenimiento', onPressed: (_loading || _saving) ? null : _openCreateMaintenanceDialog, child: const Icon(Icons.add)),
    );
  }
}

class _SemaforoState {
  final String id;
  final String label;
  final Color color;
  const _SemaforoState({required this.id, required this.label, required this.color});
}

class _FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterPill({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? scheme.primary.withValues(alpha: 0.2) : scheme.surfaceContainerHighest.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? scheme.primary.withValues(alpha: 0.65) : scheme.outline.withValues(alpha: 0.2)),
          ),
          child: Text(label, style: TextStyle(fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
        ),
      ),
    );
  }
}

class MaintenanceAssetOption {
  final String id;
  final String label;
  final String status;
  const MaintenanceAssetOption({required this.id, required this.label, required this.status});
  factory MaintenanceAssetOption.fromMap(Map<String, dynamic> map) {
    final id = map['id']?.toString() ?? '';
    final tag = map['asset_tag']?.toString() ?? 'Sin tag';
    final serial = map['serial_number']?.toString();
    final status = map['status']?.toString() ?? 'libre';
    return MaintenanceAssetOption(id: id, label: (serial == null || serial.isEmpty) ? tag : '$tag - $serial', status: status);
  }
}

class MaintenanceItem {
  final String id;
  final String? assetId;
  final String type;
  final String status;
  final String? scheduledDate;
  final String? performedDate;
  final String? completedDate;
  final String? technician;
  final String description;
  final String? result;
  final String? nextDueDate;
  final String? cost;
  final String? createdAt;
  final int reminderDays;
  final String repeatInterval;

  const MaintenanceItem({
    required this.id,
    required this.assetId,
    required this.type,
    required this.status,
    required this.scheduledDate,
    required this.performedDate,
    required this.completedDate,
    required this.technician,
    required this.description,
    required this.result,
    required this.nextDueDate,
    required this.cost,
    required this.createdAt,
    this.reminderDays = 0,
    this.repeatInterval = 'none',
  });

  factory MaintenanceItem.fromMap(Map<String, dynamic> map) {
    return MaintenanceItem(
      id: map['id']?.toString() ?? '',
      assetId: map['asset_id']?.toString(),
      type: map['type']?.toString() ?? 'preventivo',
      status: map['status']?.toString() ?? 'pendiente',
      scheduledDate: map['scheduled_date']?.toString(),
      performedDate: map['performed_date']?.toString(),
      completedDate: map['completed_date']?.toString(),
      technician: map['technician']?.toString(),
      description: map['description']?.toString() ?? '',
      result: map['result']?.toString(),
      nextDueDate: map['next_due_date']?.toString(),
      cost: map['cost']?.toString(),
      createdAt: map['created_at']?.toString(),
      reminderDays: int.tryParse(map['reminder_days']?.toString() ?? '0') ?? 0,
      repeatInterval: map['repeat_interval']?.toString() ?? 'none',
    );
  }
}

import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'app_theme.dart';
import 'maintenance_page.dart';
import 'maintenance_details_page.dart';

class MaintenanceCalendarPage extends StatefulWidget {
  const MaintenanceCalendarPage({super.key});

  @override
  State<MaintenanceCalendarPage> createState() => _MaintenanceCalendarPageState();
}

class _MaintenanceCalendarPageState extends State<MaintenanceCalendarPage> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<DateTime, List<MaintenanceItem>> _events = {};
  bool _loading = false;

  // For navigating to details, we need the context info
  List<MaintenanceAssetOption> _assets = [];
  final List<String> _statusOptions = ['pendiente', 'en_proceso', 'concluido', 'perdida'];
  final List<String> _typeOptions = ['preventivo', 'correctivo'];

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final client = Supabase.instance.client;
      
      // Load Assets for labels
      final assetsRes = await client.schema('sistema').from('assets').select('id, asset_tag, serial_number, status');
      _assets = (assetsRes as List).map((e) => MaintenanceAssetOption.fromMap(e)).toList();

      // Load Maintenance Events
      final eventsRes = await client
          .schema('sistema')
          .from('maintenance_events')
          .select()
          .not('scheduled_date', 'is', null);
      
      final List<MaintenanceItem> allEvents = (eventsRes as List).map((e) => MaintenanceItem.fromMap(e)).toList();
      
      // Group by date
      final Map<DateTime, List<MaintenanceItem>> eventMap = {};
      for (var e in allEvents) {
        if (e.scheduledDate != null) {
          final date = DateTime.parse(e.scheduledDate!).toLocal();
          final day = DateTime(date.year, date.month, date.day);
          if (eventMap[day] == null) eventMap[day] = [];
          eventMap[day]!.add(e);
        }
        // Also add next_due_date if present
        if (e.nextDueDate != null) {
           final date = DateTime.parse(e.nextDueDate!).toLocal();
           final day = DateTime(date.year, date.month, date.day);
           // We might want to label these as "PROXIMO"
           if (eventMap[day] == null) eventMap[day] = [];
           // To avoid duplicates if scheduled_date == next_due_date (unlikely but possible)
           if (!eventMap[day]!.any((item) => item.id == e.id)) {
             eventMap[day]!.add(e);
           }
        }
      }

      setState(() {
        _events = eventMap;
      });
    } catch (e) {
      debugPrint('Error loading calendar data: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<MaintenanceItem> _getEventsForDay(DateTime day) {
    final normalizedDay = DateTime(day.year, day.month, day.day);
    return _events[normalizedDay] ?? [];
  }

  String _assetLabelById(String? assetId) {
    if (assetId == null) return 'Nota General';
    final asset = _assets.firstWhere((a) => a.id == assetId, orElse: () => MaintenanceAssetOption(id: '', label: assetId, status: ''));
    return asset.label;
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pendiente': return Colors.orange;
      case 'en_proceso': return Colors.blue;
      case 'concluido': return Colors.green;
      case 'perdida': return Colors.red;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedEvents = _getEventsForDay(_selectedDay ?? _focusedDay);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendario de Mantenimiento'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: GradientBody(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 100), // Space for FAB
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: SectionCard(
                  child: TableCalendar<MaintenanceItem>(
                    firstDay: DateTime.utc(2020, 1, 1),
                    lastDay: DateTime.utc(2030, 12, 31),
                    focusedDay: _focusedDay,
                    calendarFormat: _calendarFormat,
                    selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                    onDaySelected: (selectedDay, focusedDay) {
                      setState(() {
                        _selectedDay = selectedDay;
                        _focusedDay = focusedDay;
                      });
                    },
                    onFormatChanged: (format) {
                      if (_calendarFormat != format) {
                        setState(() => _calendarFormat = format);
                      }
                    },
                    onPageChanged: (focusedDay) {
                      _focusedDay = focusedDay;
                    },
                    eventLoader: _getEventsForDay,
                    calendarStyle: CalendarStyle(
                      todayDecoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                      ),
                      selectedDecoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      markerDecoration: BoxDecoration(
                        color: theme.colorScheme.secondary,
                        shape: BoxShape.circle,
                      ),
                      markersMaxCount: 3,
                    ),
                    headerStyle: const HeaderStyle(
                      formatButtonVisible: true,
                      titleCentered: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (selectedEvents.isNotEmpty)
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: selectedEvents.length,
                  itemBuilder: (context, index) {
                    final event = selectedEvents[index];
                    final assetLabel = _assetLabelById(event.assetId);
                    final isNextDue = event.nextDueDate != null && 
                                     isSameDay(DateTime.parse(event.nextDueDate!).toLocal(), _selectedDay);

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SectionCard(
                        child: ListTile(
                          leading: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: _getStatusColor(event.status),
                              shape: BoxShape.circle,
                            ),
                          ),
                          title: Text(
                            '${event.type.toUpperCase()} - $assetLabel',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(event.description, maxLines: 1, overflow: TextOverflow.ellipsis),
                              if (isNextDue)
                                const Text('📅 Fecha de próximo servicio sugerida', 
                                  style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.blue)),
                            ],
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => MaintenanceDetailsPage(
                                  event: event,
                                  assetName: assetLabel,
                                  assets: _assets,
                                  statusOptions: _statusOptions,
                                  typeOptions: _typeOptions,
                                ),
                              ),
                            ).then((_) => _loadData());
                          },
                        ),
                      ),
                    );
                  },
                )
              else
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text('No hay eventos programados para este día'),
                  ),
                ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // Open create maintenance dialog pre-filling the selected date
          // For now, we can just navigate to the maintenance page or open the dialog
          // I'll leave a placeholder for "Agregar nota/fecha"
          _showAddNoteDialog();
        },
        icon: const Icon(Icons.add_task),
        label: const Text('Nueva Nota/Servicio'),
      ),
    );
  }

  Future<void> _saveEvent({
    required String? assetId,
    required String type,
    required String description,
    required DateTime date,
  }) async {
    setState(() => _loading = true);
    try {
      final client = Supabase.instance.client;
      final y = date.year.toString().padLeft(4, '0');
      final m = date.month.toString().padLeft(2, '0');
      final d = date.day.toString().padLeft(2, '0');
      final dateStr = '$y-$m-$d';

      await client.schema('sistema').from('maintenance_events').insert({
        'asset_id': assetId,
        'type': type,
        'status': 'pendiente',
        'scheduled_date': dateStr,
        'description': description,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Evento guardado correctamente')),
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showAddNoteDialog() {
    final descriptionCtrl = TextEditingController();
    String? selectedAssetId;
    String selectedType = 'preventivo';
    bool isGeneralNote = false;
    int reminderDays = 1;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Nueva Nota o Servicio'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  title: const Text('Nota general (sin activo)'),
                  value: isGeneralNote,
                  onChanged: (v) => setLocalState(() => isGeneralNote = v),
                ),
                if (!isGeneralNote) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedAssetId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Activo *'),
                    items: _assets.map((a) => DropdownMenuItem(value: a.id, child: Text(a.label))).toList(),
                    onChanged: (v) => setLocalState(() => selectedAssetId = v),
                  ),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedType,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Tipo'),
                  items: const [
                    DropdownMenuItem(value: 'preventivo', child: Text('Preventivo')),
                    DropdownMenuItem(value: 'correctivo', child: Text('Correctivo')),
                    DropdownMenuItem(value: 'nota', child: Text('Recordatorio / Nota')),
                  ],
                  onChanged: (v) => setLocalState(() => selectedType = v!),
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
                  decoration: const InputDecoration(labelText: 'Descripción / Nota *'),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                Text('Fecha programada: ${DateFormat('dd/MM/yyyy').format(_selectedDay ?? _focusedDay)}'),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                if (descriptionCtrl.text.trim().isEmpty) return;
                if (!isGeneralNote && selectedAssetId == null) return;
                
                Navigator.pop(context);
                _saveEvent(
                  assetId: isGeneralNote ? null : selectedAssetId,
                  type: selectedType,
                  description: descriptionCtrl.text.trim(),
                  date: _selectedDay ?? _focusedDay,
                );
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }
}

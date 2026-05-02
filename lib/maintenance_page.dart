import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';

import 'app_theme.dart';
import 'photo_manager_page.dart';
import 'photo_upload_helper.dart';

class MaintenancePage extends StatefulWidget {
  const MaintenancePage({super.key});

  @override
  State<MaintenancePage> createState() => _MaintenancePageState();
}

class _MaintenancePageState extends State<MaintenancePage> {
  final _technicianCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _resultCtrl = TextEditingController();
  final _costCtrl = TextEditingController();

  final List<String> _typeOptions = ['preventivo', 'correctivo'];
  final List<String> _statusOptions = ['pendiente', 'en_proceso', 'concluido'];

  List<_AssetOption> _assets = [];
  List<_MaintenanceItem> _events = [];
  List<DraftPhoto> _pendingPhotos = [];
  String? _selectedAssetId;
  String _selectedType = 'preventivo';
  String _selectedStatus = 'pendiente';
  String _filterStatus = 'todos';
  String _filterHealth = 'todos';
  DateTime? _scheduledDate;
  DateTime? _performedDate;
  DateTime? _nextDueDate;
  DateTime? _completedDate;
  bool _loading = false;
  bool _saving = false;
  String _status = 'Carga de mantenimientos pendiente.';

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _technicianCtrl.dispose();
    _descriptionCtrl.dispose();
    _resultCtrl.dispose();
    _costCtrl.dispose();
    super.dispose();
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
          .inFilter('status', ['activo', 'mantenimiento'])
          .order('asset_tag');

      final eventsResponse = await _client
          .schema('sistema')
          .from('maintenance_events')
          .select(
            'id, asset_id, type, scheduled_date, performed_date, '
            'technician, description, result, next_due_date, cost, created_at, '
            'status, completed_date',
          )
          .order('created_at', ascending: false)
          .limit(50);

      final assets = (assetsResponse as List<dynamic>)
          .map((e) => _AssetOption.fromMap(e as Map<String, dynamic>))
          .toList();
      final events = (eventsResponse as List<dynamic>)
          .map((e) => _MaintenanceItem.fromMap(e as Map<String, dynamic>))
          .toList();

      setState(() {
        _assets = assets;
        _events = events;
        if (_assets.isEmpty) {
          _selectedAssetId = null;
          _status = 'No hay activos activos/mantenimiento para registrar.';
        } else {
          final exists = _assets.any((asset) => asset.id == _selectedAssetId);
          _selectedAssetId = exists ? _selectedAssetId : _assets.first.id;
          _status = 'Mantenimientos cargados: ${_events.length}.';
        }
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

  Future<bool> _createMaintenance() async {
    if (_selectedAssetId == null) {
      setState(() => _status = 'Selecciona un activo.');
      return false;
    }
    if (_descriptionCtrl.text.trim().isEmpty) {
      setState(() => _status = 'Captura una descripcion del mantenimiento.');
      return false;
    }

    final costText = _costCtrl.text.trim();
    final cost = costText.isEmpty ? null : double.tryParse(costText);
    if (costText.isNotEmpty && cost == null) {
      setState(() => _status = 'Costo invalido. Usa formato numerico.');
      return false;
    }

    setState(() => _saving = true);
    try {
      final created = await _client.schema('sistema').from('maintenance_events').insert({
        'asset_id': _selectedAssetId,
        'type': _selectedType,
        'status': _selectedStatus,
        'scheduled_date': _toDbDate(_scheduledDate),
        'performed_date': _toDbDate(_performedDate),
        'technician':
            _technicianCtrl.text.trim().isEmpty ? null : _technicianCtrl.text.trim(),
        'description': _descriptionCtrl.text.trim(),
        'result': _resultCtrl.text.trim().isEmpty ? null : _resultCtrl.text.trim(),
        'next_due_date': _toDbDate(_nextDueDate),
        'completed_date': _toDbDate(
          _selectedStatus == 'concluido'
              ? (_completedDate ?? DateTime.now())
              : null,
        ),
        'cost': cost,
      }).select('id').single();
      final maintenanceId = created['id']?.toString();

      _technicianCtrl.clear();
      _descriptionCtrl.clear();
      _resultCtrl.clear();
      _costCtrl.clear();
      setState(() {
        _selectedStatus = 'pendiente';
        _scheduledDate = null;
        _performedDate = null;
        _nextDueDate = null;
        _completedDate = null;
        _status = 'Mantenimiento registrado correctamente.';
      });

      if (maintenanceId != null && _selectedAssetId != null && _pendingPhotos.isNotEmpty) {
        final uploadResult = await PhotoUploadHelper.uploadDraftPhotos(
          assetId: _selectedAssetId!,
          maintenanceEventId: maintenanceId,
          photos: _pendingPhotos,
          description: 'Foto inicial de mantenimiento',
        );
        setState(() {
          _status = uploadResult.ok
              ? 'Mantenimiento y fotos guardados.'
              : 'Mantenimiento guardado, fotos con error: ${uploadResult.message}';
          if (uploadResult.ok) {
            _pendingPhotos = [];
          }
        });
      }

      await _loadData();
      return true;
    } on PostgrestException catch (e) {
      setState(() => _status = 'Error al registrar mantenimiento: ${e.message}');
    } catch (e) {
      setState(() => _status = 'Error inesperado: $e');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
    return false;
  }

  void _resetCreateForm() {
    _selectedStatus = 'pendiente';
    _selectedType = 'preventivo';
    _scheduledDate = null;
    _performedDate = null;
    _nextDueDate = null;
    _completedDate = null;
    _technicianCtrl.clear();
    _descriptionCtrl.clear();
    _resultCtrl.clear();
    _costCtrl.clear();
    _pendingPhotos = [];
    if (_assets.isNotEmpty) {
      _selectedAssetId = _assets.first.id;
    }
  }

  Future<void> _openCreateMaintenanceDialog() async {
    _resetCreateForm();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> pickPhotos() async {
              final result = await FilePicker.platform.pickFiles(
                withData: true,
                allowMultiple: true,
              );
              final files = result?.files.where((f) => f.bytes != null).toList() ?? [];
              if (files.isEmpty) return;
              setState(() {
                _pendingPhotos.addAll(
                  files.map(
                    (f) => DraftPhoto(
                      bytes: f.bytes!,
                      fileName: f.name.isEmpty ? 'foto.jpg' : f.name,
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
              final ok = await _createMaintenance();
              if (!mounted) return;
              if (ok) {
                Navigator.of(this.context).pop();
              }
              setSheetState(() {});
            }

            Future<void> pickDateField({
              required DateTime? currentValue,
              required ValueChanged<DateTime?> onChanged,
            }) async {
              final picked = await showDatePicker(
                context: context,
                initialDate: currentValue ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) {
                setState(() => onChanged(picked));
                setSheetState(() {});
              }
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
                        'Nuevo mantenimiento',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      InputDecorator(
                        decoration: const InputDecoration(labelText: 'Activo *'),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedAssetId,
                            hint: const Text('Selecciona activo'),
                            isExpanded: true,
                            items: _assets
                                .map(
                                  (asset) => DropdownMenuItem<String>(
                                    value: asset.id,
                                    child: Text(asset.label),
                                  ),
                                )
                                .toList(),
                            onChanged: _saving
                                ? null
                                : (value) {
                                    setState(() => _selectedAssetId = value);
                                    setSheetState(() {});
                                  },
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      InputDecorator(
                        decoration: const InputDecoration(labelText: 'Tipo *'),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedType,
                            isExpanded: true,
                            items: _typeOptions
                                .map(
                                  (item) => DropdownMenuItem<String>(
                                    value: item,
                                    child: Text(item),
                                  ),
                                )
                                .toList(),
                            onChanged: _saving
                                ? null
                                : (value) {
                                    if (value != null) {
                                      setState(() => _selectedType = value);
                                      setSheetState(() {});
                                    }
                                  },
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      InputDecorator(
                        decoration: const InputDecoration(labelText: 'Estatus *'),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedStatus,
                            isExpanded: true,
                            items: _statusOptions
                                .map(
                                  (item) => DropdownMenuItem<String>(
                                    value: item,
                                    child: Text(_statusLabel(item)),
                                  ),
                                )
                                .toList(),
                            onChanged: _saving
                                ? null
                                : (value) {
                                    if (value != null) {
                                      setState(() {
                                        _selectedStatus = value;
                                        if (_selectedStatus == 'concluido' &&
                                            _completedDate == null) {
                                          _completedDate = DateTime.now();
                                        }
                                        if (_selectedStatus != 'concluido') {
                                          _completedDate = null;
                                        }
                                      });
                                      setSheetState(() {});
                                    }
                                  },
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _technicianCtrl,
                        decoration: const InputDecoration(labelText: 'Tecnico'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _descriptionCtrl,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(labelText: 'Descripcion *'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _resultCtrl,
                        minLines: 1,
                        maxLines: 3,
                        decoration: const InputDecoration(labelText: 'Resultado'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _costCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Costo'),
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
                            onPressed: _saving ? null : pickPhotos,
                            icon: const Icon(Icons.photo_library_outlined),
                            label: const Text('Agregar 1 o mas'),
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
                            (index) => Stack(
                              clipBehavior: Clip.none,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.memory(
                                    _pendingPhotos[index].bytes,
                                    width: 64,
                                    height: 64,
                                    fit: BoxFit.cover,
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
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _saving
                                ? null
                                : () => pickDateField(
                                      currentValue: _scheduledDate,
                                      onChanged: (v) => _scheduledDate = v,
                                    ),
                            icon: const Icon(Icons.event_note),
                            label: Text('Programado: ${_displayDate(_scheduledDate)}'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _saving
                                ? null
                                : () => pickDateField(
                                      currentValue: _performedDate,
                                      onChanged: (v) => _performedDate = v,
                                    ),
                            icon: const Icon(Icons.build_circle_outlined),
                            label: Text('Realizado: ${_displayDate(_performedDate)}'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _saving
                                ? null
                                : () => pickDateField(
                                      currentValue: _nextDueDate,
                                      onChanged: (v) => _nextDueDate = v,
                                    ),
                            icon: const Icon(Icons.schedule),
                            label: Text('Proximo: ${_displayDate(_nextDueDate)}'),
                          ),
                          OutlinedButton.icon(
                            onPressed: (_saving || _selectedStatus != 'concluido')
                                ? null
                                : () => pickDateField(
                                      currentValue: _completedDate,
                                      onChanged: (v) => _completedDate = v,
                                    ),
                            icon: const Icon(Icons.task_alt),
                            label: Text('Termino: ${_displayDate(_completedDate)}'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _saving ? null : submit,
                        icon: const Icon(Icons.save),
                        label: Text(_saving ? 'Guardando...' : 'Guardar mantenimiento'),
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

  String? _toDbDate(DateTime? value) {
    if (value == null) {
      return null;
    }
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _displayDate(DateTime? value) {
    if (value == null) {
      return '-';
    }
    return _toDbDate(value) ?? '-';
  }

  List<_MaintenanceItem> _filteredEvents() {
    var result = _events;
    if (_filterStatus != 'todos') {
      result = result.where((event) => event.status == _filterStatus).toList();
    }
    if (_filterHealth != 'todos') {
      result = result
          .where((event) => _semaforoState(event).id == _filterHealth)
          .toList();
    }
    return result;
  }

  DateTime? _parseDbDate(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value);
  }

  Future<void> _updateMaintenance({
    required _MaintenanceItem event,
    required String? assetId,
    required String type,
    required String status,
    required DateTime? scheduledDate,
    required DateTime? performedDate,
    required String technician,
    required String description,
    required String result,
    required DateTime? nextDueDate,
    required DateTime? completedDate,
    required String costText,
  }) async {
    if (assetId == null) {
      setState(() => _status = 'Selecciona un activo para actualizar.');
      return;
    }
    if (description.trim().isEmpty) {
      setState(() => _status = 'La descripcion no puede quedar vacia.');
      return;
    }

    final normalizedCostText = costText.trim();
    final cost = normalizedCostText.isEmpty ? null : double.tryParse(normalizedCostText);
    if (normalizedCostText.isNotEmpty && cost == null) {
      setState(() => _status = 'Costo invalido. Usa formato numerico.');
      return;
    }

    setState(() => _saving = true);
    try {
      await _client.schema('sistema').from('maintenance_events').update({
        'asset_id': assetId,
        'type': type,
        'status': status,
        'scheduled_date': _toDbDate(scheduledDate),
        'performed_date': _toDbDate(performedDate),
        'technician': technician.trim().isEmpty ? null : technician.trim(),
        'description': description.trim(),
        'result': result.trim().isEmpty ? null : result.trim(),
        'next_due_date': _toDbDate(nextDueDate),
        'completed_date': _toDbDate(
          status == 'concluido' ? (completedDate ?? DateTime.now()) : null,
        ),
        'cost': cost,
      }).eq('id', event.id);

      setState(() => _status = 'Mantenimiento actualizado correctamente.');
      await _loadData();
    } on PostgrestException catch (e) {
      setState(() => _status = 'Error al actualizar mantenimiento: ${e.message}');
    } catch (e) {
      setState(() => _status = 'Error inesperado: $e');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _openEditDialog(_MaintenanceItem event) async {
    final descriptionCtrl = TextEditingController(text: event.description);
    final technicianCtrl = TextEditingController(text: event.technician ?? '');
    final resultCtrl = TextEditingController(text: event.result ?? '');
    final costCtrl = TextEditingController(text: event.cost ?? '');
    String? currentAssetId = event.assetId;
    String currentType = event.type;
    String currentStatus = event.status;
    DateTime? currentScheduledDate = _parseDbDate(event.scheduledDate);
    DateTime? currentPerformedDate = _parseDbDate(event.performedDate);
    DateTime? currentNextDueDate = _parseDbDate(event.nextDueDate);
    DateTime? currentCompletedDate = _parseDbDate(event.completedDate);

    final save = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            Future<void> pickLocalDate({
              required DateTime? value,
              required ValueChanged<DateTime?> onChanged,
            }) async {
              final picked = await showDatePicker(
                context: context,
                initialDate: value ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) {
                setLocalState(() {
                  onChanged(picked);
                });
              }
            }

            return AlertDialog(
              title: const Text('Editar mantenimiento'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InputDecorator(
                      decoration: const InputDecoration(labelText: 'Activo'),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: currentAssetId,
                          hint: const Text('Selecciona activo'),
                          isExpanded: true,
                          items: _assets
                              .map(
                                (asset) => DropdownMenuItem<String>(
                                  value: asset.id,
                                  child: Text(asset.label),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setLocalState(() => currentAssetId = value);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    InputDecorator(
                      decoration: const InputDecoration(labelText: 'Tipo'),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: currentType,
                          isExpanded: true,
                          items: _typeOptions
                              .map(
                                (type) => DropdownMenuItem<String>(
                                  value: type,
                                  child: Text(type),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setLocalState(() => currentType = value);
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    InputDecorator(
                      decoration: const InputDecoration(labelText: 'Estatus'),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: currentStatus,
                          isExpanded: true,
                          items: _statusOptions
                              .map(
                                (status) => DropdownMenuItem<String>(
                                  value: status,
                                  child: Text(_statusLabel(status)),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setLocalState(() {
                                currentStatus = value;
                                if (currentStatus == 'concluido' &&
                                    currentCompletedDate == null) {
                                  currentCompletedDate = DateTime.now();
                                }
                                if (currentStatus != 'concluido') {
                                  currentCompletedDate = null;
                                }
                              });
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: technicianCtrl,
                      decoration: const InputDecoration(labelText: 'Tecnico'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: descriptionCtrl,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(labelText: 'Descripcion *'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: resultCtrl,
                      minLines: 1,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'Resultado'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: costCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Costo'),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: () => pickLocalDate(
                            value: currentScheduledDate,
                            onChanged: (v) => currentScheduledDate = v,
                          ),
                          child: Text('Programado: ${_displayDate(currentScheduledDate)}'),
                        ),
                        OutlinedButton(
                          onPressed: () => pickLocalDate(
                            value: currentPerformedDate,
                            onChanged: (v) => currentPerformedDate = v,
                          ),
                          child: Text('Realizado: ${_displayDate(currentPerformedDate)}'),
                        ),
                        OutlinedButton(
                          onPressed: () => pickLocalDate(
                            value: currentNextDueDate,
                            onChanged: (v) => currentNextDueDate = v,
                          ),
                          child: Text('Proximo: ${_displayDate(currentNextDueDate)}'),
                        ),
                        OutlinedButton(
                          onPressed: currentStatus == 'concluido'
                              ? () => pickLocalDate(
                                    value: currentCompletedDate,
                                    onChanged: (v) => currentCompletedDate = v,
                                  )
                              : null,
                          child: Text(
                            'Termino: ${_displayDate(currentCompletedDate)}',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Guardar cambios'),
                ),
              ],
            );
          },
        );
      },
    );

    if (save == true) {
      await _updateMaintenance(
        event: event,
        assetId: currentAssetId,
        type: currentType,
        status: currentStatus,
        scheduledDate: currentScheduledDate,
        performedDate: currentPerformedDate,
        technician: technicianCtrl.text,
        description: descriptionCtrl.text,
        result: resultCtrl.text,
        nextDueDate: currentNextDueDate,
        completedDate: currentCompletedDate,
        costText: costCtrl.text,
      );
    }

    descriptionCtrl.dispose();
    technicianCtrl.dispose();
    resultCtrl.dispose();
    costCtrl.dispose();
  }

  String _assetLabelById(String? assetId) {
    if (assetId == null) {
      return 'Sin activo';
    }
    for (final item in _assets) {
      if (item.id == assetId) {
        return item.label;
      }
    }
    return assetId;
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pendiente':
        return 'Pendiente';
      case 'en_proceso':
        return 'En proceso';
      case 'concluido':
        return 'Concluido';
      default:
        return status;
    }
  }

  _SemaforoState _semaforoState(_MaintenanceItem event) {
    if (event.status == 'concluido') {
      return const _SemaforoState(
        id: 'concluido',
        label: 'Concluido',
        color: Colors.green,
      );
    }

    final dueDate = _parseDbDate(event.nextDueDate);
    if (dueDate == null) {
      return const _SemaforoState(
        id: 'sin_fecha',
        label: 'Sin fecha compromiso',
        color: Colors.grey,
      );
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final days = due.difference(today).inDays;

    if (days < 0) {
      return const _SemaforoState(
        id: 'vencido',
        label: 'Vencido',
        color: Colors.red,
      );
    }
    if (days <= 2) {
      return const _SemaforoState(
        id: 'por_vencer',
        label: 'Por vencer',
        color: Colors.orange,
      );
    }
    return const _SemaforoState(
      id: 'en_tiempo',
      label: 'En tiempo',
      color: Colors.blue,
    );
  }

  Future<void> _openMaintenancePhotoManager(_MaintenanceItem event) async {
    if (event.assetId == null || event.assetId!.isEmpty) {
      setState(
        () => _status = 'Este mantenimiento no tiene activo asociado.',
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhotoManagerPage(
          title: 'Fotos mantenimiento',
          assetId: event.assetId!,
          maintenanceEventId: event.id,
        ),
      ),
    );
    setState(() => _status = 'Gestor de fotos cerrado.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mantenimientos'),
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
                _status,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          Text(
            'Ultimos mantenimientos (${_filteredEvents().length})',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Filtrar por estatus',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _FilterPill(
                        label: 'Todos',
                        selected: _filterStatus == 'todos',
                        onTap: () => setState(() => _filterStatus = 'todos'),
                      ),
                      _FilterPill(
                        label: 'Pendiente',
                        selected: _filterStatus == 'pendiente',
                        onTap: () => setState(() => _filterStatus = 'pendiente'),
                      ),
                      _FilterPill(
                        label: 'En proceso',
                        selected: _filterStatus == 'en_proceso',
                        onTap: () => setState(() => _filterStatus = 'en_proceso'),
                      ),
                      _FilterPill(
                        label: 'Concluido',
                        selected: _filterStatus == 'concluido',
                        onTap: () => setState(() => _filterStatus = 'concluido'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Filtrar por semaforo',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _FilterPill(
                        label: 'Todos',
                        selected: _filterHealth == 'todos',
                        onTap: () => setState(() => _filterHealth = 'todos'),
                      ),
                      _FilterPill(
                        label: 'Vencido',
                        selected: _filterHealth == 'vencido',
                        onTap: () => setState(() => _filterHealth = 'vencido'),
                        dotColor: Colors.red,
                      ),
                      _FilterPill(
                        label: 'Por vencer',
                        selected: _filterHealth == 'por_vencer',
                        onTap: () => setState(() => _filterHealth = 'por_vencer'),
                        dotColor: Colors.orange,
                      ),
                      _FilterPill(
                        label: 'En tiempo',
                        selected: _filterHealth == 'en_tiempo',
                        onTap: () => setState(() => _filterHealth = 'en_tiempo'),
                        dotColor: Colors.blue,
                      ),
                      _FilterPill(
                        label: 'Sin fecha',
                        selected: _filterHealth == 'sin_fecha',
                        onTap: () => setState(() => _filterHealth = 'sin_fecha'),
                        dotColor: Colors.grey,
                      ),
                      _FilterPill(
                        label: 'Concluido',
                        selected: _filterHealth == 'concluido',
                        onTap: () => setState(() => _filterHealth = 'concluido'),
                        dotColor: Colors.green,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (_filteredEvents().isEmpty)
            const Text('Aun no hay mantenimientos registrados.')
          else
            ..._filteredEvents().map(
              (event) {
                final semaforo = _semaforoState(event);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SectionCard(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _openEditDialog(event),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Icon(
                                  event.type == 'correctivo'
                                      ? Icons.warning_amber_rounded
                                      : Icons.handyman_outlined,
                                  color: semaforo.color,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '${event.type.toUpperCase()} - ${_assetLabelById(event.assetId)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 19,
                                  ),
                                ),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'editar') {
                                    _openEditDialog(event);
                                  } else if (value == 'foto') {
                                    _openMaintenancePhotoManager(event);
                                  }
                                },
                                itemBuilder: (context) => const [
                                  PopupMenuItem<String>(
                                    value: 'foto',
                                    child: Text('Gestionar fotos'),
                                  ),
                                  PopupMenuItem<String>(
                                    value: 'editar',
                                    child: Text('Editar mantenimiento'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Programado: ${event.scheduledDate ?? '-'} | '
                            'Realizado: ${event.performedDate ?? '-'}',
                          ),
                          Text(
                            'Tecnico: ${event.technician ?? '-'} | '
                            'Costo: ${event.cost ?? '-'}',
                          ),
                          Text(
                            'Proximo: ${event.nextDueDate ?? '-'} | '
                            'Termino: ${event.completedDate ?? '-'}',
                          ),
                          Text(
                            'Estatus: ${_statusLabel(event.status)} | '
                            'Semaforo: ${semaforo.label}',
                          ),
                          const SizedBox(height: 6),
                          Text(event.description),
                          if (event.result != null && event.result!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text('Resultado: ${event.result}'),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Agregar mantenimiento',
        onPressed: (_loading || _saving) ? null : _openCreateMaintenanceDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _SemaforoState {
  final String id;
  final String label;
  final Color color;

  const _SemaforoState({
    required this.id,
    required this.label,
    required this.color,
  });
}

class _FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? dotColor;

  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.dotColor,
  });

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
            color: selected
                ? scheme.primary.withValues(alpha: 0.2)
                : scheme.surfaceContainerHighest.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.65)
                  : scheme.outline.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dotColor != null) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssetOption {
  final String id;
  final String label;

  const _AssetOption({
    required this.id,
    required this.label,
  });

  factory _AssetOption.fromMap(Map<String, dynamic> map) {
    final id = map['id']?.toString() ?? '';
    final tag = map['asset_tag']?.toString() ?? 'Sin tag';
    final serial = map['serial_number']?.toString();
    final status = map['status']?.toString() ?? 'activo';
    final baseLabel = (serial == null || serial.isEmpty) ? tag : '$tag - $serial';
    return _AssetOption(
      id: id,
      label: '$baseLabel [$status]',
    );
  }
}

class _MaintenanceItem {
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

  const _MaintenanceItem({
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
  });

  factory _MaintenanceItem.fromMap(Map<String, dynamic> map) {
    return _MaintenanceItem(
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
    );
  }
}

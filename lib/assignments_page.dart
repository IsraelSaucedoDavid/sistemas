import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'assignment_acknowledgement_page.dart';
import 'assignment_evidence_page.dart';
import 'app_theme.dart';
import 'photo_upload_helper.dart';
import 'person_directory_service.dart';

class AssignmentsPage extends StatefulWidget {
  const AssignmentsPage({super.key});

  @override
  State<AssignmentsPage> createState() => _AssignmentsPageState();
}

class _AssignmentsPageState extends State<AssignmentsPage> {
  final _searchCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _institutionalEmailCtrl = TextEditingController();
  final _institutionalPasswordCtrl = TextEditingController();
  final _pcPasswordCtrl = TextEditingController();
  final _filterCtrl = TextEditingController();
  Timer? _debounce;

  List<_AssetOption> _assets = [];
  List<_AssignmentItem> _assignments = [];
  List<ExternalPerson> _searchResults = [];
  ExternalPerson? _selectedPerson;
  String? _selectedAssetId;
  bool _loading = false;
  bool _saving = false;
  bool _searchingPeople = false;
  _AssignmentFilterStatus _statusFilter = _AssignmentFilterStatus.all;
  String _status = 'Carga de asignaciones pendiente.';

  SupabaseClient get _client => Supabase.instance.client;

  void _disposeControllerLater(TextEditingController controller) {
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      controller.dispose();
    });
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _notesCtrl.dispose();
    _institutionalEmailCtrl.dispose();
    _institutionalPasswordCtrl.dispose();
    _pcPasswordCtrl.dispose();
    _filterCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (_client.auth.currentSession == null) {
      setState(() => _status = 'Inicia sesion para gestionar asignaciones.');
      return;
    }

    setState(() => _loading = true);
    try {
      final assetsRows = await _client
          .schema('sistema')
          .from('assets')
          .select('id, asset_tag, serial_number, status')
          .neq('status', 'baja')
          .order('asset_tag');

      final assignmentsRows = await _client
          .schema('sistema')
          .from('assignments')
          .select(
            'id, asset_id, person_id, assigned_at, returned_at, notes, '
            'institutional_email, institutional_password, pc_password, '
            'assets(asset_tag,serial_number), '
            'people(full_name,email,department), '
            'assignment_acknowledgements(signer_name,signer_email,signature_path,pdf_path,accepted_terms,signed_at,email_status,email_sent_at)',
          )
          .order('assigned_at', ascending: false)
          .limit(80);

      final assets = (assetsRows as List<dynamic>)
          .map((e) => _AssetOption.fromMap(e as Map<String, dynamic>))
          .toList();
      final assignments = (assignmentsRows as List<dynamic>)
          .map((e) => _AssignmentItem.fromMap(e as Map<String, dynamic>))
          .toList();

      setState(() {
        _assets = assets;
        _assignments = assignments;
        if (_assets.isNotEmpty) {
          final exists = _assets.any((a) => a.id == _selectedAssetId);
          _selectedAssetId = exists ? _selectedAssetId : _assets.first.id;
        } else {
          _selectedAssetId = null;
        }
        _status = 'Asignaciones cargadas: ${_assignments.length}.';
      });
    } on PostgrestException catch (e) {
      setState(() => _status = 'Error cargando asignaciones: ${e.message}');
    } catch (e) {
      setState(() => _status = 'Error inesperado: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _onSearchChanged(String value, {VoidCallback? onResults}) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final q = value.trim();
      if (q.length < 2) {
        if (mounted) {
          setState(() {
            _searchingPeople = false;
            _searchResults = [];
          });
          onResults?.call();
        }
        return;
      }
      if (mounted) {
        setState(() => _searchingPeople = true);
        onResults?.call();
      }
      try {
        final people = await PersonDirectoryService.searchPeople(q);
        if (!mounted) return;
        setState(() {
          _searchingPeople = false;
          _searchResults = people;
        });
        onResults?.call();
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _searchingPeople = false;
          _status = 'Error buscando personal: $e';
        });
        onResults?.call();
      }
    });
  }

  Future<String> _ensurePersonRecord(ExternalPerson person) async {
    final email = person.email?.trim();
    final employeeCode = person.employeeCode?.trim().isNotEmpty == true
        ? person.employeeCode!.trim()
        : (person.externalId?.trim().isNotEmpty == true
              ? 'ext_${person.externalId!.trim()}'
              : null);

    if (employeeCode != null) {
      final existing = await _client
          .schema('sistema')
          .from('people')
          .select('id')
          .eq('employee_code', employeeCode)
          .limit(1);
      if ((existing as List).isNotEmpty) {
        return existing.first['id'].toString();
      }
    }

    if (email != null && email.isNotEmpty) {
      final existing = await _client
          .schema('sistema')
          .from('people')
          .select('id')
          .eq('email', email)
          .limit(1);
      if ((existing as List).isNotEmpty) {
        return existing.first['id'].toString();
      }
    }

    final inserted = await _client
        .schema('sistema')
        .from('people')
        .insert({
          'employee_code': employeeCode,
          'full_name': person.fullName,
          'email': (email == null || email.isEmpty) ? null : email,
          'department': person.department,
        })
        .select('id')
        .single();

    return inserted['id'].toString();
  }

  Future<_CreatedAssignmentContext?> _createAssignment({
    required List<DraftPhoto> entregaPhotos,
    String? entregaDescription,
  }) async {
    if (_selectedAssetId == null) {
      setState(() => _status = 'Selecciona un activo.');
      return null;
    }
    final person = _selectedPerson;
    if (person == null) {
      setState(() => _status = 'Selecciona una persona de la busqueda.');
      return null;
    }

    setState(() => _saving = true);
    try {
      final personId = await _ensurePersonRecord(person);

      await _client
          .schema('sistema')
          .from('assignments')
          .update({'returned_at': DateTime.now().toIso8601String()})
          .eq('asset_id', _selectedAssetId!)
          .isFilter('returned_at', null);

      final inserted = await _client
          .schema('sistema')
          .from('assignments')
          .insert({
            'asset_id': _selectedAssetId,
            'person_id': personId,
            'notes': _notesCtrl.text.trim().isEmpty
                ? null
                : _notesCtrl.text.trim(),
            'institutional_email': _institutionalEmailCtrl.text.trim().isEmpty
                ? null
                : _institutionalEmailCtrl.text.trim(),
            'institutional_password':
                _institutionalPasswordCtrl.text.trim().isEmpty
                ? null
                : _institutionalPasswordCtrl.text.trim(),
            'pc_password': _pcPasswordCtrl.text.trim().isEmpty
                ? null
                : _pcPasswordCtrl.text.trim(),
          })
          .select('id, asset_id, assigned_at')
          .single();

      final assignmentId = inserted['id']?.toString();
      final assetId = inserted['asset_id']?.toString();
      final assignedAt = inserted['assigned_at']?.toString();
      _AssetOption? selectedAsset;
      for (final asset in _assets) {
        if (asset.id == _selectedAssetId) {
          selectedAsset = asset;
          break;
        }
      }
      final selectedPersonSnapshot = _selectedPerson;
      final notesValue = _notesCtrl.text.trim().isEmpty
          ? null
          : _notesCtrl.text.trim();
      final institutionalEmailValue =
          _institutionalEmailCtrl.text.trim().isEmpty
          ? null
          : _institutionalEmailCtrl.text.trim();
      if (assignmentId != null && assetId != null && entregaPhotos.isNotEmpty) {
        final uploadResult =
            await PhotoUploadHelper.uploadAssignmentDraftPhotos(
              assignmentId: assignmentId,
              assetId: assetId,
              phase: 'entrega',
              description: entregaDescription,
              photos: entregaPhotos,
            );
        if (!uploadResult.ok) {
          setState(() {
            _status =
                'Asignacion registrada, pero fallo evidencia de entrega: ${uploadResult.message}';
          });
        }
      }

      setState(() {
        _selectedPerson = null;
        _searchCtrl.clear();
        _searchResults = [];
        _notesCtrl.clear();
        _institutionalEmailCtrl.clear();
        _institutionalPasswordCtrl.clear();
        _pcPasswordCtrl.clear();
        _status = 'Asignacion registrada correctamente.';
      });

      await _loadData();
      if (assignmentId != null &&
          assetId != null &&
          selectedPersonSnapshot != null) {
        return _CreatedAssignmentContext(
          assignmentId: assignmentId,
          assetId: assetId,
          assetLabel: selectedAsset?.label ?? 'Activo asignado',
          personName: selectedPersonSnapshot.fullName,
          personEmail: selectedPersonSnapshot.email,
          assignedAt: assignedAt,
          notes: notesValue,
          institutionalEmail: institutionalEmailValue,
        );
      }
      return null;
    } on PostgrestException catch (e) {
      setState(() => _status = 'Error guardando asignacion: ${e.message}');
    } catch (e) {
      setState(() => _status = 'Error inesperado: $e');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
    return null;
  }

  Future<void> _pickDraftPhotos(
    List<DraftPhoto> target,
    VoidCallback refresh,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      allowMultiple: true,
    );
    final files = result?.files.where((f) => f.bytes != null).toList() ?? [];
    if (files.isEmpty) return;
    target.addAll(
      files.map(
        (f) => DraftPhoto(
          bytes: f.bytes!,
          fileName: f.name.isEmpty ? 'foto.jpg' : f.name,
        ),
      ),
    );
    refresh();
  }

  Future<void> _takeDraftPhoto(
    List<DraftPhoto> target,
    VoidCallback refresh,
  ) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (image == null) return;
    final bytes = await image.readAsBytes();
    target.add(
      DraftPhoto(
        bytes: bytes,
        fileName: image.name.isEmpty ? 'camera.jpg' : image.name,
      ),
    );
    refresh();
  }

  Widget _draftPhotosPreview(List<DraftPhoto> photos, VoidCallback onChanged) {
    if (photos.isEmpty) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: List.generate(
        photos.length,
        (index) => Stack(
          clipBehavior: Clip.none,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                photos[index].bytes,
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
                  onTap: _saving
                      ? null
                      : () {
                          photos.removeAt(index);
                          onChanged();
                        },
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 14, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openCreateDialog() async {
    _selectedPerson = null;
    _searchCtrl.clear();
    _searchResults = [];
    _searchingPeople = false;
    _notesCtrl.clear();
    _institutionalEmailCtrl.clear();
    _institutionalPasswordCtrl.clear();
    _pcPasswordCtrl.clear();
    final pendingEntregaPhotos = <DraftPhoto>[];
    final entregaDescriptionCtrl = TextEditingController();
    var showInstitutionalPassword = false;
    var showPcPassword = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nueva asignacion',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Activo *',
                        ),
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
                      TextField(
                        controller: _searchCtrl,
                        onChanged: (value) {
                          setState(() => _selectedPerson = null);
                          _onSearchChanged(
                            value,
                            onResults: () {
                              if (!mounted) return;
                              setSheetState(() {});
                            },
                          );
                          setSheetState(() {});
                        },
                        decoration: InputDecoration(
                          labelText: 'Buscar persona en contacto *',
                          hintText:
                              'Nombre, apellido paterno/materno, ID o correo',
                          suffixIcon: _searchingPeople
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : const Icon(Icons.search),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_selectedPerson != null)
                        Text(
                          'Seleccionado: ${_selectedPerson!.fullName}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      if (_searchResults.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 220,
                          child: ListView.builder(
                            itemCount: _searchResults.length,
                            itemBuilder: (context, index) {
                              final p = _searchResults[index];
                              return ListTile(
                                dense: true,
                                title: Text(p.fullName),
                                subtitle: Text(
                                  'ID: ${p.externalId ?? '-'} | ${p.email ?? '-'}',
                                ),
                                trailing: const Icon(
                                  Icons.arrow_forward_ios,
                                  size: 14,
                                ),
                                onTap: _saving
                                    ? null
                                    : () {
                                        setState(() {
                                          _selectedPerson = p;
                                          _searchCtrl.text = p.fullName;
                                          _searchResults = [];
                                        });
                                        setSheetState(() {});
                                      },
                              );
                            },
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      TextField(
                        controller: _notesCtrl,
                        minLines: 2,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Notas (opcional)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _institutionalEmailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Correo institucional (opcional)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _institutionalPasswordCtrl,
                        obscureText: !showInstitutionalPassword,
                        decoration: InputDecoration(
                          labelText: 'Contrasena de correo (opcional)',
                          suffixIcon: IconButton(
                            onPressed: () {
                              setSheetState(
                                () => showInstitutionalPassword =
                                    !showInstitutionalPassword,
                              );
                            },
                            icon: Icon(
                              showInstitutionalPassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _pcPasswordCtrl,
                        obscureText: !showPcPassword,
                        decoration: InputDecoration(
                          labelText: 'Contrasena de la PC (opcional)',
                          suffixIcon: IconButton(
                            onPressed: () {
                              setSheetState(
                                () => showPcPassword = !showPcPassword,
                              );
                            },
                            icon: Icon(
                              showPcPassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Evidencia de entrega (${pendingEntregaPhotos.length})',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: entregaDescriptionCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Descripcion de fotos (opcional)',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _saving
                                ? null
                                : () => _pickDraftPhotos(
                                    pendingEntregaPhotos,
                                    () => setSheetState(() {}),
                                  ),
                            icon: const Icon(Icons.photo_library_outlined),
                            label: const Text('Agregar 1 o mas'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _saving
                                ? null
                                : () => _takeDraftPhoto(
                                    pendingEntregaPhotos,
                                    () => setSheetState(() {}),
                                  ),
                            icon: const Icon(Icons.photo_camera_outlined),
                            label: const Text('Tomar foto'),
                          ),
                        ],
                      ),
                      if (pendingEntregaPhotos.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _draftPhotosPreview(
                          pendingEntregaPhotos,
                          () => setSheetState(() {}),
                        ),
                      ],
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _saving
                            ? null
                            : () async {
                                final created = await _createAssignment(
                                  entregaPhotos: pendingEntregaPhotos,
                                  entregaDescription:
                                      entregaDescriptionCtrl.text,
                                );
                                if (!context.mounted) return;
                                if (created != null) {
                                  Navigator.of(context).pop();
                                  if (!mounted) return;
                                  await _openAcknowledgementPageFromCreated(
                                    created,
                                  );
                                } else {
                                  setSheetState(() {});
                                }
                              },
                        icon: const Icon(Icons.assignment_ind_outlined),
                        label: Text(
                          _saving ? 'Guardando...' : 'Asignar equipo',
                        ),
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
    _disposeControllerLater(entregaDescriptionCtrl);
  }

  Future<void> _openReturnDialog(_AssignmentItem item) async {
    if (item.returnedAt != null) return;
    final returnPhotos = <DraftPhoto>[];
    final returnDescriptionCtrl = TextEditingController();
    final returnNoteCtrl = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cerrar asignacion',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.assetLabel,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: returnNoteCtrl,
                        minLines: 2,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Nota de devolucion (opcional)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Fotos de devolucion * (${returnPhotos.length})',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: returnDescriptionCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Descripcion de fotos (opcional)',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _saving
                                ? null
                                : () => _pickDraftPhotos(
                                    returnPhotos,
                                    () => setSheetState(() {}),
                                  ),
                            icon: const Icon(Icons.photo_library_outlined),
                            label: const Text('Agregar 1 o mas'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _saving
                                ? null
                                : () => _takeDraftPhoto(
                                    returnPhotos,
                                    () => setSheetState(() {}),
                                  ),
                            icon: const Icon(Icons.photo_camera_outlined),
                            label: const Text('Tomar foto'),
                          ),
                        ],
                      ),
                      if (returnPhotos.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _draftPhotosPreview(
                          returnPhotos,
                          () => setSheetState(() {}),
                        ),
                      ],
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _saving
                            ? null
                            : () async {
                                final ok = await _closeAssignmentWithEvidence(
                                  item: item,
                                  returnPhotos: returnPhotos,
                                  photoDescription: returnDescriptionCtrl.text,
                                  returnNote: returnNoteCtrl.text,
                                );
                                if (!context.mounted) return;
                                if (ok) {
                                  Navigator.of(context).pop();
                                } else {
                                  setSheetState(() {});
                                }
                              },
                        icon: const Icon(Icons.assignment_return_outlined),
                        label: Text(
                          _saving ? 'Guardando...' : 'Confirmar devolucion',
                        ),
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

    _disposeControllerLater(returnDescriptionCtrl);
    _disposeControllerLater(returnNoteCtrl);
  }

  Future<bool> _closeAssignmentWithEvidence({
    required _AssignmentItem item,
    required List<DraftPhoto> returnPhotos,
    required String photoDescription,
    required String returnNote,
  }) async {
    if (item.assetId == null || item.assetId!.isEmpty) {
      setState(() => _status = 'No se encontro el activo de la asignacion.');
      return false;
    }
    if (returnPhotos.isEmpty) {
      setState(() => _status = 'Agrega al menos una foto de devolucion.');
      return false;
    }

    setState(() => _saving = true);
    try {
      final uploadResult = await PhotoUploadHelper.uploadAssignmentDraftPhotos(
        assignmentId: item.id,
        assetId: item.assetId!,
        phase: 'devolucion',
        description: photoDescription,
        photos: returnPhotos,
      );
      if (!uploadResult.ok) {
        setState(
          () =>
              _status = 'No se pudo guardar evidencia: ${uploadResult.message}',
        );
        return false;
      }

      final note = returnNote.trim();
      final nowIso = DateTime.now().toIso8601String();
      final mergedNote = note.isEmpty
          ? item.notes
          : (item.notes == null || item.notes!.trim().isEmpty)
          ? '[DEVOLUCION] $note'
          : '${item.notes}\n[DEVOLUCION] $note';

      await _client
          .schema('sistema')
          .from('assignments')
          .update({'returned_at': nowIso, 'notes': mergedNote})
          .eq('id', item.id);
      setState(() => _status = 'Asignacion cerrada con evidencia.');
      await _loadData();
      return true;
    } on PostgrestException catch (e) {
      setState(() => _status = 'Error cerrando asignacion: ${e.message}');
    } catch (e) {
      setState(() => _status = 'Error inesperado: $e');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
    return false;
  }

  Future<void> _openEvidencePage(_AssignmentItem item) async {
    final assetId = item.assetId;
    if (assetId == null || assetId.isEmpty) {
      setState(() => _status = 'No se encontro el activo de esta asignacion.');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AssignmentEvidencePage(
          assignmentId: item.id,
          assetId: assetId,
          assetLabel: item.assetLabel,
        ),
      ),
    );
    if (!mounted) return;
    await _loadData();
  }

  Future<void> _openAcknowledgementPage(_AssignmentItem item) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AssignmentAcknowledgementPage(
          assignmentId: item.id,
          assetLabel: item.assetLabel,
          personName: item.personName,
          personEmail: item.personEmail,
          assignedAt: item.assignedAt,
          notes: item.notes,
          institutionalEmail: item.institutionalEmail,
        ),
      ),
    );
  }

  Future<void> _openAcknowledgementPageFromCreated(
    _CreatedAssignmentContext created,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AssignmentAcknowledgementPage(
          assignmentId: created.assignmentId,
          assetLabel: created.assetLabel,
          personName: created.personName,
          personEmail: created.personEmail,
          assignedAt: created.assignedAt,
          notes: created.notes,
          institutionalEmail: created.institutionalEmail,
        ),
      ),
    );
  }

  Future<({int entrega, int devolucion})> _loadEvidenceSummary(
    String assignmentId,
  ) async {
    final rows = await _client
        .schema('sistema')
        .from('assignment_photos')
        .select('phase')
        .eq('assignment_id', assignmentId);
    var entrega = 0;
    var devolucion = 0;
    for (final row in (rows as List<dynamic>)) {
      final phase = (row as Map<String, dynamic>)['phase']?.toString();
      if (phase == 'entrega') entrega++;
      if (phase == 'devolucion') devolucion++;
    }
    return (entrega: entrega, devolucion: devolucion);
  }

  List<_AssignmentItem> get _filteredAssignments {
    final query = _filterCtrl.text.trim().toLowerCase();
    return _assignments.where((item) {
      final statusOk = switch (_statusFilter) {
        _AssignmentFilterStatus.all => true,
        _AssignmentFilterStatus.active => item.returnedAt == null,
        _AssignmentFilterStatus.returned => item.returnedAt != null,
      };
      if (!statusOk) return false;
      if (query.isEmpty) return true;
      final haystack =
          '${item.assetLabel} ${item.personName} ${item.personDepartment ?? ''} ${item.notes ?? ''} ${item.institutionalEmail ?? ''}'
              .toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  Future<bool> _updateAssignment({
    required _AssignmentItem item,
    required String? assetId,
    required String notes,
    required String institutionalEmail,
    required String institutionalPassword,
    required String pcPassword,
  }) async {
    if (assetId == null || assetId.isEmpty) {
      setState(() => _status = 'Selecciona un activo.');
      return false;
    }

    setState(() => _saving = true);
    try {
      await _client
          .schema('sistema')
          .from('assignments')
          .update({
            'asset_id': assetId,
            'notes': notes.trim().isEmpty ? null : notes.trim(),
            'institutional_email': institutionalEmail.trim().isEmpty
                ? null
                : institutionalEmail.trim(),
            'institutional_password': institutionalPassword.trim().isEmpty
                ? null
                : institutionalPassword.trim(),
            'pc_password': pcPassword.trim().isEmpty ? null : pcPassword.trim(),
          })
          .eq('id', item.id);

      setState(() => _status = 'Asignacion actualizada correctamente.');
      await _loadData();
      return true;
    } on PostgrestException catch (e) {
      setState(() => _status = 'Error actualizando asignacion: ${e.message}');
    } catch (e) {
      setState(() => _status = 'Error inesperado: $e');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
    return false;
  }

  Future<void> _openEditDialog(_AssignmentItem item) async {
    var selectedAssetId = item.assetId ?? _selectedAssetId;
    final notesCtrl = TextEditingController(text: item.notes ?? '');
    final institutionalEmailCtrl = TextEditingController(
      text: item.institutionalEmail ?? '',
    );
    final institutionalPasswordCtrl = TextEditingController(
      text: item.institutionalPassword ?? '',
    );
    final pcPasswordCtrl = TextEditingController(text: item.pcPassword ?? '');
    var showInstitutionalPassword = false;
    var showPcPassword = false;
    var entregaCount = 0;
    var devolucionCount = 0;
    try {
      final summary = await _loadEvidenceSummary(item.id);
      entregaCount = summary.entrega;
      devolucionCount = summary.devolucion;
    } catch (_) {
      // Si falla el conteo, solo mostramos 0/0 y el usuario aun puede gestionar evidencias.
    }
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Editar asignacion',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Activo *',
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: selectedAssetId,
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
                                    setSheetState(
                                      () => selectedAssetId = value,
                                    );
                                  },
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        item.returnedAt == null
                            ? 'Estatus: ASIGNADO'
                            : 'Estatus: DEVUELTO',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      if (item.returnedAt == null)
                        Text(
                          'Para cerrar la asignacion usa "Marcar devolucion" para adjuntar evidencias.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: notesCtrl,
                        minLines: 2,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Notas (opcional)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: institutionalEmailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Correo institucional (opcional)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: institutionalPasswordCtrl,
                        obscureText: !showInstitutionalPassword,
                        decoration: InputDecoration(
                          labelText: 'Contrasena de correo (opcional)',
                          suffixIcon: IconButton(
                            onPressed: () {
                              setSheetState(
                                () => showInstitutionalPassword =
                                    !showInstitutionalPassword,
                              );
                            },
                            icon: Icon(
                              showInstitutionalPassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: pcPasswordCtrl,
                        obscureText: !showPcPassword,
                        decoration: InputDecoration(
                          labelText: 'Contrasena de la PC (opcional)',
                          suffixIcon: IconButton(
                            onPressed: () {
                              setSheetState(
                                () => showPcPassword = !showPcPassword,
                              );
                            },
                            icon: Icon(
                              showPcPassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _saving
                            ? null
                            : () async {
                                Navigator.of(context).pop();
                                await _openEvidencePage(item);
                              },
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Gestionar fotos y evidencias'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _saving
                            ? null
                            : () async {
                                Navigator.of(context).pop();
                                await _openAcknowledgementPage(item);
                              },
                        icon: const Icon(Icons.draw_outlined),
                        label: const Text('Acta y firma de entrega'),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Chip(
                            avatar: const Icon(Icons.upload_file, size: 16),
                            label: Text('Entrega ($entregaCount)'),
                            backgroundColor: Colors.blue.withValues(
                              alpha: 0.15,
                            ),
                          ),
                          Chip(
                            avatar: const Icon(
                              Icons.assignment_return,
                              size: 16,
                            ),
                            label: Text('Devolucion ($devolucionCount)'),
                            backgroundColor: Colors.green.withValues(
                              alpha: 0.16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _saving
                            ? null
                            : () async {
                                final ok = await _updateAssignment(
                                  item: item,
                                  assetId: selectedAssetId,
                                  notes: notesCtrl.text,
                                  institutionalEmail:
                                      institutionalEmailCtrl.text,
                                  institutionalPassword:
                                      institutionalPasswordCtrl.text,
                                  pcPassword: pcPasswordCtrl.text,
                                );
                                if (!context.mounted) return;
                                if (ok) {
                                  Navigator.of(context).pop();
                                } else {
                                  setSheetState(() {});
                                }
                              },
                        icon: const Icon(Icons.save_outlined),
                        label: Text(
                          _saving ? 'Guardando...' : 'Guardar cambios',
                        ),
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

    _disposeControllerLater(notesCtrl);
    _disposeControllerLater(institutionalEmailCtrl);
    _disposeControllerLater(institutionalPasswordCtrl);
    _disposeControllerLater(pcPasswordCtrl);
  }

  String _formatDateTime(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '-';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    final dt = parsed.toLocal();
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  Widget _detailRow(String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
              decoration: TextDecoration.none,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: scheme.onSurface.withValues(alpha: 0.9),
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mailStatusBadge(_AssignmentItem item) {
    final status = (item.emailStatus ?? '').trim().toLowerCase();
    late final String label;
    late final Color fg;
    late final Color bg;

    if (status == 'sent') {
      label = 'CORREO ENVIADO';
      fg = Colors.green.shade300;
      bg = Colors.green.withValues(alpha: 0.18);
    } else if (status == 'error') {
      label = 'ERROR DE CORREO';
      fg = Colors.red.shade300;
      bg = Colors.red.withValues(alpha: 0.18);
    } else {
      label = 'CORREO PENDIENTE';
      fg = Colors.amber.shade300;
      bg = Colors.amber.withValues(alpha: 0.2);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: bg,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }

  Future<_AssignmentFullDetails> _loadAssignmentFullDetails(
    _AssignmentItem item,
  ) async {
    final entregaPhotos = await PhotoUploadHelper.fetchAssignmentPhotos(
      assignmentId: item.id,
      phase: 'entrega',
    );
    final devolucionPhotos = await PhotoUploadHelper.fetchAssignmentPhotos(
      assignmentId: item.id,
      phase: 'devolucion',
    );

    String? signatureUrl;
    final signaturePath = item.ackSignaturePath;
    if (signaturePath != null && signaturePath.trim().isNotEmpty) {
      try {
        signatureUrl = await _client.storage
            .from('assignment-signatures')
            .createSignedUrl(signaturePath, 3600);
      } catch (_) {
        signatureUrl = null;
      }
    }

    String? pdfUrl;
    final pdfPath = item.ackPdfPath;
    if (pdfPath != null && pdfPath.trim().isNotEmpty) {
      try {
        pdfUrl = await _client.storage
            .from('assignment-documents')
            .createSignedUrl(pdfPath, 3600);
      } catch (_) {
        pdfUrl = null;
      }
    }

    return _AssignmentFullDetails(
      entregaPhotos: entregaPhotos,
      devolucionPhotos: devolucionPhotos,
      signatureUrl: signatureUrl,
      pdfUrl: pdfUrl,
    );
  }

  Future<void> _openAssignmentDetails(_AssignmentItem item) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final detailsFuture = _loadAssignmentFullDetails(item);
        var showPasswords = false;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: StatefulBuilder(
              builder: (context, setModalState) {
                return FutureBuilder<_AssignmentFullDetails>(
                  future: detailsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SizedBox(
                        height: 300,
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (snapshot.hasError) {
                      return SizedBox(
                        height: 300,
                        child: Center(
                          child: Text(
                            'No se pudo cargar el detalle: ${snapshot.error}',
                          ),
                        ),
                      );
                    }
                    final details = snapshot.data!;
                    final isReturned = item.returnedAt != null;
                    return SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Detalle de asignacion',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _statusChip(
                                context: context,
                                label: isReturned ? 'Devuelto' : 'Asignado',
                                color: isReturned
                                    ? Colors.grey.shade700
                                    : Colors.green.shade700,
                              ),
                              _statusChip(
                                context: context,
                                label: _mailStatusText(item.emailStatus),
                                color: _mailStatusColor(item.emailStatus),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _detailsSection(
                            context: context,
                            title: 'Informacion general',
                            icon: Icons.info_outline,
                            children: [
                              _modalDetailRow('Activo', item.assetLabel),
                              _modalDetailRow('Persona', item.personName),
                              _modalDetailRow(
                                'Correo persona',
                                item.personEmail ?? '-',
                              ),
                              _modalDetailRow(
                                'Departamento',
                                item.personDepartment ?? '-',
                              ),
                              _modalDetailRow(
                                'Asignado desde',
                                _formatDateTime(item.assignedAt),
                              ),
                              _modalDetailRow(
                                'Regreso',
                                isReturned
                                    ? _formatDateTime(item.returnedAt)
                                    : 'Activo',
                              ),
                              if (item.notes != null &&
                                  item.notes!.trim().isNotEmpty)
                                _modalDetailRow('Notas', item.notes!),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _detailsSection(
                            context: context,
                            title: 'Credenciales',
                            icon: Icons.lock_outline,
                            trailing: IconButton(
                              tooltip: showPasswords
                                  ? 'Ocultar contrasenas'
                                  : 'Mostrar contrasenas',
                              onPressed: () {
                                setModalState(() {
                                  showPasswords = !showPasswords;
                                });
                              },
                              icon: Icon(
                                showPasswords
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                            ),
                            children: [
                              _modalDetailRow(
                                'Correo institucional',
                                item.institutionalEmail ?? '-',
                              ),
                              _modalDetailRow(
                                'Contrasena correo',
                                _maskSecret(
                                  item.institutionalPassword,
                                  show: showPasswords,
                                ),
                              ),
                              _modalDetailRow(
                                'Contrasena PC',
                                _maskSecret(
                                  item.pcPassword,
                                  show: showPasswords,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _detailsSection(
                            context: context,
                            title: 'Acta y firma',
                            icon: Icons.draw_outlined,
                            children: [
                              _modalDetailRow(
                                'Firmante',
                                item.ackSignerName ?? '-',
                              ),
                              _modalDetailRow(
                                'Correo firmante',
                                item.ackSignerEmail ?? '-',
                              ),
                              _modalDetailRow(
                                'Acepto terminos',
                                item.ackAcceptedTerms ? 'Si' : 'No',
                              ),
                              _modalDetailRow(
                                'Fecha firma',
                                _formatDateTime(item.ackSignedAt),
                              ),
                              if (details.signatureUrl != null) ...[
                                const SizedBox(height: 8),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest
                                        .withValues(alpha: 0.35),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      details.signatureUrl!,
                                      height: 120,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              if (details.pdfUrl != null)
                                OutlinedButton.icon(
                                  onPressed: () => showDialog<void>(
                                    context: context,
                                    builder: (_) => AlertDialog(
                                      title: const Text('URL temporal del PDF'),
                                      content: SelectableText(details.pdfUrl!),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(context).pop(),
                                          child: const Text('Cerrar'),
                                        ),
                                      ],
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.picture_as_pdf_outlined,
                                  ),
                                  label: const Text('Ver URL del acta PDF'),
                                )
                              else if ((item.ackPdfPath ?? '').isNotEmpty)
                                _modalDetailRow('PDF (path)', item.ackPdfPath!),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _detailsSection(
                            context: context,
                            title:
                                'Evidencias de entrega (${details.entregaPhotos.length})',
                            icon: Icons.photo_camera_back_outlined,
                            children: [_photosStrip(details.entregaPhotos)],
                          ),
                          const SizedBox(height: 10),
                          _detailsSection(
                            context: context,
                            title:
                                'Evidencias de devolucion (${details.devolucionPhotos.length})',
                            icon: Icons.assignment_return_outlined,
                            children: [_photosStrip(details.devolucionPhotos)],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _detailsSection({
    required BuildContext context,
    required String title,
    required IconData icon,
    required List<Widget> children,
    Widget? trailing,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.28),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              ...[trailing].nonNulls,
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _modalDetailRow(String label, String value) {
    final safeValue = value.trim().isEmpty ? '-' : value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          SelectableText(
            safeValue,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _statusChip({
    required BuildContext context,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.16),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  String _mailStatusText(String? statusRaw) {
    final status = (statusRaw ?? '').trim().toLowerCase();
    if (status == 'sent') return 'Correo enviado';
    if (status == 'error') return 'Correo con error';
    return 'Correo pendiente';
  }

  Color _mailStatusColor(String? statusRaw) {
    final status = (statusRaw ?? '').trim().toLowerCase();
    if (status == 'sent') return Colors.green.shade700;
    if (status == 'error') return Colors.red.shade700;
    return Colors.amber.shade800;
  }

  String _maskSecret(String? input, {required bool show}) {
    final value = (input ?? '').trim();
    if (value.isEmpty) return '-';
    if (show) return value;
    return '********';
  }

  Widget _photosStrip(List<AssignmentPhotoDocument> photos) {
    if (photos.isEmpty) {
      return const Text('Sin fotos registradas.');
    }
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final photo = photos[index];
          return FutureBuilder<String>(
            future: PhotoUploadHelper.getSignedAssignmentPhotoUrl(
              photo.filePath,
            ),
            builder: (context, snapshot) {
              final url = snapshot.data;
              return GestureDetector(
                onTap: url == null
                    ? null
                    : () => showDialog<void>(
                        context: context,
                        builder: (context) {
                          return Dialog(
                            child: InteractiveViewer(
                              child: Image.network(url, fit: BoxFit.contain),
                            ),
                          );
                        },
                      ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 84,
                    height: 84,
                    child: url == null
                        ? Container(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.4),
                            child: const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : Image.network(url, fit: BoxFit.cover),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _resendAssignmentEmail(_AssignmentItem item) async {
    final toEmail = (item.institutionalEmail?.trim().isNotEmpty == true)
        ? item.institutionalEmail!.trim()
        : (item.ackSignerEmail?.trim().isNotEmpty == true)
        ? item.ackSignerEmail!.trim()
        : null;
    final signerName = (item.ackSignerName?.trim().isNotEmpty == true)
        ? item.ackSignerName!.trim()
        : item.personName;
    final pdfPath = item.ackPdfPath?.trim();

    if (toEmail == null || toEmail.isEmpty) {
      setState(() => _status = 'No hay correo destino para reenviar.');
      return;
    }
    if (pdfPath == null || pdfPath.isEmpty) {
      setState(() => _status = 'No hay PDF de acta para reenviar.');
      return;
    }

    setState(() => _saving = true);
    try {
      final response = await _client.functions.invoke(
        'send-assignment-notification',
        body: {
          'assignmentId': item.id,
          'toEmail': toEmail,
          'assetLabel': item.assetLabel,
          'signerName': signerName,
          'assignedAt': item.assignedAt,
          'pdfPath': pdfPath,
        },
      );
      if (!mounted) return;
      if (response.status >= 200 && response.status < 300) {
        setState(() => _status = 'Correo reenviado correctamente.');
      } else {
        setState(
          () => _status =
              'Fallo el reenvio de correo (${response.status}): ${response.data}',
        );
      }
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Error reenviando correo: $e');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredAssignments = _filteredAssignments;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Asignaciones'),
        actions: [
          const ThemeToggleButton(),
          IconButton(
            tooltip: 'Recargar',
            onPressed: _loading ? null : _loadData,
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
            const SizedBox(height: 12),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Filtros',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Todos'),
                        selected: _statusFilter == _AssignmentFilterStatus.all,
                        onSelected: (v) {
                          if (!v) return;
                          setState(
                            () => _statusFilter = _AssignmentFilterStatus.all,
                          );
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Asignado'),
                        selected:
                            _statusFilter == _AssignmentFilterStatus.active,
                        onSelected: (v) {
                          if (!v) return;
                          setState(
                            () =>
                                _statusFilter = _AssignmentFilterStatus.active,
                          );
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Devuelto'),
                        selected:
                            _statusFilter == _AssignmentFilterStatus.returned,
                        onSelected: (v) {
                          if (!v) return;
                          setState(
                            () => _statusFilter =
                                _AssignmentFilterStatus.returned,
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _filterCtrl,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Buscar activo/persona/depto/nota',
                      suffixIcon: _filterCtrl.text.isEmpty
                          ? const Icon(Icons.search)
                          : IconButton(
                              onPressed: () {
                                _filterCtrl.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.clear),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Asignaciones (${filteredAssignments.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (filteredAssignments.isEmpty)
              const SectionCard(child: Text('No hay asignaciones registradas.'))
            else
              ...filteredAssignments.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GestureDetector(
                    onTap: () => _openAssignmentDetails(item),
                    child: SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: item.returnedAt == null
                                    ? Theme.of(context).colorScheme.primary
                                          .withValues(alpha: 0.18)
                                    : Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest
                                          .withValues(alpha: 0.8),
                                child: Icon(
                                  item.returnedAt == null
                                      ? Icons.assignment_turned_in_outlined
                                      : Icons.assignment_return_outlined,
                                  size: 18,
                                  color: item.returnedAt == null
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  item.assetLabel,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 18,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 9,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(999),
                                      color: item.returnedAt == null
                                          ? Colors.green.withValues(alpha: 0.18)
                                          : Colors.grey.withValues(alpha: 0.18),
                                    ),
                                    child: Text(
                                      item.returnedAt == null
                                          ? 'ASIGNADO'
                                          : 'DEVUELTO',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: item.returnedAt == null
                                            ? Colors.green.shade400
                                            : Colors.grey.shade400,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  _mailStatusBadge(item),
                                ],
                              ),
                              const SizedBox(width: 2),
                              IconButton(
                                tooltip: 'Editar asignacion',
                                onPressed: _saving
                                    ? null
                                    : () => _openEditDialog(item),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _detailRow('Persona', item.personName),
                          _detailRow('Depto', item.personDepartment ?? '-'),
                          _detailRow('Desde', _formatDateTime(item.assignedAt)),
                          _detailRow(
                            'Regreso',
                            item.returnedAt == null
                                ? 'Activo'
                                : _formatDateTime(item.returnedAt),
                          ),
                          if (item.institutionalEmail != null &&
                              item.institutionalEmail!.trim().isNotEmpty)
                            _detailRow(
                              'Correo institucional',
                              item.institutionalEmail!,
                            ),
                          if ((item.institutionalPassword != null &&
                                  item.institutionalPassword!
                                      .trim()
                                      .isNotEmpty) ||
                              (item.pcPassword != null &&
                                  item.pcPassword!.trim().isNotEmpty))
                            const Padding(
                              padding: EdgeInsets.only(bottom: 6),
                              child: Text(
                                'Credenciales: configuradas',
                                style: TextStyle(
                                  fontStyle: FontStyle.italic,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          if (item.notes != null &&
                              item.notes!.trim().isNotEmpty)
                            _detailRow('Nota', item.notes!),
                          if ((item.emailStatus ?? '').toLowerCase() ==
                                  'error' ||
                              ((item.emailStatus ?? '').isEmpty &&
                                  item.ackPdfPath != null &&
                                  item.ackPdfPath!.trim().isNotEmpty)) ...[
                            const SizedBox(height: 4),
                            Align(
                              alignment: Alignment.centerRight,
                              child: OutlinedButton.icon(
                                onPressed: _saving
                                    ? null
                                    : () => _resendAssignmentEmail(item),
                                icon: const Icon(
                                  Icons.mark_email_read_outlined,
                                ),
                                label: const Text('Reenviar correo'),
                              ),
                            ),
                          ],
                          if (item.returnedAt == null) ...[
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerRight,
                              child: OutlinedButton.icon(
                                onPressed: _saving
                                    ? null
                                    : () => _openReturnDialog(item),
                                icon: const Icon(
                                  Icons.assignment_return_outlined,
                                ),
                                label: const Text('Marcar devolucion'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Nueva asignacion',
        onPressed: (_loading || _saving) ? null : _openCreateDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _AssetOption {
  final String id;
  final String label;

  const _AssetOption({required this.id, required this.label});

  factory _AssetOption.fromMap(Map<String, dynamic> map) {
    final id = map['id']?.toString() ?? '';
    final tag = map['asset_tag']?.toString() ?? 'Sin tag';
    final serial = map['serial_number']?.toString();
    final status = map['status']?.toString() ?? 'activo';
    final label = (serial == null || serial.isEmpty) ? tag : '$tag - $serial';
    return _AssetOption(id: id, label: '$label [$status]');
  }
}

class _AssignmentItem {
  final String id;
  final String? assetId;
  final String assetLabel;
  final String personName;
  final String? personEmail;
  final String? personDepartment;
  final String? assignedAt;
  final String? returnedAt;
  final String? notes;
  final String? institutionalEmail;
  final String? institutionalPassword;
  final String? pcPassword;
  final String? ackSignerName;
  final String? ackSignerEmail;
  final String? ackSignaturePath;
  final String? ackPdfPath;
  final bool ackAcceptedTerms;
  final String? ackSignedAt;
  final String? emailStatus;
  final String? emailSentAt;

  const _AssignmentItem({
    required this.id,
    required this.assetId,
    required this.assetLabel,
    required this.personName,
    required this.personEmail,
    required this.personDepartment,
    required this.assignedAt,
    required this.returnedAt,
    required this.notes,
    required this.institutionalEmail,
    required this.institutionalPassword,
    required this.pcPassword,
    required this.ackSignerName,
    required this.ackSignerEmail,
    required this.ackSignaturePath,
    required this.ackPdfPath,
    required this.ackAcceptedTerms,
    required this.ackSignedAt,
    required this.emailStatus,
    required this.emailSentAt,
  });

  factory _AssignmentItem.fromMap(Map<String, dynamic> map) {
    final assetMap = map['assets'] as Map<String, dynamic>?;
    final personMap = map['people'] as Map<String, dynamic>?;
    final ackRaw = map['assignment_acknowledgements'];
    Map<String, dynamic>? ackMap;
    if (ackRaw is Map<String, dynamic>) {
      ackMap = ackRaw;
    } else if (ackRaw is List &&
        ackRaw.isNotEmpty &&
        ackRaw.first is Map<String, dynamic>) {
      ackMap = ackRaw.first as Map<String, dynamic>;
    }
    final tag = assetMap?['asset_tag']?.toString() ?? 'Sin activo';
    final serial = assetMap?['serial_number']?.toString();
    final assetLabel = (serial == null || serial.isEmpty)
        ? tag
        : '$tag - $serial';
    return _AssignmentItem(
      id: map['id']?.toString() ?? '',
      assetId: map['asset_id']?.toString(),
      assetLabel: assetLabel,
      personName: personMap?['full_name']?.toString() ?? 'Sin persona',
      personEmail: personMap?['email']?.toString(),
      personDepartment: personMap?['department']?.toString(),
      assignedAt: map['assigned_at']?.toString(),
      returnedAt: map['returned_at']?.toString(),
      notes: map['notes']?.toString(),
      institutionalEmail: map['institutional_email']?.toString(),
      institutionalPassword: map['institutional_password']?.toString(),
      pcPassword: map['pc_password']?.toString(),
      ackSignerName: ackMap?['signer_name']?.toString(),
      ackSignerEmail: ackMap?['signer_email']?.toString(),
      ackSignaturePath: ackMap?['signature_path']?.toString(),
      ackPdfPath: ackMap?['pdf_path']?.toString(),
      ackAcceptedTerms: ackMap?['accepted_terms'] == true,
      ackSignedAt: ackMap?['signed_at']?.toString(),
      emailStatus: ackMap?['email_status']?.toString(),
      emailSentAt: ackMap?['email_sent_at']?.toString(),
    );
  }
}

class _AssignmentFullDetails {
  final List<AssignmentPhotoDocument> entregaPhotos;
  final List<AssignmentPhotoDocument> devolucionPhotos;
  final String? signatureUrl;
  final String? pdfUrl;

  const _AssignmentFullDetails({
    required this.entregaPhotos,
    required this.devolucionPhotos,
    required this.signatureUrl,
    required this.pdfUrl,
  });
}

class _CreatedAssignmentContext {
  final String assignmentId;
  final String assetId;
  final String assetLabel;
  final String personName;
  final String? personEmail;
  final String? assignedAt;
  final String? notes;
  final String? institutionalEmail;

  const _CreatedAssignmentContext({
    required this.assignmentId,
    required this.assetId,
    required this.assetLabel,
    required this.personName,
    required this.personEmail,
    required this.assignedAt,
    required this.notes,
    required this.institutionalEmail,
  });
}

enum _AssignmentFilterStatus { all, active, returned }

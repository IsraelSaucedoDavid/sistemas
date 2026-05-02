import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:signature/signature.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_theme.dart';

class AssignmentAcknowledgementPage extends StatefulWidget {
  final String assignmentId;
  final String assetLabel;
  final String personName;
  final String? personEmail;
  final String? assignedAt;
  final String? notes;
  final String? institutionalEmail;

  const AssignmentAcknowledgementPage({
    super.key,
    required this.assignmentId,
    required this.assetLabel,
    required this.personName,
    required this.personEmail,
    required this.assignedAt,
    required this.notes,
    required this.institutionalEmail,
  });

  @override
  State<AssignmentAcknowledgementPage> createState() =>
      _AssignmentAcknowledgementPageState();
}

class _AssignmentAcknowledgementPageState
    extends State<AssignmentAcknowledgementPage> {
  final _signerNameCtrl = TextEditingController();
  final _signerEmailCtrl = TextEditingController();
  final SignatureController _signatureCtrl = SignatureController(
    penStrokeWidth: 2.3,
    penColor: Colors.white,
    exportBackgroundColor: Colors.black,
  );

  bool _acceptedTerms = false;
  bool _saving = false;
  String _status = 'Pendiente de firma.';

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _signerNameCtrl.text = widget.personName;
    _signerEmailCtrl.text = widget.personEmail ?? '';
  }

  @override
  void dispose() {
    _signerNameCtrl.dispose();
    _signerEmailCtrl.dispose();
    _signatureCtrl.dispose();
    super.dispose();
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

  Future<void> _saveAcknowledgement() async {
    final signerName = _signerNameCtrl.text.trim();
    final signerEmail = _signerEmailCtrl.text.trim();

    if (signerName.isEmpty) {
      setState(() => _status = 'Captura el nombre de quien recibe.');
      return;
    }
    if (!_acceptedTerms) {
      setState(() => _status = 'Debes aceptar los terminos del resguardo.');
      return;
    }
    if (_signatureCtrl.isEmpty) {
      setState(() => _status = 'Agrega la firma para confirmar la entrega.');
      return;
    }

    setState(() => _saving = true);
    try {
      final signatureBytes = await _signatureCtrl.toPngBytes();
      if (signatureBytes == null || signatureBytes.isEmpty) {
        setState(() => _status = 'No se pudo generar la imagen de firma.');
        return;
      }

      final pdfBytes = await _buildActaPdf(signatureBytes);
      final signaturePath = await _uploadSignature(signatureBytes);
      final pdfPath = await _uploadActaPdf(pdfBytes);
      await _upsertAcknowledgement(
        signerName: signerName,
        signerEmail: signerEmail.isEmpty ? null : signerEmail,
        signaturePath: signaturePath,
        pdfPath: pdfPath,
      );
      final destination = (widget.institutionalEmail?.trim().isNotEmpty == true)
          ? widget.institutionalEmail!.trim()
          : (signerEmail.isEmpty ? null : signerEmail);
      if (destination == null) {
        setState(
          () => _status =
              'Acta firmada y guardada. No se envio correo porque no hay destinatario.',
        );
      } else {
        final sent = await _sendAssignmentEmail(
          toEmail: destination,
          signerName: signerName,
          pdfPath: pdfPath,
        );
        setState(
          () => _status = sent
              ? 'Acta firmada y correo enviado correctamente.'
              : 'Acta firmada, pero fallo el envio de correo.',
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on StorageException catch (e) {
      setState(() => _status = 'Error storage firma: ${e.message}');
    } on PostgrestException catch (e) {
      setState(() => _status = 'Error BD firma: ${e.message}');
    } catch (e) {
      setState(() => _status = 'Error inesperado en firma: $e');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<String> _uploadSignature(Uint8List bytes) async {
    final safePerson = widget.personName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final path =
        'assignment/${widget.assignmentId}/signature/${DateTime.now().microsecondsSinceEpoch}_${safePerson.isEmpty ? 'firmante' : safePerson}.png';

    await _client.storage.from('assignment-signatures').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: false),
        );
    return path;
  }

  Future<void> _upsertAcknowledgement({
    required String signerName,
    required String? signerEmail,
    required String signaturePath,
    required String pdfPath,
  }) async {
    final existing = await _client
        .schema('sistema')
        .from('assignment_acknowledgements')
        .select('id')
        .eq('assignment_id', widget.assignmentId)
        .limit(1);

    final payload = {
      'assignment_id': widget.assignmentId,
      'signer_name': signerName,
      'signer_email': signerEmail,
      'signature_path': signaturePath,
      'pdf_path': pdfPath,
      'accepted_terms': true,
      'signed_at': DateTime.now().toIso8601String(),
      'email_status': null,
      'email_error': null,
      'email_sent_at': null,
    };

    if ((existing as List).isEmpty) {
      await _client.schema('sistema').from('assignment_acknowledgements').insert(
            payload,
          );
      return;
    }

    final existingId = existing.first['id']?.toString();
    if (existingId == null || existingId.isEmpty) {
      await _client.schema('sistema').from('assignment_acknowledgements').insert(
            payload,
          );
      return;
    }
    await _client
        .schema('sistema')
        .from('assignment_acknowledgements')
        .update(payload)
        .eq('id', existingId);
  }

  Future<Uint8List> _buildActaPdf(Uint8List signatureBytes) async {
    final doc = pw.Document();
    final signatureImage = pw.MemoryImage(signatureBytes);
    final nowText = _formatDateTime(DateTime.now().toIso8601String());
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Acta de entrega de equipo TI',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Text('Fecha de firma: $nowText'),
              pw.SizedBox(height: 6),
              pw.Text('Activo: ${widget.assetLabel}'),
              pw.Text('Responsable: ${widget.personName}'),
              pw.Text('Fecha de asignacion: ${_formatDateTime(widget.assignedAt)}'),
              if (widget.institutionalEmail != null &&
                  widget.institutionalEmail!.trim().isNotEmpty)
                pw.Text('Correo institucional: ${widget.institutionalEmail}'),
              if (widget.notes != null && widget.notes!.trim().isNotEmpty) ...[
                pw.SizedBox(height: 6),
                pw.Text('Nota: ${widget.notes}'),
              ],
              pw.SizedBox(height: 14),
              pw.Text(
                'Declaro que recibo el equipo en condicion funcional y me hago '
                'responsable de su uso y resguardo conforme a las politicas de TI.',
              ),
              pw.SizedBox(height: 14),
              pw.Text('Firmante: ${_signerNameCtrl.text.trim()}'),
              if (_signerEmailCtrl.text.trim().isNotEmpty)
                pw.Text('Correo firmante: ${_signerEmailCtrl.text.trim()}'),
              pw.SizedBox(height: 10),
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.black),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Firma digital',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Image(signatureImage, width: 260, height: 110),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
    return Uint8List.fromList(await doc.save());
  }

  Future<String> _uploadActaPdf(Uint8List pdfBytes) async {
    final safePerson = widget.personName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final path =
        'assignment/${widget.assignmentId}/acta/${DateTime.now().microsecondsSinceEpoch}_${safePerson.isEmpty ? 'firmante' : safePerson}.pdf';

    await _client.storage.from('assignment-documents').uploadBinary(
          path,
          pdfBytes,
          fileOptions: const FileOptions(
            upsert: false,
            contentType: 'application/pdf',
          ),
        );
    return path;
  }

  Future<bool> _sendAssignmentEmail({
    required String toEmail,
    required String signerName,
    required String pdfPath,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'send-assignment-notification',
        body: {
          'assignmentId': widget.assignmentId,
          'toEmail': toEmail,
          'assetLabel': widget.assetLabel,
          'signerName': signerName,
          'assignedAt': widget.assignedAt,
          'pdfPath': pdfPath,
        },
      );
      if (response.status >= 200 && response.status < 300) {
        await _client
            .schema('sistema')
            .from('assignment_acknowledgements')
            .update({
              'email_status': 'sent',
              'email_error': null,
              'email_sent_at': DateTime.now().toIso8601String(),
            })
            .eq('assignment_id', widget.assignmentId);
        return true;
      }
      await _client
          .schema('sistema')
          .from('assignment_acknowledgements')
          .update({
            'email_status': 'error',
            'email_error': 'HTTP ${response.status}: ${response.data}',
          })
          .eq('assignment_id', widget.assignmentId);
      return false;
    } catch (e) {
      await _client
          .schema('sistema')
          .from('assignment_acknowledgements')
          .update({
            'email_status': 'error',
            'email_error': e.toString(),
          })
          .eq('assignment_id', widget.assignmentId);
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Acta y firma de entrega'),
        actions: const [ThemeToggleButton()],
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
                    'Datos de la entrega',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text('Activo: ${widget.assetLabel}'),
                  Text('Responsable: ${widget.personName}'),
                  Text('Fecha asignacion: ${_formatDateTime(widget.assignedAt)}'),
                  if (widget.institutionalEmail != null &&
                      widget.institutionalEmail!.trim().isNotEmpty)
                    Text('Correo institucional: ${widget.institutionalEmail}'),
                  if (widget.notes != null && widget.notes!.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text('Nota: ${widget.notes}'),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Confirmacion del resguardo',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Declaro que recibo el equipo en condicion funcional, me hago '
                    'responsable de su resguardo y uso conforme a las politicas de TI.',
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _signerNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nombre de quien recibe *',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _signerEmailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Correo de quien recibe (opcional)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  CheckboxListTile(
                    value: _acceptedTerms,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: _saving
                        ? null
                        : (value) {
                            setState(() => _acceptedTerms = value == true);
                          },
                    title: const Text('Acepto los terminos del resguardo del equipo'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Firma digital',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: scheme.outline.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Signature(
                      controller: _signatureCtrl,
                      height: 220,
                      backgroundColor: Colors.transparent,
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
                            : () {
                                _signatureCtrl.clear();
                                setState(() {});
                              },
                        icon: const Icon(Icons.clear),
                        label: const Text('Limpiar'),
                      ),
                      ElevatedButton.icon(
                        onPressed: _saving ? null : _saveAcknowledgement,
                        icon: const Icon(Icons.verified_outlined),
                        label: Text(_saving ? 'Guardando...' : 'Confirmar y firmar'),
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
          ],
        ),
      ),
    );
  }
}


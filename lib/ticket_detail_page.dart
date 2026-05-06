import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'app_theme.dart';
import 'ticket_service.dart';

class TicketDetailPage extends StatefulWidget {
  final String ticketId;
  const TicketDetailPage({super.key, required this.ticketId});

  @override
  State<TicketDetailPage> createState() => _TicketDetailPageState();
}

class _TicketDetailPageState extends State<TicketDetailPage> {
  TicketDetail? _detail;
  bool _loading = true;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final d = await TicketService.getTicketDetail(widget.ticketId);
      setState(() => _detail = d);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openFullScreenImage(String url) {
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (ctx) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Center(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: Image.network(url, fit: BoxFit.contain),
          ),
        ),
      ),
    ));
  }

  Future<void> _doAction(String accion) async {
    String comentario = '';

    // Para cerrar o cancelar, pedimos comentario
    if (accion == 'cerrar' || accion == 'cancelar' || accion == 'pausar') {
      final ctrl = TextEditingController();
      final label = accion == 'cerrar' ? 'Cerrar Ticket'
          : accion == 'cancelar' ? 'Cancelar Ticket'
          : 'Pausar Ticket';
      final hint = accion == 'cerrar'
          ? '¿Confirmas que el problema fue resuelto? Agrega un comentario de cierre.'
          : accion == 'cancelar'
              ? '¿Por qué se cancela este ticket?'
              : '¿Por qué se pausa este ticket? (opcional)';
      final fieldLabel = accion == 'cerrar' ? 'Comentario de cierre'
          : accion == 'cancelar' ? 'Razón de cancelación'
          : 'Motivo de pausa (opcional)';
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(label),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(hint),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: fieldLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: accion == 'cancelar'
                  ? FilledButton.styleFrom(backgroundColor: Colors.red)
                  : accion == 'pausar'
                      ? FilledButton.styleFrom(backgroundColor: Colors.orange)
                      : null,
              child: Text(label),
            ),
          ],
        ),
      );
      if (ok != true) return;
      comentario = ctrl.text.trim();
    } else {
      // Reanudar: confirmación simple
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Reanudar Ticket'),
          content: const Text('¿Confirmas que deseas reanudar este ticket? Pasará a estado "En proceso".'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reanudar')),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() => _saving = true);
    try {
      await TicketService.updateTicketStatus(
        ticketId: widget.ticketId,
        accion: accion,
        comentario: comentario,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              accion == 'cerrar' ? '✅ Ticket cerrado correctamente'
              : accion == 'cancelar' ? '🚫 Ticket cancelado'
              : '▶️ Ticket reanudado',
            ),
            backgroundColor: accion == 'cerrar' ? Colors.green : accion == 'cancelar' ? Colors.red : Colors.blue,
          ),
        );
        await _load(); // Refrescar detalle
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    try { return DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(raw).toLocal()); }
    catch (_) { return raw; }
  }

  Color _prioridadColor(String p) {
    switch (p) {
      case 'Crítica': return const Color(0xFFD32F2F);
      case 'Alta':    return const Color(0xFFE64A19);
      case 'Media':   return const Color(0xFFF57F17);
      default:        return const Color(0xFF388E3C);
    }
  }

  Color _estadoColor(String e) {
    switch (e) {
      case 'Abierto':    return const Color(0xFF1565C0);
      case 'En proceso': return const Color(0xFF6A1B9A);
      case 'En Pausa':   return const Color(0xFFF57F17);
      case 'Cerrado':    return const Color(0xFF2E7D32);
      case 'Cancelado':  return const Color(0xFF616161);
      default:           return Colors.grey;
    }
  }

  String _formatTiempo(int? seg) {
    if (seg == null) return '—';
    if (seg <= 0) return 'Vencido';
    final h = seg ~/ 3600;
    final d = h ~/ 24;
    if (d >= 1) return '$d días, ${h % 24} horas';
    return '$h h ${(seg % 3600) ~/ 60} min';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Detalle de Ticket')),
        body: Center(child: Text('Error: $_error')),
      );
    }

    final t = _detail!.ticket;
    final historial = _detail!.historial;
    final evaluacion = _detail!.evaluacion;
    final estado = t.estado;
    final pColor = _prioridadColor(t.prioridad);
    final eColor = _estadoColor(estado);
    final seg = t.segundosRestantes;
    Color tiempoColor = seg == null ? Colors.grey : seg <= 0 ? Colors.red : seg < 7200 ? Colors.orange : Colors.green;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.ticketId, style: const TextStyle(fontFamily: 'monospace', fontSize: 14)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          const ThemeToggleButton(),
        ],
      ),
      body: GradientBody(
        child: _saving
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Header ──
                    SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _Chip(t.prioridad, pColor),
                              const SizedBox(width: 8),
                              _Chip(estado, eColor),
                              const SizedBox(width: 8),
                              _Chip(t.tipoSolicitud, scheme.secondary),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(t.asunto, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.person_outline, size: 14, color: scheme.outline),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  '${t.nombre} · ${t.email}',
                                  style: theme.textTheme.bodySmall,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          if (t.departamento != null) ...[
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(Icons.business_outlined, size: 14, color: scheme.outline),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    t.departamento!,
                                    style: theme.textTheme.bodySmall,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const Divider(height: 24),
                          // Tiempo restante
                          Row(
                            children: [
                              Icon(Icons.timer_outlined, color: tiempoColor),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Tiempo restante', style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline)),
                                  Text(
                                    _formatTiempo(seg),
                                    style: TextStyle(fontWeight: FontWeight.bold, color: tiempoColor, fontSize: 16),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('Fecha límite', style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline)),
                                  Text(_formatDate(t.fechaLimite), style: theme.textTheme.bodySmall),
                                ],
                              ),
                            ],
                          ),
                          const Divider(height: 24),
                          _InfoRow('Creado', _formatDate(t.createdAt)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Acciones ──
                    if (!['Cerrado', 'Cancelado'].contains(estado)) ...[
                      Text('Acciones', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      SectionCard(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            if (estado == 'En Pausa') ...[
                              _ActionIconBtn(
                                icon: Icons.play_arrow_rounded,
                                color: const Color(0xFF1565C0),
                                tooltip: 'Reanudar',
                                onTap: () => _doAction('reanudar'),
                              ),
                            ] else ...[
                              _ActionIconBtn(
                                icon: Icons.check_circle_outline,
                                color: const Color(0xFF2E7D32),
                                tooltip: 'Cerrar ticket',
                                onTap: () => _doAction('cerrar'),
                              ),
                              _ActionIconBtn(
                                icon: Icons.pause_circle_outline,
                                color: Colors.orange,
                                tooltip: 'Pausar ticket',
                                onTap: () => _doAction('pausar'),
                              ),
                            ],
                            _ActionIconBtn(
                              icon: Icons.cancel_outlined,
                              color: Colors.red,
                              tooltip: 'Cancelar ticket',
                              onTap: () => _doAction('cancelar'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ── Evaluación ──
                    if (evaluacion != null) ...[
                      Text('Evaluación del Usuario', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      SectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  '${(evaluacion.promedio * 20).toStringAsFixed(0)}%',
                                  style: theme.textTheme.displaySmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: evaluacion.promedio >= 0.8 ? Colors.green : evaluacion.promedio >= 0.6 ? Colors.orange : Colors.red,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Promedio general', style: theme.textTheme.labelSmall),
                                      if (evaluacion.esAutomatica)
                                        Container(
                                          margin: const EdgeInsets.only(top: 4),
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.orange.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(999),
                                          ),
                                          child: const Text('Auto-evaluado', style: TextStyle(fontSize: 10, color: Colors.orange)),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _EvalRow('Comunicación clara', evaluacion.p1Comunicacion == 1),
                            _EvalRow('Satisfacción general', evaluacion.p2Satisfaccion == 1),
                            _EvalRow('Tiempo de respuesta', evaluacion.p3TiempoRespuesta == 1),
                            _EvalRow('Resolución completa', evaluacion.p4Resolucion == 1),
                            _EvalRow('Facilidad del proceso', evaluacion.p5Facilidad == 1),
                            if (evaluacion.comentarios != null && evaluacion.comentarios!.isNotEmpty) ...[
                              const Divider(height: 20),
                              Text('Comentarios:', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text(evaluacion.comentarios!, style: theme.textTheme.bodyMedium),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ── Adjuntos / Imágenes ──
                    if (t.imageUrls.isNotEmpty) ...[
                      Text('Archivos Adjuntos', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      SectionCard(
                        child: SizedBox(
                          height: 120,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: t.imageUrls.length,
                            separatorBuilder: (sepCtx, sepI) => const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              final url = t.imageUrls[index];
                              return GestureDetector(
                                onTap: () => _openFullScreenImage(url),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.network(
                                    url,
                                    width: 120,
                                    height: 120,
                                    fit: BoxFit.cover,
                                    errorBuilder: (errCtx, errObj, errSt) => Container(
                                      width: 120,
                                      height: 120,
                                      color: scheme.surfaceContainerHighest,
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.broken_image_outlined, color: scheme.outline),
                                          const SizedBox(height: 4),
                                          Text('Sin vista\nprevia', style: TextStyle(fontSize: 10, color: scheme.outline), textAlign: TextAlign.center),
                                        ],
                                      ),
                                    ),
                                    loadingBuilder: (_, child, progress) => progress == null
                                        ? child
                                        : Container(
                                            width: 120,
                                            height: 120,
                                            color: scheme.surfaceContainerHighest,
                                            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                          ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ── Historial ──
                    Text('Historial de Acciones', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    if (historial.isEmpty)
                      SectionCard(child: Center(child: Text('Sin historial registrado.', style: theme.textTheme.bodySmall)))
                    else
                      SectionCard(
                        child: Column(
                          children: historial.asMap().entries.map((entry) {
                            final h = entry.value;
                            final isLast = entry.key == historial.length - 1;
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Column(
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isLast ? scheme.primary : scheme.outline.withValues(alpha: 0.4),
                                      ),
                                    ),
                                    if (!isLast) Container(width: 1.5, height: 40, color: scheme.outline.withValues(alpha: 0.2)),
                                  ],
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(h.accion, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                        if (h.descripcion != null && h.descripcion!.isNotEmpty)
                                          Text(h.descripcion!, style: theme.textTheme.bodySmall),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${h.realizadoPor} · ${_formatDate(h.createdAt)}',
                                          style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 90, child: Text('$label:', style: TextStyle(color: scheme.outline, fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13))),
        ],
      ),
    );
  }
}

class _ActionIconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _ActionIconBtn({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: color.withValues(alpha: 0.12),
            shape: const CircleBorder(),
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Icon(icon, color: color, size: 28),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            tooltip,
            style: TextStyle(
              fontSize: 10,
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _EvalRow extends StatelessWidget {
  final String label;
  final bool value;
  const _EvalRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(value ? Icons.check_circle_rounded : Icons.cancel_rounded,
              size: 16, color: value ? Colors.green : Colors.red),
          const SizedBox(width: 8),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

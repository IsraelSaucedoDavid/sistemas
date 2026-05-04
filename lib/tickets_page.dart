import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'app_theme.dart';
import 'ticket_service.dart';
import 'ticket_detail_page.dart';

// ─── Filtros de tiempo ───
enum _FiltroTiempo { todos, hoy, semana, mes }

extension _FiltroLabel on _FiltroTiempo {
  String get label {
    switch (this) {
      case _FiltroTiempo.todos:  return 'Todos';
      case _FiltroTiempo.hoy:   return 'Hoy';
      case _FiltroTiempo.semana: return 'Esta semana';
      case _FiltroTiempo.mes:   return 'Este mes';
    }
  }
}

class TicketsPage extends StatefulWidget {
  const TicketsPage({super.key});

  @override
  State<TicketsPage> createState() => _TicketsPageState();
}

class _TicketsPageState extends State<TicketsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<String> _tabs       = ['Todos', 'Abierto', 'En proceso', 'En Pausa', 'Cerrado', 'Cancelado'];
  final List<String> _tabValues  = ['todos', 'Abierto', 'En proceso', 'En Pausa', 'Cerrado', 'Cancelado'];

  List<Ticket> _tickets     = [];
  bool         _loading     = false;
  String?      _error;
  bool         _ascendente  = false;                       // false = más recientes primero
  _FiltroTiempo _filtroTiempo = _FiltroTiempo.todos;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) _loadTickets();
    });
    _loadTickets();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadTickets() async {
    setState(() { _loading = true; _error = null; });
    try {
      final estado = _tabValues[_tabController.index];
      final list   = await TicketService.getTickets(estado: estado, limit: 100);
      setState(() => _tickets = list);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Aplica filtro de tiempo + orden localmente (sin nueva petición al servidor)
  List<Ticket> get _ticketsFiltrados {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    var lista = _tickets.where((t) {
      if (_filtroTiempo == _FiltroTiempo.todos) return true;
      final dt = DateTime.tryParse(t.createdAt)?.toLocal();
      if (dt == null) return false;
      switch (_filtroTiempo) {
        case _FiltroTiempo.hoy:
          return dt.isAfter(today);
        case _FiltroTiempo.semana:
          return dt.isAfter(today.subtract(const Duration(days: 7)));
        case _FiltroTiempo.mes:
          return dt.isAfter(DateTime(now.year, now.month, 1));
        default:
          return true;
      }
    }).toList();

    // Ordenar por created_at
    lista.sort((a, b) {
      final dtA = DateTime.tryParse(a.createdAt) ?? DateTime(2000);
      final dtB = DateTime.tryParse(b.createdAt) ?? DateTime(2000);
      return _ascendente ? dtA.compareTo(dtB) : dtB.compareTo(dtA);
    });

    return lista;
  }

  // ─── Colores ───
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

  String _formatTiempoRestante(int? segundos) {
    if (segundos == null) return '—';
    if (segundos <= 0) return 'Vencido';
    final h = segundos ~/ 3600;
    final d = h ~/ 24;
    if (d >= 1) return '$d d ${h % 24} h';
    return '${h} h ${(segundos % 3600) ~/ 60} min';
  }

  Color _tiempoColor(int? segundos) {
    if (segundos == null) return Colors.grey;
    if (segundos <= 0) return Colors.red;
    final h = segundos ~/ 3600;
    if (h <= 2) return Colors.red;
    if (h <= 24) return Colors.orange;
    return Colors.green;
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    try {
      return DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(raw).toLocal());
    } catch (_) { return raw; }
  }

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final scheme = theme.colorScheme;
    final filtrados = _ticketsFiltrados;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tickets de Soporte'),
        actions: [
          // Botón de orden
          Tooltip(
            message: _ascendente ? 'Más recientes primero' : 'Más antiguos primero',
            child: IconButton(
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Icon(
                  _ascendente ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                  key: ValueKey(_ascendente),
                ),
              ),
              onPressed: () => setState(() => _ascendente = !_ascendente),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _loadTickets,
          ),
          const ThemeToggleButton(),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: _tabs.map((t) => Tab(text: t)).toList(),
        ),
      ),
      body: GradientBody(
        child: Column(
          children: [
            // ── Filtros de tiempo ──
            _FiltroTiempoBar(
              seleccionado: _filtroTiempo,
              onChanged: (f) => setState(() => _filtroTiempo = f),
            ),
            // ── Contador ──
            if (!_loading && _error == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Row(
                  children: [
                    Text(
                      '${filtrados.length} ticket${filtrados.length != 1 ? "s" : ""}',
                      style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
                    ),
                    const Spacer(),
                    Text(
                      _ascendente ? '↑ Más antiguos primero' : '↓ Más recientes primero',
                      style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
                    ),
                  ],
                ),
              ),
            // ── Lista ──
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.cloud_off_rounded, size: 64, color: scheme.error),
                                const SizedBox(height: 16),
                                Text('Error al cargar tickets', style: theme.textTheme.titleMedium),
                                const SizedBox(height: 8),
                                Text(_error!, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
                                const SizedBox(height: 24),
                                FilledButton.icon(onPressed: _loadTickets, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
                              ],
                            ),
                          ),
                        )
                      : filtrados.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.inbox_rounded, size: 64, color: scheme.outline),
                                  const SizedBox(height: 12),
                                  Text('Sin tickets para este filtro', style: theme.textTheme.bodyLarge?.copyWith(color: scheme.outline)),
                                ],
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _loadTickets,
                              child: ListView.builder(
                                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                                itemCount: filtrados.length,
                                itemBuilder: (context, index) {
                                  final t = filtrados[index];
                                  return _TicketCard(
                                    ticket: t,
                                    prioridadColor: _prioridadColor(t.prioridad),
                                    estadoColor: _estadoColor(t.estado),
                                    tiempoRestante: _formatTiempoRestante(t.segundosRestantes),
                                    tiempoColor: _tiempoColor(t.segundosRestantes),
                                    fechaCreacion: _formatDate(t.createdAt),
                                    onTap: () async {
                                      await Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => TicketDetailPage(ticketId: t.ticketId),
                                        ),
                                      );
                                      _loadTickets();
                                    },
                                  );
                                },
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Barra de filtros de tiempo ───
class _FiltroTiempoBar extends StatelessWidget {
  final _FiltroTiempo seleccionado;
  final ValueChanged<_FiltroTiempo> onChanged;

  const _FiltroTiempoBar({required this.seleccionado, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: _FiltroTiempo.values.map((f) {
          final active = f == seleccionado;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: () => onChanged(f),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: active ? scheme.primary : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: active ? scheme.primary : scheme.outlineVariant,
                  ),
                ),
                child: Text(
                  f.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: active ? FontWeight.bold : FontWeight.normal,
                    color: active ? scheme.onPrimary : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Tarjeta de ticket ───
class _TicketCard extends StatelessWidget {
  final Ticket ticket;
  final Color prioridadColor;
  final Color estadoColor;
  final String tiempoRestante;
  final Color tiempoColor;
  final String fechaCreacion;
  final VoidCallback onTap;

  const _TicketCard({
    required this.ticket,
    required this.prioridadColor,
    required this.estadoColor,
    required this.tiempoRestante,
    required this.tiempoColor,
    required this.fechaCreacion,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SectionCard(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 40,
                    decoration: BoxDecoration(
                      color: prioridadColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ticket.ticketId,
                          style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
                        ),
                        Text(
                          ticket.asunto,
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _Chip(label: ticket.estado, color: estadoColor),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.person_outline, size: 14, color: theme.colorScheme.outline),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${ticket.nombre}${ticket.departamento != null ? " · ${ticket.departamento}" : ""}',
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _Chip(label: ticket.prioridad, color: prioridadColor, small: true),
                  const SizedBox(width: 6),
                  _Chip(label: ticket.tipoSolicitud, color: theme.colorScheme.secondary, small: true),
                  const Spacer(),
                  Icon(Icons.timer_outlined, size: 13, color: tiempoColor),
                  const SizedBox(width: 3),
                  Text(
                    tiempoRestante,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: tiempoColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Creado: $fechaCreacion',
                style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
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
  final bool small;

  const _Chip({required this.label, required this.color, this.small = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 7 : 10, vertical: small ? 3 : 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: small ? 10 : 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

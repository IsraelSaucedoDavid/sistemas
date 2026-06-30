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
      case _FiltroTiempo.todos:
        return 'Cualquier fecha';
      case _FiltroTiempo.hoy:
        return 'Hoy';
      case _FiltroTiempo.semana:
        return 'Esta semana';
      case _FiltroTiempo.mes:
        return 'Este mes';
    }
  }
}

// ─── Modelo de Estado de Filtros ───
class _TicketFilter {
  String searchQuery = '';
  List<String> estados = [];
  List<String> prioridades = [];
  List<String> urgencias = [];
  _FiltroTiempo tiempo = _FiltroTiempo.todos;

  bool get isActive =>
      searchQuery.isNotEmpty ||
      estados.isNotEmpty ||
      prioridades.isNotEmpty ||
      urgencias.isNotEmpty ||
      tiempo != _FiltroTiempo.todos;

  void clear() {
    searchQuery = '';
    estados.clear();
    prioridades.clear();
    urgencias.clear();
    tiempo = _FiltroTiempo.todos;
  }
}

class TicketsPage extends StatefulWidget {
  const TicketsPage({super.key});

  @override
  State<TicketsPage> createState() => _TicketsPageState();
}

class _TicketsPageState extends State<TicketsPage> {
  List<Ticket> _tickets = [];
  bool _loading = false;
  String? _error;
  bool _ascendente = false; // false = más recientes primero

  final _TicketFilter _filter = _TicketFilter();
  final TextEditingController _searchController = TextEditingController();

  final List<String> _todosLosEstados = [
    'Abierto',
    'En proceso',
    'En Pausa',
    'Cerrado',
    'Cancelado',
  ];
  final List<String> _todasLasPrioridades = [
    'Baja',
    'Media',
    'Alta',
    'Crítica',
  ];
  final List<String> _todasLasUrgencias = [
    'Vencidos',
    'Por Vencer',
    'A tiempo',
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadTickets();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _filter.searchQuery = _searchController.text.trim().toLowerCase();
    });
  }

  Future<void> _loadTickets() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Cargamos un lote de tickets para filtrarlos localmente
      final list = await TicketService.getTickets(
        estado: 'todos',
        limit: 500, // Limite amplio para busquedas locales
      );
      setState(() {
        _tickets = list;
        debugPrint('TicketsPage: _tickets cargados base (${list.length})');
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Ticket> get _ticketsFiltrados {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    var lista = _tickets.where((t) {
      // 1. Búsqueda por texto
      if (_filter.searchQuery.isNotEmpty) {
        final query = _filter.searchQuery;
        final matchId = t.ticketId.toLowerCase().contains(query);
        final matchAsunto = t.asunto.toLowerCase().contains(query);
        final matchNombre = t.nombre.toLowerCase().contains(query);
        if (!matchId && !matchAsunto && !matchNombre) return false;
      }

      // 2. Estados múltiples
      if (_filter.estados.isNotEmpty && !_filter.estados.contains(t.estado)) {
        return false;
      }

      // 3. Prioridades múltiples
      if (_filter.prioridades.isNotEmpty &&
          !_filter.prioridades.contains(t.prioridad)) {
        return false;
      }

      // 4. Urgencia (SLA)
      if (_filter.urgencias.isNotEmpty) {
        final secs = t.segundosRestantes ?? 0;
        final hours = secs / 3600.0;

        bool match = false;
        if (_filter.urgencias.contains('Vencidos') && secs <= 0) match = true;
        if (_filter.urgencias.contains('Por Vencer') && secs > 0 && hours <= 2) {
          match = true;
        }
        if (_filter.urgencias.contains('A tiempo') && hours > 2) match = true;

        if (!match) return false;
      }

      // 5. Filtro de Tiempo
      if (_filter.tiempo != _FiltroTiempo.todos) {
        final dt = DateTime.tryParse(t.createdAt)?.toLocal();
        if (dt == null) return false;

        switch (_filter.tiempo) {
          case _FiltroTiempo.hoy:
            if (!(dt.year == today.year &&
                dt.month == today.month &&
                dt.day == today.day)) {
              return false;
            }
            break;
          case _FiltroTiempo.semana:
            if (!dt.isAfter(today.subtract(const Duration(days: 7)))) {
              return false;
            }
            break;
          case _FiltroTiempo.mes:
            if (!(dt.year == now.year && dt.month == now.month)) return false;
            break;
          default:
            break;
        }
      }

      return true;
    }).toList();

    // Ordenar
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
      case 'Crítica':
        return const Color(0xFFD32F2F);
      case 'Alta':
        return const Color(0xFFE64A19);
      case 'Media':
        return const Color(0xFFF57F17);
      default:
        return const Color(0xFF388E3C);
    }
  }

  Color _estadoColor(String e) {
    switch (e) {
      case 'Abierto':
        return const Color(0xFF1565C0);
      case 'En proceso':
        return const Color(0xFF6A1B9A);
      case 'En Pausa':
        return const Color(0xFFF57F17);
      case 'Cerrado':
        return const Color(0xFF2E7D32);
      case 'Cancelado':
        return const Color(0xFF616161);
      default:
        return Colors.grey;
    }
  }

  String _formatTiempoRestante(int? segundos) {
    if (segundos == null) return '—';
    if (segundos <= 0) return 'Vencido';
    final h = segundos ~/ 3600;
    final d = h ~/ 24;
    if (d >= 1) return '$d d ${h % 24} h';
    return '$h h ${(segundos % 3600) ~/ 60} min';
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
      return DateFormat(
        'dd/MM/yyyy HH:mm',
      ).format(DateTime.parse(raw).toLocal());
    } catch (_) {
      return raw;
    }
  }

  void _abrirPanelFiltros() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final theme = Theme.of(context);
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.9,
              maxChildSize: 0.9,
              builder: (_, controller) {
                return Column(
                  children: [
                    // Header del bottom sheet
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(Icons.filter_list_rounded),
                          const SizedBox(width: 8),
                          Text(
                            'Filtros Avanzados',
                            style: theme.textTheme.titleLarge,
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              setModalState(() => _filter.clear());
                              setState(() {}); // Update main page
                            },
                            child: const Text('Limpiar'),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView(
                        controller: controller,
                        padding: const EdgeInsets.all(16),
                        children: [
                          // Sección: Estados
                          Text(
                            'Estados',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _todosLosEstados.map((estado) {
                              final isSelected = _filter.estados.contains(
                                estado,
                              );
                              return FilterChip(
                                label: Text(estado),
                                selected: isSelected,
                                onSelected: (selected) {
                                  setModalState(() {
                                    if (selected) {
                                      _filter.estados.add(estado);
                                    } else {
                                      _filter.estados.remove(estado);
                                    }
                                  });
                                  setState(() {});
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 24),

                          // Sección: Prioridad
                          Text(
                            'Prioridad',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _todasLasPrioridades.map((prioridad) {
                              final isSelected = _filter.prioridades.contains(
                                prioridad,
                              );
                              return FilterChip(
                                label: Text(prioridad),
                                selected: isSelected,
                                selectedColor: _prioridadColor(
                                  prioridad,
                                ).withValues(alpha: 0.2),
                                checkmarkColor: _prioridadColor(prioridad),
                                onSelected: (selected) {
                                  setModalState(() {
                                    if (selected) {
                                      _filter.prioridades.add(prioridad);
                                    } else {
                                      _filter.prioridades.remove(prioridad);
                                    }
                                  });
                                  setState(() {});
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 24),

                          // Sección: Urgencia / SLA
                          Text(
                            'Urgencia (SLA)',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _todasLasUrgencias.map((urgencia) {
                              final isSelected = _filter.urgencias.contains(
                                urgencia,
                              );
                              return FilterChip(
                                label: Text(urgencia),
                                selected: isSelected,
                                onSelected: (selected) {
                                  setModalState(() {
                                    if (selected) {
                                      _filter.urgencias.add(urgencia);
                                    } else {
                                      _filter.urgencias.remove(urgencia);
                                    }
                                  });
                                  setState(() {});
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 24),

                          // Sección: Tiempo
                          Text(
                            'Fecha de Creación',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _FiltroTiempo.values.map((f) {
                              final isSelected = _filter.tiempo == f;
                              return ChoiceChip(
                                label: Text(f.label),
                                selected: isSelected,
                                onSelected: (selected) {
                                  if (selected) {
                                    setModalState(() => _filter.tiempo = f);
                                    setState(() {});
                                  }
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                    // Botón inferior
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Ver Resultados'),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildActiveFiltersChips() {
    List<Widget> chips = [];

    for (var estado in _filter.estados) {
      chips.add(
        InputChip(
          label: Text(estado, style: const TextStyle(fontSize: 12)),
          onDeleted: () => setState(() => _filter.estados.remove(estado)),
        ),
      );
    }
    for (var prio in _filter.prioridades) {
      chips.add(
        InputChip(
          label: Text(prio, style: const TextStyle(fontSize: 12)),
          onDeleted: () => setState(() => _filter.prioridades.remove(prio)),
        ),
      );
    }
    for (var urg in _filter.urgencias) {
      chips.add(
        InputChip(
          label: Text(urg, style: const TextStyle(fontSize: 12)),
          onDeleted: () => setState(() => _filter.urgencias.remove(urg)),
        ),
      );
    }
    if (_filter.tiempo != _FiltroTiempo.todos) {
      chips.add(
        InputChip(
          label: Text(
            _filter.tiempo.label,
            style: const TextStyle(fontSize: 12),
          ),
          onDeleted: () => setState(() => _filter.tiempo = _FiltroTiempo.todos),
        ),
      );
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, index) => chips[index],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final filtrados = _ticketsFiltrados;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tickets de Soporte'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _loadTickets,
          ),
          const ThemeToggleButton(),
        ],
      ),
      body: GradientBody(
        child: Column(
          children: [
            // ── Barra de Búsqueda y Botón Filtros ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Buscar ticket, asunto o usuario...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 20),
                                onPressed: () {
                                  _searchController.clear();
                                  FocusScope.of(context).unfocus();
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 0,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(999),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: scheme.surfaceContainerHighest.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: _filter.isActive
                          ? scheme.primaryContainer
                          : scheme.surfaceContainerHighest.withValues(
                              alpha: 0.5,
                            ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: IconButton(
                      icon: Icon(
                        Icons.tune_rounded,
                        color: _filter.isActive
                            ? scheme.onPrimaryContainer
                            : scheme.onSurfaceVariant,
                      ),
                      onPressed: _abrirPanelFiltros,
                      tooltip: 'Filtros Avanzados',
                    ),
                  ),
                ],
              ),
            ),

            // ── Chips de Filtros Activos ──
            _buildActiveFiltersChips(),
            if (_filter.isActive) const SizedBox(height: 8),

            // ── Contador y Orden ──
            if (!_loading && _error == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Row(
                  children: [
                    Text(
                      '${filtrados.length} ticket${filtrados.length != 1 ? "s" : ""}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.outline,
                      ),
                    ),
                    const Spacer(),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(() => _ascendente = !_ascendente),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Row(
                          children: [
                            Text(
                              _ascendente ? 'Más antiguos' : 'Más recientes',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.primary,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              _ascendente
                                  ? Icons.arrow_upward_rounded
                                  : Icons.arrow_downward_rounded,
                              size: 14,
                              color: scheme.primary,
                            ),
                          ],
                        ),
                      ),
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
                            Icon(
                              Icons.cloud_off_rounded,
                              size: 64,
                              color: scheme.error,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Error al cargar tickets',
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _error!,
                              style: theme.textTheme.bodySmall,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            FilledButton.icon(
                              onPressed: _loadTickets,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Reintentar'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : filtrados.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.inbox_rounded,
                            size: 64,
                            color: scheme.outline,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No se encontraron tickets',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: scheme.outline,
                            ),
                          ),
                          if (_filter.isActive) ...[
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () => setState(() {
                                _filter.clear();
                                _searchController.clear();
                              }),
                              child: const Text('Limpiar filtros'),
                            ),
                          ],
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
                            tiempoRestante: _formatTiempoRestante(
                              t.segundosRestantes,
                            ),
                            tiempoColor: _tiempoColor(t.segundosRestantes),
                            fechaCreacion: _formatDate(t.createdAt),
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      TicketDetailPage(ticketId: t.ticketId),
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
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                        Text(
                          ticket.asunto,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
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
                  Icon(
                    Icons.person_outline,
                    size: 14,
                    color: theme.colorScheme.outline,
                  ),
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
                  _Chip(
                    label: ticket.prioridad,
                    color: prioridadColor,
                    small: true,
                  ),
                  const SizedBox(width: 6),
                  _Chip(
                    label: ticket.tipoSolicitud,
                    color: theme.colorScheme.secondary,
                    small: true,
                  ),
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
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
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
  final bool small;

  const _Chip({required this.label, required this.color, this.small = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 7 : 10,
        vertical: small ? 3 : 4,
      ),
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

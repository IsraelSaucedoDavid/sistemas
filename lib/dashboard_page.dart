import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'account_settings_page.dart';
import 'assignments_page.dart';
import 'app_theme.dart';
import 'assets_page.dart';
import 'login_page.dart';
import 'maintenance_page.dart';
import 'maintenance_calendar_page.dart';
import 'tickets_page.dart';
import 'ticket_service.dart';
import 'notifications_page.dart';
import 'notification_service.dart';
import 'dart:async';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool _loading = false;
  late _DashboardStats _stats;
  StreamSubscription? _notifSubscription;

  @override
  void initState() {
    super.initState();
    _stats = _DashboardStats.empty();
    _loadStats();
    
    // Escuchar notificaciones para refrescar el Dashboard automáticamente
    _notifSubscription = NotificationService().onNotificationReceived.listen((_) {
      debugPrint('Dashboard: Refrescando por nueva notificación...');
      _loadStats();
    });
  }

  @override
  void dispose() {
    _notifSubscription?.cancel();
    super.dispose();
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  Future<void> _loadStats() async {
    final client = Supabase.instance.client;
    setState(() => _loading = true);
    try {
      final assetsRows = await client
          .schema('sistema')
          .from('assets')
          .select('id, status');
      final maintRows = await client
          .schema('sistema')
          .from('maintenance_events')
          .select('id, status, next_due_date');
      final docsRows = await client
          .schema('sistema')
          .from('asset_documents')
          .select('id');

      final assets = assetsRows as List<dynamic>;
      final maints = maintRows as List<dynamic>;
      final docs = docsRows as List<dynamic>;

      int funcionando = 0,
          libre = 0,
          asignado = 0,
          mantenimiento = 0,
          descompuesto = 0,
          baja = 0;
      for (final row in assets) {
        final s = (row as Map<String, dynamic>)['status']?.toString() ?? '';
        if (s == 'funcionando' || s == 'activo') funcionando++;
        if (s == 'libre') libre++;
        if (s == 'asignado') asignado++;
        if (s == 'mantenimiento') mantenimiento++;
        if (s == 'descompuesto') descompuesto++;
        if (s == 'baja') baja++;
      }

      int pend = 0, enProceso = 0, concl = 0, vencido = 0, porVencer = 0;
      final today = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
      );
      for (final row in maints) {
        final map = row as Map<String, dynamic>;
        final s = map['status']?.toString() ?? 'pendiente';
        if (s == 'pendiente') pend++;
        if (s == 'en_proceso') enProceso++;
        if (s == 'concluido') concl++;
        if (s != 'concluido') {
          final due = DateTime.tryParse(map['next_due_date']?.toString() ?? '');
          if (due != null) {
            final days = DateTime(
              due.year,
              due.month,
              due.day,
            ).difference(today).inDays;
            if (days < 0) {
              vencido++;
            } else if (days <= 2) {
              porVencer++;
            }
          }
        }
      }

      // ── Tickets (API externa) ──
      int tkTotal = 0, tkAbiertos = 0, tkEnProceso = 0, tkPausa = 0;
      int tkCerrados = 0, tkCancelados = 0, tkCriticos = 0, tkVencidos = 0;
      try {
        final tickets = await TicketService.getTickets(
          estado: 'todos',
          limit: 200,
        );
        tkTotal = tickets.length;
        for (final t in tickets) {
          if (t.estado == 'Abierto') tkAbiertos++;
          if (t.estado == 'En proceso') tkEnProceso++;
          if (t.estado == 'En Pausa') tkPausa++;
          if (t.estado == 'Cerrado') tkCerrados++;
          if (t.estado == 'Cancelado') tkCancelados++;

          // Solo contar como crítico si NO está Cerrado ni Cancelado
          if (t.prioridad == 'Crítica' &&
              !['Cerrado', 'Cancelado'].contains(t.estado)) {
            tkCriticos++;
          }

          if (t.segundosRestantes != null &&
              t.segundosRestantes! <= 0 &&
              !['Cerrado', 'Cancelado'].contains(t.estado)) {
            tkVencidos++;
          }
        }
      } catch (e) {
        debugPrint('Tickets load error: $e');
      }

      // ── Notificaciones (Unread count) ──
      int unreadCount = 0;
      try {
        final unreadRes = await client
            .from('notifications')
            .select('id')
            .eq('is_read', false);
        unreadCount = (unreadRes as List).length;
        debugPrint('--- NOTIFICACIONES NO LEÍDAS: $unreadCount ---');
      } catch (e) {
        debugPrint('Error en conteo de notificaciones: $e');
        debugPrint('*** ASEGÚRATE DE HABER AGREGADO LA COLUMNA is_read EN SUPABASE ***');
      }

      setState(() {
        _stats = _DashboardStats(
          totalAssets: assets.length,
          assetsFuncionando: funcionando,
          assetsLibre: libre,
          assetsAsignado: asignado,
          assetsMantenimiento: mantenimiento,
          assetsDescompuesto: descompuesto,
          assetsBaja: baja,
          totalMantenimientos: maints.length,
          mtPendientes: pend,
          mtEnProceso: enProceso,
          mtConcluidos: concl,
          mtVencidos: vencido,
          mtPorVencer: porVencer,
          totalFotos: docs.length,
          tkTotal: tkTotal,
          tkAbiertos: tkAbiertos,
          tkEnProceso: tkEnProceso,
          tkPausa: tkPausa,
          tkCerrados: tkCerrados,
          tkCancelados: tkCancelados,
          tkCriticos: tkCriticos,
          tkVencidos: tkVencidos,
          unreadNotifications: unreadCount,
        );
      });
    } catch (e) {
      debugPrint('Dashboard error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _navigate(Widget page) {
    Navigator.of(context).pop();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : scheme.surface,
      appBar: AppBar(
        backgroundColor: isDark ? AppColors.darkBg : scheme.surface,
        title: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppColors.amber,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Dashboard TI',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
          ],
        ),
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const NotificationsPage()),
                  );
                  _loadStats(); // Recargar al volver para limpiar el contador
                },
              ),
              if (_stats.unreadNotifications > 0)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: AppColors.red,
                      shape: BoxShape.circle,
                      border: Border.all(color: isDark ? AppColors.darkBg : Colors.white, width: 1.5),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    child: Center(
                      child: Text(
                        '${_stats.unreadNotifications}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const ThemeToggleButton(),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadStats,
          ),
        ],
      ),
      drawer: _buildDrawer(context),
      body: _loading && _stats.totalAssets == 0
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.amber),
            )
          : RefreshIndicator(
              color: AppColors.amber,
              onRefresh: _loadStats,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  _buildHeader(email, scheme, isDark),
                  const SizedBox(height: 16),
                  _buildAlertBanner(isDark),
                  const SizedBox(height: 16),
                  _buildSectionTitle('Inventario de Activos'),
                  const SizedBox(height: 10),
                  _buildAssetGrid(isDark),
                  const SizedBox(height: 20),
                  _buildSectionTitle('Mantenimientos'),
                  const SizedBox(height: 10),
                  _buildMaintenanceRow(isDark),
                  const SizedBox(height: 20),
                  _buildSectionTitle('Tickets de Soporte'),
                  const SizedBox(height: 10),
                  _buildTicketsSection(isDark),
                  const SizedBox(height: 20),
                  _buildSectionTitle('Accesos Rápidos'),
                  const SizedBox(height: 10),
                  _buildQuickAccess(context),
                  const SizedBox(height: 20),
                  _buildBottomStats(isDark),
                ],
              ),
            ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Drawer(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? AppColors.darkCard
          : scheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.darkBg, Color(0xFF1C1F28)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.amber.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.amber.withValues(alpha: 0.4),
                      ),
                    ),
                    child: const Icon(
                      Icons.person_outline,
                      color: AppColors.amber,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Sistema TI',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    Supabase.instance.client.auth.currentUser?.email ?? '',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _drawerItem(
              Icons.dashboard_outlined,
              'Dashboard',
              () => Navigator.of(context).pop(),
            ),
            _drawerItem(
              Icons.inventory_2_outlined,
              'Activos',
              () => _navigate(const AssetsPage()),
            ),
            _drawerItem(
              Icons.assignment_ind_outlined,
              'Asignaciones',
              () => _navigate(const AssignmentsPage()),
            ),
            _drawerItem(
              Icons.build_circle_outlined,
              'Mantenimientos',
              () => _navigate(const MaintenancePage()),
            ),
            _drawerItem(
              Icons.confirmation_number_outlined,
              'Tickets',
              () => _navigate(const TicketsPage()),
            ),
            _drawerItem(
              Icons.calendar_month_outlined,
              'Calendario',
              () => _navigate(const MaintenanceCalendarPage()),
            ),
            _drawerItem(
              Icons.settings_outlined,
              'Mi Cuenta',
              () => _navigate(const AccountSettingsPage()),
            ),
            const Spacer(),
            const Divider(),
            _drawerItem(
              Icons.logout,
              'Cerrar Sesión',
              _signOut,
              color: AppColors.red,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _drawerItem(
    IconData icon,
    String title,
    VoidCallback onTap, {
    Color? color,
  }) {
    return ListTile(
      leading: Icon(icon, color: color ?? AppColors.amber, size: 22),
      title: Text(
        title,
        style: TextStyle(color: color, fontWeight: FontWeight.w500),
      ),
      onTap: onTap,
      dense: true,
    );
  }

  Widget _buildHeader(String email, ColorScheme scheme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF1C1F28), Color(0xFF242836)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [AppColors.amber, AppColors.amberGlow],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.amber.withValues(alpha: 0.4),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(Icons.person, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Bienvenido',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                Text(
                  email,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: AppColors.green.withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Text(
                    '● Activo',
                    style: TextStyle(
                      color: AppColors.green,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_loading)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.amber,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAlertBanner(bool isDark) {
    final alerts = [
      if (_stats.tkCriticos > 0) '🔴 ${_stats.tkCriticos} tickets críticos',
      if (_stats.tkVencidos > 0) '⏰ ${_stats.tkVencidos} tickets vencidos',
      if (_stats.mtVencidos > 0) '🔧 ${_stats.mtVencidos} mant. vencidos',
      if (_stats.assetsDescompuesto > 0)
        '💥 ${_stats.assetsDescompuesto} activos descompuestos',
      if (_stats.mtPorVencer > 0) '⚠️ ${_stats.mtPorVencer} mant. por vencer',
    ];
    if (alerts.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: AppColors.red.withValues(alpha: 0.1),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: AppColors.red,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              alerts.join('  '),
              style: const TextStyle(
                color: AppColors.red,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTicketsSection(bool isDark) {
    final total = _stats.tkTotal;
    final cerrados = _stats.tkCerrados;
    final cancelados = _stats.tkCancelados;
    final finalizados = cerrados + cancelados;
    final pct = total > 0 ? finalizados / total : 0.0;
    final activos = _stats.tkAbiertos + _stats.tkEnProceso + _stats.tkPausa;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _BigStatCard(
                label: 'Total Tickets',
                value: total.toString(),
                icon: Icons.confirmation_number_outlined,
                color: AppColors.blue,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _BigStatCard(
                label: 'Activos',
                value: activos.toString(),
                icon: Icons.pending_outlined,
                color: AppColors.amber,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _SmallStatCard(
                label: 'Abiertos',
                value: _stats.tkAbiertos.toString(),
                color: AppColors.blue,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SmallStatCard(
                label: 'En Proceso',
                value: _stats.tkEnProceso.toString(),
                color: AppColors.purple,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SmallStatCard(
                label: 'En Pausa',
                value: _stats.tkPausa.toString(),
                color: Colors.orange,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SmallStatCard(
                label: 'Cerrados',
                value: _stats.tkCerrados.toString(),
                color: AppColors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _SmallStatCard(
                label: 'Críticos',
                value: _stats.tkCriticos.toString(),
                color: AppColors.red,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SmallStatCard(
                label: 'Vencidos',
                value: _stats.tkVencidos.toString(),
                color: Colors.redAccent,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SmallStatCard(
                label: 'Cancelados',
                value: _stats.tkCancelados.toString(),
                color: Colors.grey,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SmallStatCard(
                label: 'SLA OK',
                value: total > 0
                    ? '${((finalizados / total) * 100).toInt()}%'
                    : '—',
                color: AppColors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (total > 0)
          _GaugeCard(
            label: 'Resolución de Tickets',
            value: pct.clamp(0.0, 1.0),
            color: AppColors.blue,
            subtitle: '$finalizados de $total tickets finalizados',
          ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: AppColors.amber,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ],
    );
  }

  Widget _buildAssetGrid(bool isDark) {
    final total = _stats.totalAssets;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _BigStatCard(
                label: 'Total Activos',
                value: total.toString(),
                icon: Icons.devices_outlined,
                color: AppColors.amber,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _BigStatCard(
                label: 'Funcionando',
                value: _stats.assetsFuncionando.toString(),
                icon: Icons.check_circle_outline,
                color: AppColors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _SmallStatCard(
                label: 'Libres',
                value: _stats.assetsLibre.toString(),
                color: AppColors.blue,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SmallStatCard(
                label: 'Asignados',
                value: _stats.assetsAsignado.toString(),
                color: AppColors.purple,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SmallStatCard(
                label: 'Mant.',
                value: _stats.assetsMantenimiento.toString(),
                color: AppColors.amberGlow,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SmallStatCard(
                label: 'Baja',
                value: _stats.assetsBaja.toString(),
                color: Colors.grey,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (total > 0)
          _GaugeCard(
            label: 'Operatividad',
            value:
                ((_stats.assetsFuncionando +
                            _stats.assetsLibre +
                            _stats.assetsAsignado) /
                        total)
                    .clamp(0.0, 1.0),
            color: AppColors.amber,
            subtitle:
                '${_stats.assetsFuncionando + _stats.assetsLibre + _stats.assetsAsignado} de $total activos operativos',
          ),
      ],
    );
  }

  Widget _buildMaintenanceRow(bool isDark) {
    final total = _stats.totalMantenimientos;
    final pct = total > 0 ? _stats.mtConcluidos / total : 0.0;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _BigStatCard(
                label: 'Total Servicios',
                value: total.toString(),
                icon: Icons.build_outlined,
                color: AppColors.purple,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _BigStatCard(
                label: 'Concluidos',
                value: _stats.mtConcluidos.toString(),
                icon: Icons.task_alt_outlined,
                color: AppColors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _SmallStatCard(
                label: 'Pendiente',
                value: _stats.mtPendientes.toString(),
                color: AppColors.amber,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SmallStatCard(
                label: 'En Proceso',
                value: _stats.mtEnProceso.toString(),
                color: AppColors.blue,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SmallStatCard(
                label: 'Vencidos',
                value: _stats.mtVencidos.toString(),
                color: AppColors.red,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SmallStatCard(
                label: 'Por Vencer',
                value: _stats.mtPorVencer.toString(),
                color: Colors.orange,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (total > 0)
          _GaugeCard(
            label: 'Progreso Total',
            value: pct.clamp(0.0, 1.0),
            color: AppColors.green,
            subtitle: '${_stats.mtConcluidos} de $total servicios concluidos',
          ),
      ],
    );
  }

  Widget _buildQuickAccess(BuildContext context) {
    final items = [
      _QA(
        'Activos',
        Icons.devices_outlined,
        AppColors.amber,
        const AssetsPage(),
      ),
      _QA(
        'Asignaciones',
        Icons.assignment_ind_outlined,
        AppColors.blue,
        const AssignmentsPage(),
      ),
      _QA(
        'Mantenimiento',
        Icons.build_circle_outlined,
        AppColors.purple,
        const MaintenancePage(),
      ),
      _QA(
        'Tickets',
        Icons.confirmation_number_outlined,
        AppColors.green,
        const TicketsPage(),
      ),
      _QA(
        'Calendario',
        Icons.calendar_month_outlined,
        Colors.orange,
        const MaintenanceCalendarPage(),
      ),
    ];
    return SizedBox(
      height: 90,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, i) => const SizedBox(width: 10),
        itemBuilder: (ctx, i) {
          final q = items[i];
          return GestureDetector(
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => q.page)),
            child: Container(
              width: 80,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: q.color.withValues(alpha: 0.1),
                border: Border.all(color: q.color.withValues(alpha: 0.3)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(q.icon, color: q.color, size: 26),
                  const SizedBox(height: 6),
                  Text(
                    q.label,
                    style: TextStyle(
                      fontSize: 10,
                      color: q.color,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottomStats(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color(0xFF1C1F28),
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _BottomStat(
            value: _stats.totalFotos.toString(),
            label: 'Evidencias',
            icon: Icons.photo_library_outlined,
            color: AppColors.blue,
          ),
          _BottomStat(
            value: _stats.totalAssets.toString(),
            label: 'Activos',
            icon: Icons.devices_outlined,
            color: AppColors.amber,
          ),
          _BottomStat(
            value: _stats.totalMantenimientos.toString(),
            label: 'Servicios',
            icon: Icons.build_outlined,
            color: AppColors.purple,
          ),
        ],
      ),
    );
  }
}

// ── Widgets auxiliares ────────────────────────────────────────────────────────

class _QA {
  final String label;
  final IconData icon;
  final Color color;
  final Widget page;
  const _QA(this.label, this.icon, this.color, this.page);
}

class _BigStatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _BigStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const Spacer(),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: color,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.white54),
          ),
        ],
      ),
    );
  }
}

class _SmallStatCard extends StatelessWidget {
  final String label, value;
  final Color color;
  const _SmallStatCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 9, color: Colors.white54),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _GaugeCard extends StatelessWidget {
  final String label, subtitle;
  final double value;
  final Color color;
  const _GaugeCard({
    required this.label,
    required this.value,
    required this.color,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0xFF1C1F28),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: CustomPaint(
              painter: _ArcPainter(value, color),
              child: Center(
                child: Text(
                  '${(value * 100).toInt()}%',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 11, color: Colors.white54),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: value,
                    minHeight: 6,
                    backgroundColor: color.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  final double value;
  final Color color;
  const _ArcPainter(this.value, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = math.min(cx, cy) - 4;
    final bg = Paint()
      ..color = color.withValues(alpha: 0.12)
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final fg = Paint()
      ..color = color
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      -math.pi / 2,
      2 * math.pi,
      false,
      bg,
    );
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      -math.pi / 2,
      2 * math.pi * value,
      false,
      fg,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.value != value;
}

class _BottomStat extends StatelessWidget {
  final String value, label;
  final IconData icon;
  final Color color;
  const _BottomStat({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Colors.white54),
        ),
      ],
    );
  }
}

// ── Modelo de datos ───────────────────────────────────────────────────────────
class _DashboardStats {
  final int totalAssets, assetsFuncionando, assetsLibre, assetsAsignado;
  final int assetsMantenimiento, assetsDescompuesto, assetsBaja;
  final int totalMantenimientos, mtPendientes, mtEnProceso, mtConcluidos;
  final int mtVencidos, mtPorVencer, totalFotos;
  // Tickets
  final int tkTotal, tkAbiertos, tkEnProceso, tkPausa;
  final int tkCerrados, tkCancelados, tkCriticos, tkVencidos;
  final int unreadNotifications;

  const _DashboardStats({
    required this.totalAssets,
    required this.assetsFuncionando,
    required this.assetsLibre,
    required this.assetsAsignado,
    required this.assetsMantenimiento,
    required this.assetsDescompuesto,
    required this.assetsBaja,
    required this.totalMantenimientos,
    required this.mtPendientes,
    required this.mtEnProceso,
    required this.mtConcluidos,
    required this.mtVencidos,
    required this.mtPorVencer,
    required this.totalFotos,
    required this.tkTotal,
    required this.tkAbiertos,
    required this.tkEnProceso,
    required this.tkPausa,
    required this.tkCerrados,
    required this.tkCancelados,
    required this.tkCriticos,
    required this.tkVencidos,
    required this.unreadNotifications,
  });

  factory _DashboardStats.empty() => const _DashboardStats(
    totalAssets: 0,
    assetsFuncionando: 0,
    assetsLibre: 0,
    assetsAsignado: 0,
    assetsMantenimiento: 0,
    assetsDescompuesto: 0,
    assetsBaja: 0,
    totalMantenimientos: 0,
    mtPendientes: 0,
    mtEnProceso: 0,
    mtConcluidos: 0,
    mtVencidos: 0,
    mtPorVencer: 0,
    totalFotos: 0,
    tkTotal: 0,
    tkAbiertos: 0,
    tkEnProceso: 0,
    tkPausa: 0,
    tkCerrados: 0,
    tkCancelados: 0,
    tkCriticos: 0,
    tkVencidos: 0,
    unreadNotifications: 0,
  );
}

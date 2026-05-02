import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'account_settings_page.dart';
import 'assignments_page.dart';
import 'app_theme.dart';
import 'assets_page.dart';
import 'login_page.dart';
import 'maintenance_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool _loading = false;
  String _status = 'Cargando datos del dashboard...';
  late _DashboardStats _stats;

  @override
  void initState() {
    super.initState();
    _stats = _DashboardStats.empty();
    _loadStats();
  }

  Future<void> _signOut(BuildContext context) async {
    await Supabase.instance.client.auth.signOut();
    if (!context.mounted) return;
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

      int activos = 0;
      int assetMantenimiento = 0;
      int assetBaja = 0;
      for (final row in assets) {
        final status = (row as Map<String, dynamic>)['status']?.toString() ?? '';
        if (status == 'activo') activos++;
        if (status == 'mantenimiento') assetMantenimiento++;
        if (status == 'baja') assetBaja++;
      }

      int pend = 0;
      int enProceso = 0;
      int concl = 0;
      int vencido = 0;
      int porVencer = 0;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      for (final row in maints) {
        final map = row as Map<String, dynamic>;
        final status = map['status']?.toString() ?? 'pendiente';
        if (status == 'pendiente') pend++;
        if (status == 'en_proceso') enProceso++;
        if (status == 'concluido') concl++;

        if (status != 'concluido') {
          final dueString = map['next_due_date']?.toString();
          final due = dueString == null ? null : DateTime.tryParse(dueString);
          if (due != null) {
            final dueDate = DateTime(due.year, due.month, due.day);
            final days = dueDate.difference(today).inDays;
            if (days < 0) {
              vencido++;
            } else if (days <= 2) {
              porVencer++;
            }
          }
        }
      }

      setState(() {
        _stats = _DashboardStats(
          totalAssets: assets.length,
          assetsActivos: activos,
          assetsMantenimiento: assetMantenimiento,
          assetsBaja: assetBaja,
          totalMantenimientos: maints.length,
          mtPendientes: pend,
          mtEnProceso: enProceso,
          mtConcluidos: concl,
          mtVencidos: vencido,
          mtPorVencer: porVencer,
          totalFotos: docs.length,
        );
        _status = 'Dashboard actualizado.';
      });
    } on PostgrestException catch (e) {
      setState(() => _status = 'Error al cargar dashboard: ${e.message}');
    } catch (e) {
      setState(() => _status = 'Error inesperado: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = Supabase.instance.client.auth.currentUser?.email ?? 'Sin usuario';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard TI'),
        actions: [
          const ThemeToggleButton(),
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _loading ? null : _loadStats,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.dashboard_outlined),
                title: const Text('Dashboard'),
                subtitle: const Text('Resumen general'),
                onTap: () => Navigator.of(context).pop(),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('Configuracion de cuenta'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AccountSettingsPage()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: const Text('Activos'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AssetsPage()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.assignment_ind_outlined),
                title: const Text('Asignaciones'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AssignmentsPage()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.build_circle_outlined),
                title: const Text('Mantenimientos'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MaintenancePage()),
                  );
                },
              ),
              const Spacer(),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.login_outlined),
                title: const Text('Ir a login (cerrar sesion)'),
                onTap: () {
                  Navigator.of(context).pop();
                  _signOut(context);
                },
              ),
            ],
          ),
        ),
      ),
      body: GradientBody(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SectionCard(
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                    child: Icon(
                      Icons.person_outline,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Sesion activa',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(email),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Resumen de Activos',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _StatChip(label: 'Total', value: _stats.totalAssets.toString()),
                      _StatChip(label: 'Activos', value: _stats.assetsActivos.toString()),
                      _StatChip(
                        label: 'En mantenimiento',
                        value: _stats.assetsMantenimiento.toString(),
                      ),
                      _StatChip(label: 'Baja', value: _stats.assetsBaja.toString()),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Resumen de Mantenimientos',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _StatChip(
                        label: 'Servicios',
                        value: _stats.totalMantenimientos.toString(),
                      ),
                      _StatChip(
                        label: 'Pendientes',
                        value: _stats.mtPendientes.toString(),
                      ),
                      _StatChip(
                        label: 'En proceso',
                        value: _stats.mtEnProceso.toString(),
                      ),
                      _StatChip(
                        label: 'Concluidos',
                        value: _stats.mtConcluidos.toString(),
                      ),
                      _StatChip(
                        label: 'Vencidos',
                        value: _stats.mtVencidos.toString(),
                      ),
                      _StatChip(
                        label: 'Por vencer',
                        value: _stats.mtPorVencer.toString(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SectionCard(
              child: Row(
                children: [
                  const Icon(Icons.photo_library_outlined),
                  const SizedBox(width: 10),
                  Text('Evidencias fotografias: ${_stats.totalFotos}'),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(_status),
            const SizedBox(height: 70),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;

  const _StatChip({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(value),
        ],
      ),
    );
  }
}

class _DashboardStats {
  final int totalAssets;
  final int assetsActivos;
  final int assetsMantenimiento;
  final int assetsBaja;
  final int totalMantenimientos;
  final int mtPendientes;
  final int mtEnProceso;
  final int mtConcluidos;
  final int mtVencidos;
  final int mtPorVencer;
  final int totalFotos;

  const _DashboardStats({
    required this.totalAssets,
    required this.assetsActivos,
    required this.assetsMantenimiento,
    required this.assetsBaja,
    required this.totalMantenimientos,
    required this.mtPendientes,
    required this.mtEnProceso,
    required this.mtConcluidos,
    required this.mtVencidos,
    required this.mtPorVencer,
    required this.totalFotos,
  });

  factory _DashboardStats.empty() {
    return const _DashboardStats(
      totalAssets: 0,
      assetsActivos: 0,
      assetsMantenimiento: 0,
      assetsBaja: 0,
      totalMantenimientos: 0,
      mtPendientes: 0,
      mtEnProceso: 0,
      mtConcluidos: 0,
      mtVencidos: 0,
      mtPorVencer: 0,
      totalFotos: 0,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_theme.dart';
import 'ticket_detail_page.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _notifications = [];

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    await _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() => _loading = true);
    try {
      final response = await Supabase.instance.client
          .from('notifications')
          .select()
          .order('created_at', ascending: false)
          .limit(50);

      if (mounted) {
        setState(() {
          _notifications = List<Map<String, dynamic>>.from(response);
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading notifications: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markAllAsRead() async {
    try {
      debugPrint('Intentando marcar todas como leídas...');
      // 1. Actualizar en la base de datos
      final response = await Supabase.instance.client
          .from('notifications')
          .update({'is_read': true})
          .eq('is_read', false)
          .select(); // El .select() nos ayuda a confirmar si algo cambió
      
      debugPrint('Respuesta de Supabase (filas afectadas): ${response.length}');
      
      // 2. Actualizar LOCALMENTE de inmediato
      if (mounted) {
        setState(() {
          for (var n in _notifications) {
            n['is_read'] = true;
          }
        });
      }
    } catch (e) {
      debugPrint('*** ERROR CRÍTICO AL MARCAR COMO LEÍDAS ***');
      debugPrint('Detalle del error: $e');
      debugPrint('Sugerencia: Verifica si la tabla "notifications" tiene habilitado RLS y si tienes una política de UPDATE.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Notificaciones',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadNotifications,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.amber),
            )
          : _notifications.isEmpty
          ? _buildEmptyState()
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _notifications.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final notif = _notifications[index];
                return _NotificationCard(
                  notification: notif,
                  onTap: () => _handleNotificationTap(notif),
                );
              },
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_none_outlined,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No tienes notificaciones aún',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Aquí aparecerán las alertas de nuevos tickets\ny actualizaciones importantes.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ],
      ),
    );
  }

  void _handleNotificationTap(Map<String, dynamic> notif) async {
    final ticketId = notif['ticket_id']?.toString();
    final notifId = notif['id'];

    // Marcar esta notificación específica como leída
    try {
      await Supabase.instance.client
          .from('notifications')
          .update({'is_read': true})
          .eq('id', notifId);
      
      if (mounted) {
        setState(() {
          notif['is_read'] = true;
        });
      }
    } catch (e) {
      debugPrint('Error marking single notification as read: $e');
    }

    if (ticketId != null && ticketId.isNotEmpty) {
      try {
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TicketDetailPage(ticketId: ticketId),
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo abrir el detalle del ticket'),
          ),
        );
      }
    }
  }
}

class _NotificationCard extends StatelessWidget {
  final Map<String, dynamic> notification;
  final VoidCallback onTap;

  const _NotificationCard({required this.notification, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final type = notification['type'] ?? 'info';

    IconData icon = Icons.notifications_outlined;
    Color color = AppColors.blue;

    if (type == 'ticket_new') {
      icon = Icons.confirmation_number_outlined;
      color = AppColors.amber;
    } else if (type == 'ticket_urgent') {
      icon = Icons.warning_amber_rounded;
      color = AppColors.red;
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: (notification['is_read'] == false)
                ? color
                : (isDark ? Colors.white10 : Colors.black12),
            width: (notification['is_read'] == false) ? 1.5 : 1,
          ),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        notification['title'] ?? 'Notificación',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        _formatDate(notification['created_at']),
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification['body'] ?? '',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes}m';
      if (diff.inHours < 24) return 'Hace ${diff.inHours}h';
      return '${date.day}/${date.month}';
    } catch (_) {
      return '';
    }
  }
}

import 'dart:convert';
import 'package:http/http.dart' as http;

// ─────────────────────────── Modelos ───────────────────────────

class Ticket {
  final String ticketId;
  final String nombre;
  final String email;
  final String? departamento;
  final String asunto;
  final String prioridad;
  final String tipoSolicitud;
  final String estado;
  final String? fechaLimite;
  final String createdAt;
  final int? segundosRestantes;
  final bool evaluacionCompletada;
  final List<String> adjuntos;

  static const String _imageBaseUrl =
      'https://reclutamiento-promsan.com/uploads/tickets/';

  List<String> get imageUrls =>
      adjuntos.map((f) => '$_imageBaseUrl$f').toList();

  const Ticket({
    required this.ticketId,
    required this.nombre,
    required this.email,
    this.departamento,
    required this.asunto,
    required this.prioridad,
    required this.tipoSolicitud,
    required this.estado,
    this.fechaLimite,
    required this.createdAt,
    this.segundosRestantes,
    required this.evaluacionCompletada,
    required this.adjuntos,
  });

  factory Ticket.fromMap(Map<String, dynamic> m) {
    return Ticket(
      ticketId: m['ticket_id']?.toString() ?? '',
      nombre: m['nombre']?.toString() ?? '',
      email: m['email']?.toString() ?? '',
      departamento: m['departamento']?.toString(),
      asunto: m['asunto']?.toString() ?? '',
      prioridad: m['prioridad']?.toString() ?? 'Baja',
      tipoSolicitud: m['tipo_solicitud']?.toString() ?? 'Programable',
      estado: m['estado']?.toString() ?? 'Abierto',
      fechaLimite: m['fecha_limite']?.toString(),
      createdAt: m['created_at']?.toString() ?? '',
      segundosRestantes: int.tryParse(m['segundos_restantes']?.toString() ?? ''),
      evaluacionCompletada: (m['evaluacion_completada']?.toString() == '1'),
      adjuntos: _parseAdjuntos(m['adjuntos']),
    );
  }

  static List<String> _parseAdjuntos(dynamic raw) {
    if (raw == null || raw.toString().isEmpty || raw.toString() == 'null') return [];
    try {
      final decoded = jsonDecode(raw.toString());
      if (decoded is List) {
        return decoded.map((e) => e.toString()).toList();
      }
    } catch (_) {}
    return [];
  }
}

class TicketHistorial {
  final String accion;
  final String? descripcion;
  final String realizadoPor;
  final String createdAt;

  const TicketHistorial({
    required this.accion,
    this.descripcion,
    required this.realizadoPor,
    required this.createdAt,
  });

  factory TicketHistorial.fromMap(Map<String, dynamic> m) {
    return TicketHistorial(
      accion: m['accion']?.toString() ?? '',
      descripcion: m['descripcion']?.toString(),
      realizadoPor: m['realizado_por']?.toString() ?? 'Sistema',
      createdAt: m['created_at']?.toString() ?? '',
    );
  }
}

class TicketEvaluacion {
  final int p1Comunicacion;
  final int p2Satisfaccion;
  final int p3TiempoRespuesta;
  final int p4Resolucion;
  final int p5Facilidad;
  final double promedio;
  final String? comentarios;
  final bool esAutomatica;

  const TicketEvaluacion({
    required this.p1Comunicacion,
    required this.p2Satisfaccion,
    required this.p3TiempoRespuesta,
    required this.p4Resolucion,
    required this.p5Facilidad,
    required this.promedio,
    this.comentarios,
    required this.esAutomatica,
  });

  factory TicketEvaluacion.fromMap(Map<String, dynamic> m) {
    return TicketEvaluacion(
      p1Comunicacion: int.tryParse(m['p1_comunicacion']?.toString() ?? '0') ?? 0,
      p2Satisfaccion: int.tryParse(m['p2_satisfaccion']?.toString() ?? '0') ?? 0,
      p3TiempoRespuesta: int.tryParse(m['p3_tiempo_respuesta']?.toString() ?? '0') ?? 0,
      p4Resolucion: int.tryParse(m['p4_resolucion']?.toString() ?? '0') ?? 0,
      p5Facilidad: int.tryParse(m['p5_facilidad']?.toString() ?? '0') ?? 0,
      promedio: double.tryParse(m['promedio']?.toString() ?? '0') ?? 0.0,
      comentarios: m['comentarios']?.toString(),
      esAutomatica: (m['es_automatica']?.toString() == '1'),
    );
  }
}

class TicketDetail {
  final Ticket ticket;
  final List<TicketHistorial> historial;
  final TicketEvaluacion? evaluacion;

  const TicketDetail({
    required this.ticket,
    required this.historial,
    this.evaluacion,
  });
}

// ─────────────────────────── Servicio ───────────────────────────

class TicketService {
  static String get _baseUrl =>
      const String.fromEnvironment(
        'TICKETS_API_URL',
        defaultValue: 'https://reclutamiento-promsan.com/api-sistemas/tickets',
      );
  static String get _token =>
      const String.fromEnvironment(
        'CONTACTO_API_TOKEN',
        defaultValue: 'SistemasTK2026',
      );

  static Map<String, String> get _headers => {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    if (_token.isNotEmpty) 'X-API-KEY': _token,
  };

  static Future<List<Ticket>> getTickets({
    String estado = 'todos',
    int page = 1,
    int limit = 30,
  }) async {
    final uri = Uri.parse('$_baseUrl/get_tickets.php').replace(
      queryParameters: {
        if (estado != 'todos') 'estado': estado,
        'page': page.toString(),
        'limit': limit.toString(),
      },
    );

    final response = await http.get(uri, headers: _headers)
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('Error al obtener tickets (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (decoded['success'] != true) {
      throw Exception(decoded['error']?.toString() ?? 'Error desconocido');
    }

    final data = decoded['data'] as Map<String, dynamic>;
    final rows = data['tickets'] as List<dynamic>;
    return rows
        .whereType<Map<String, dynamic>>()
        .map(Ticket.fromMap)
        .toList();
  }

  static Future<TicketDetail> getTicketDetail(String ticketId) async {
    final uri = Uri.parse('$_baseUrl/get_ticket_detail.php').replace(
      queryParameters: {'ticket_id': ticketId},
    );

    final response = await http.get(uri, headers: _headers)
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('Error al obtener detalle (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (decoded['success'] != true) {
      throw Exception(decoded['error']?.toString() ?? 'Error desconocido');
    }

    final data = decoded['data'] as Map<String, dynamic>;
    final historialRaw = data['historial'] as List<dynamic>;
    final evalRaw = data['evaluacion'];

    return TicketDetail(
      ticket: Ticket.fromMap(data['ticket'] as Map<String, dynamic>),
      historial: historialRaw
          .whereType<Map<String, dynamic>>()
          .map(TicketHistorial.fromMap)
          .toList(),
      evaluacion: evalRaw != null
          ? TicketEvaluacion.fromMap(evalRaw as Map<String, dynamic>)
          : null,
    );
  }

  static Future<void> updateTicketStatus({
    required String ticketId,
    required String accion, // 'cerrar' | 'cancelar' | 'reanudar'
    String comentario = '',
  }) async {
    final uri = Uri.parse('$_baseUrl/update_ticket_status.php');
    final body = jsonEncode({
      'ticket_id': ticketId,
      'accion': accion,
      'comentario': comentario,
    });

    final response = await http.post(uri, headers: _headers, body: body)
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('Error al actualizar ticket (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (decoded['success'] != true) {
      throw Exception(decoded['error']?.toString() ?? 'Error al actualizar');
    }
  }
}

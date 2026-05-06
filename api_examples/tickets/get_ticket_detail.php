<?php
header('Content-Type: application/json');

if (file_exists('bd_reclutamiento.php')) {
    require_once 'bd_reclutamiento.php';
} elseif (file_exists('../bd_reclutamiento.php')) {
    require_once '../bd_reclutamiento.php';
}

$headers = apache_request_headers();
$apiKey = $headers['X-API-KEY'] ?? $headers['x-api-key'] ?? '';

if ($apiKey !== 'SistemasTK2026') {
    http_response_code(401);
    die(json_encode(['success' => false, 'error' => 'No autorizado']));
}

$ticket_id = $_GET['ticket_id'] ?? '';

if (empty($ticket_id)) {
    die(json_encode(['success' => false, 'error' => 'Falta ticket_id']));
}

try {
    // 1. Datos del Ticket (Tabla: tickets_asistencia)
    $stmt = $pdo_reclutamiento->prepare("SELECT ticket_id, nombre, email, departamento, asunto, prioridad, tipo_solicitud, estado, fecha_limite, created_at, evaluacion_completada, adjuntos, descripcion FROM tickets_asistencia WHERE ticket_id = ?");
    $stmt->execute([$ticket_id]);
    $ticket = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$ticket) {
        die(json_encode(['success' => false, 'error' => 'Ticket no encontrado']));
    }

    // 2. Historial (Tabla: tickets_historial)
    $stmtH = $pdo_reclutamiento->prepare("SELECT accion, descripcion, realizado_por, created_at FROM tickets_historial WHERE ticket_id = ? ORDER BY id ASC");
    $stmtH->execute([$ticket_id]);
    $historial = $stmtH->fetchAll(PDO::FETCH_ASSOC);

    // 3. Evaluación (Tabla: ticket_evaluaciones)
    $stmtE = $pdo_reclutamiento->prepare("SELECT * FROM ticket_evaluaciones WHERE ticket_id = ? LIMIT 1");
    $stmtE->execute([$ticket_id]);
    $evaluacion = $stmtE->fetch(PDO::FETCH_ASSOC);

    echo json_encode([
        'success' => true,
        'data' => [
            'ticket' => $ticket,
            'historial' => $historial,
            'evaluacion' => $evaluacion ?: null
        ]
    ], JSON_UNESCAPED_UNICODE);

} catch (PDOException $e) {
    http_response_code(500);
    echo json_encode(['success' => false, 'error' => $e->getMessage()]);
}

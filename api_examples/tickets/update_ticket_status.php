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

$raw = file_get_contents('php://input');
$data = json_decode($raw, true);

$ticket_id = $data['ticket_id'] ?? '';
$accion = $data['accion'] ?? ''; 
$comentario = $data['comentario'] ?? '';

if (empty($ticket_id) || empty($accion)) {
    die(json_encode(['success' => false, 'error' => 'Datos incompletos']));
}

try {
    $nuevoEstado = '';
    $descripcionHistorial = '';

    switch ($accion) {
        case 'cerrar':
            $nuevoEstado = 'Cerrado';
            $descripcionHistorial = "Ticket cerrado desde la App. " . $comentario;
            break;
        case 'cancelar':
            $nuevoEstado = 'Cancelado';
            $descripcionHistorial = "Ticket cancelado desde la App. " . $comentario;
            break;
        case 'reanudar':
            $nuevoEstado = 'Abierto';
            $descripcionHistorial = "Ticket reanudado desde la App. " . $comentario;
            break;
        default:
            die(json_encode(['success' => false, 'error' => 'Acción no válida']));
    }

    $pdo_reclutamiento->beginTransaction();

    // 1. Actualizar (Tabla: tickets_asistencia)
    $stmt = $pdo_reclutamiento->prepare("UPDATE tickets_asistencia SET estado = ?, updated_at = NOW() WHERE ticket_id = ?");
    $stmt->execute([$nuevoEstado, $ticket_id]);

    // 2. Historial (Tabla: tickets_historial)
    $stmtH = $pdo_reclutamiento->prepare("INSERT INTO tickets_historial (ticket_id, accion, descripcion, realizado_por, created_at) VALUES (?, ?, ?, ?, NOW())");
    $stmtH->execute([$ticket_id, strtoupper($accion), $descripcionHistorial, 'Soporte Técnico App']);

    $pdo_reclutamiento->commit();

    echo json_encode(['success' => true, 'message' => "Ticket actualizado a $nuevoEstado"]);

} catch (PDOException $e) {
    if ($pdo_reclutamiento->inTransaction()) $pdo_reclutamiento->rollBack();
    http_response_code(500);
    echo json_encode(['success' => false, 'error' => $e->getMessage()]);
}

<?php
header('Content-Type: application/json; charset=utf-8');

// Localizar la conexión de forma robusta
if (file_exists('bd_reclutamiento.php')) {
    require_once 'bd_reclutamiento.php';
} elseif (file_exists('../bd_reclutamiento.php')) {
    require_once '../bd_reclutamiento.php';
} else {
    die(json_encode(['success' => false, 'error' => 'Archivo de conexión no encontrado']));
}

$headers = apache_request_headers();
$apiKey = $headers['X-API-KEY'] ?? $headers['x-api-key'] ?? '';

if ($apiKey !== 'SistemasTK2026') {
    http_response_code(401);
    die(json_encode(['success' => false, 'error' => 'No autorizado']));
}

$estado = $_GET['estado'] ?? 'todos';

try {
    $sql = "SELECT * FROM tickets_asistencia ORDER BY id DESC LIMIT 500";
    $stmt = $pdo_reclutamiento->prepare($sql);
    $stmt->execute();
    $tickets = $stmt->fetchAll(PDO::FETCH_ASSOC);

    echo json_encode([
        'success' => true, 
        'data' => [
            'tickets' => $tickets,
            'total' => count($tickets)
        ]
    ], JSON_UNESCAPED_UNICODE);

} catch (PDOException $e) {
    http_response_code(500);
    echo json_encode(['success' => false, 'error' => 'Error SQL: ' . $e->getMessage()]);
}

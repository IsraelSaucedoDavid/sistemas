<?php
header('Content-Type: application/json; charset=utf-8');

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

try {
    // Intentar crear la tabla si no existe (Historial de notificaciones)
    $sql_create = "CREATE TABLE IF NOT EXISTS notificaciones_historial (
        id INT AUTO_INCREMENT PRIMARY KEY,
        ticket_id VARCHAR(32),
        titulo VARCHAR(200),
        mensaje TEXT,
        tipo VARCHAR(50) DEFAULT 'info',
        leida TINYINT(1) DEFAULT 0,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )";
    $pdo_reclutamiento->exec($sql_create);

    // Obtener las últimas 50 notificaciones
    $sql = "SELECT * FROM notificaciones_historial ORDER BY created_at DESC LIMIT 50";
    $stmt = $pdo_reclutamiento->prepare($sql);
    $stmt->execute();
    $notificaciones = $stmt->fetchAll(PDO::FETCH_ASSOC);

    echo json_encode(['success' => true, 'data' => $notificaciones], JSON_UNESCAPED_UNICODE);

} catch (PDOException $e) {
    http_response_code(500);
    echo json_encode(['success' => false, 'error' => 'Error SQL: ' . $e->getMessage()]);
}

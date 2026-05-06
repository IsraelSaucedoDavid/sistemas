<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { exit; }

// Buscamos la conexión en la carpeta superior
require_once '../bd_reclutamiento.php'; 

$raw = file_get_contents('php://input');
$data = json_decode($raw, true);
$token = $data['token'] ?? '';
$email = $data['email'] ?? 'admin';

if (empty($token)) {
    echo json_encode(['success' => false, 'error' => 'Token vacío']);
    exit;
}

try {
    $pdo_reclutamiento->exec("CREATE TABLE IF NOT EXISTS tecnicos_tokens (
        id INT AUTO_INCREMENT PRIMARY KEY,
        email VARCHAR(255),
        token TEXT NOT NULL,
        ultima_actualizacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        UNIQUE KEY(email(50))
    )");

    $stmt = $pdo_reclutamiento->prepare("INSERT INTO tecnicos_tokens (email, token) 
        VALUES (?, ?) ON DUPLICATE KEY UPDATE token = ?, ultima_actualizacion = NOW()");
    $stmt->execute([$email, $token, $token]);

    echo json_encode(['success' => true, 'message' => 'Token registrado en subcarpeta tickets']);
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['success' => false, 'error' => $e->getMessage()]);
}

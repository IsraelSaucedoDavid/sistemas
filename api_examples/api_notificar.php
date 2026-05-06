<?php
header('Content-Type: application/json');
require_once 'bd_reclutamiento.php';

// El archivo service-account.json es NECESARIO para autenticarse con Firebase V1
$serviceAccountPath = __DIR__ . '/service-account.json'; 

if (!file_exists($serviceAccountPath)) {
    http_response_code(500);
    echo json_encode(['success' => false, 'error' => 'No se encontro service-account.json en el servidor']);
    exit;
}

$config = json_decode(file_get_contents($serviceAccountPath), true);

// 1. Obtener todos los tokens registrados en la base de datos
try {
    $stmt = $pdo_reclutamiento->query("SELECT token FROM tecnicos_tokens");
    $tokens = $stmt->fetchAll(PDO::FETCH_COLUMN);
    
    if (empty($tokens)) {
        echo json_encode(['success' => false, 'error' => 'No hay dispositivos (tokens) registrados en la tabla tecnicos_tokens']);
        exit;
    }

    // 2. Generar el Access Token de Google para FCM V1
    $accessToken = getAccessToken($config);
    if (!$accessToken) {
        throw new Exception("No se pudo generar el Access Token de Google. Revisa tu service-account.json");
    }

    // 3. Enviar la notificación a cada token
    $successCount = 0;
    $errors = [];
    
    foreach ($tokens as $token) {
        $res = sendPush(
            $token, 
            "🎫 Nuevo Ticket", 
            "Se ha recibido una nueva solicitud de soporte técnico.", 
            $accessToken, 
            $config['project_id']
        );
        
        if (isset($res['name'])) {
            $successCount++;
        } else {
            $errors[] = $res;
        }
    }

    echo json_encode([
        'success' => true, 
        'enviados' => $successCount, 
        'fallidos' => count($errors),
        'detalles_error' => $errors
    ], JSON_UNESCAPED_UNICODE);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['success' => false, 'error' => $e->getMessage()]);
}

// --- FUNCIONES AUXILIARES PARA FIREBASE V1 ---

function sendPush($token, $title, $body, $accessToken, $projectId) {
    $url = "https://fcm.googleapis.com/v1/projects/$projectId/messages:send";
    
    $message = [
        'message' => [
            'token' => $token,
            'notification' => [
                'title' => $title,
                'body' => $body
            ],
            'android' => [
                'notification' => [
                    'channel_id' => 'tickets_channel',
                    'priority' => 'high',
                    'click_action' => 'FLUTTER_NOTIFICATION_CLICK'
                ]
            ],
            'apns' => [
                'payload' => [
                    'aps' => [
                        'sound' => 'default'
                    ]
                ]
            ],
            'data' => [
                'click_action' => 'FLUTTER_NOTIFICATION_CLICK',
                'type' => 'new_ticket'
            ]
        ]
    ];

    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, $url);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_HTTPHEADER, [
        'Authorization: Bearer ' . $accessToken,
        'Content-Type: application/json'
    ]);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($message));
    $res = curl_exec($ch);
    curl_close($ch);
    
    return json_decode($res, true);
}

function getAccessToken($config) {
    $header = base64UrlEncode(json_encode(['alg' => 'RS256', 'typ' => 'JWT']));
    $payload = base64UrlEncode(json_encode([
        'iss' => $config['client_email'],
        'scope' => 'https://www.googleapis.com/auth/firebase.messaging',
        'aud' => $config['token_uri'],
        'iat' => time(),
        'exp' => time() + 3600
    ]));
    
    $privateKey = $config['private_key'];
    $signature = '';
    openssl_sign("$header.$payload", $signature, $privateKey, 'SHA256');
    $jwt = "$header.$payload." . base64UrlEncode($signature);
    
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, $config['token_uri']);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, http_build_query([
        'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        'assertion' => $jwt
    ]));
    $res = json_decode(curl_exec($ch), true);
    
    return $res['access_token'] ?? null;
}

function base64UrlEncode($data) {
    return str_replace(['+', '/', '='], ['-', '_', ''], base64_encode($data));
}

<?php
header('Content-Type: application/json');
require_once '../bd_reclutamiento.php'; // Conexión en carpeta superior

// El nuevo archivo generado por el usuario en la raíz
$serviceAccountPath = __DIR__ . '/../../sistemas-25486-firebase-adminsdk-fbsvc-35160549db.json'; 

if (!file_exists($serviceAccountPath)) {
    // Si no está en la raíz, buscarlo en la carpeta tickets por si acaso
    $serviceAccountPath = __DIR__ . '/sistemas-25486-firebase-adminsdk-fbsvc-35160549db.json';
}

if (!file_exists($serviceAccountPath)) {
    http_response_code(500);
    echo json_encode(['success' => false, 'error' => 'No se encontró el nuevo archivo JSON de credenciales']);
    exit;
}

$config = json_decode(file_get_contents($serviceAccountPath), true);

try {
    $stmt = $pdo_reclutamiento->query("SELECT token FROM tecnicos_tokens");
    $tokens = $stmt->fetchAll(PDO::FETCH_COLUMN);
    
    if (empty($tokens)) {
        echo json_encode(['success' => false, 'error' => 'No hay dispositivos registrados']);
        exit;
    }

    $accessToken = getAccessToken($config);
    
    // Si hubo error de autenticación, mostrarlo y salir
    if (is_array($accessToken)) {
        die(json_encode(['success' => false, 'error' => 'Error de autenticación con Google', 'detalle' => $accessToken]));
    }

    $successCount = 0;
    $errors = [];
    
    foreach ($tokens as $token) {
        $res = sendPush($token, "🎫 Nuevo Ticket", "Se ha recibido una nueva solicitud de soporte técnico.", $accessToken, $config['project_id']);
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
        'errores' => $errors
    ]);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['success' => false, 'error' => $e->getMessage()]);
}

function sendPush($token, $title, $body, $accessToken, $projectId) {
    $url = "https://fcm.googleapis.com/v1/projects/$projectId/messages:send";
    $message = [
        'message' => [
            'token' => $token,
            'notification' => ['title' => $title, 'body' => $body],
            'data' => ['type' => 'new_ticket']
        ]
    ];
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, $url);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_HTTPHEADER, ['Authorization: Bearer ' . $accessToken, 'Content-Type: application/json']);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($message));
    $res = curl_exec($ch);
    curl_close($ch);
    return json_decode($res, true);
}

function getAccessToken($config) {
    // Lógica EXACTA de test_push.php
    $raw_key = $config['private_key'];
    $key_body = str_replace(["-----BEGIN PRIVATE KEY-----", "-----END PRIVATE KEY-----", "-----BEGIN RSA PRIVATE KEY-----", "-----END RSA PRIVATE KEY-----", "\n", "\r", " ", "\\n"], "", $raw_key);
    // Intentamos con el formato RSA específico
    $formatted_key = "-----BEGIN RSA PRIVATE KEY-----\n" . chunk_split($key_body, 64, "\n") . "-----END RSA PRIVATE KEY-----";

    $header = base64UrlEncode(json_encode(['alg' => 'RS256', 'typ' => 'JWT']));
    $payload = base64UrlEncode(json_encode([
        'iss' => $config['client_email'], 
        'scope' => 'https://www.googleapis.com/auth/firebase.messaging', 
        'aud' => $config['token_uri'], 
        'iat' => time(), 
        'exp' => time() + 3600
    ]));
    
    $signature = '';
    // Pasamos la cadena $formatted_key directamente
    if (!openssl_sign($header . "." . $payload, $signature, $formatted_key, 'SHA256')) {
        return ['error_auth' => 'Fallo al firmar: ' . openssl_error_string()];
    }

    $jwt = $header . "." . $payload . "." . base64UrlEncode($signature);
    
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, $config['token_uri']);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, http_build_query([
        'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer', 
        'assertion' => $jwt
    ]));
    
    $res = json_decode(curl_exec($ch), true);
    curl_close($ch);
    
    return $res['access_token'] ?? ['error_auth' => $res];
}

function base64UrlEncode($data) { return str_replace(['+', '/', '='], ['-', '_', ''], base64_encode($data)); }

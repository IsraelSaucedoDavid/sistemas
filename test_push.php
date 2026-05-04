<?php
error_reporting(E_ALL);
ini_set('display_errors', 1);

echo "<h2>Probando Limpieza de Llave...</h2>";

$jsonPath = __DIR__ . '/service-account.json';
$config = json_decode(file_get_contents($jsonPath), true);

$raw_key = $config['private_key'];

// LIMPIEZA EXTREMA: Quitar todo y volver a armar el PEM
$key_body = str_replace(["-----BEGIN PRIVATE KEY-----", "-----END PRIVATE KEY-----", "\n", "\r", " ", "\\n"], "", $raw_key);
$formatted_key = "-----BEGIN PRIVATE KEY-----\n" . chunk_split($key_body, 64, "\n") . "-----END PRIVATE KEY-----";

$res = openssl_pkey_get_private($formatted_key);

if ($res) {
    echo "✅ ¡LLAVE CARGADA CON ÉXITO! <br>";
    
    $token = 'clDaceYaQj2BJY7CbmzJbj:APA91bG1MVW37Z8cPbyNJiv0mkAn-Crf3aBPeCL_RAK-WJ5xnjnw3PU7iIp1NUrtzx2Dp4kknmtp-XcX_2fjdpzkjIQn3QpsJaawsHiNxUOusFSu3L4OFT0';
    $accessToken = getAccessToken($config, $formatted_key);
    
    if ($accessToken) {
        echo "✅ Access Token generado.<br>";
        $url = "https://fcm.googleapis.com/v1/projects/{$config['project_id']}/messages:send";
        $message = ['message' => ['token' => $token, 'notification' => ['title' => '¡POR FIN! 🚀', 'body' => 'La limpieza extrema funcionó.']]];
        $headers = ['Authorization: Bearer ' . $accessToken, 'Content-Type: application/json'];
        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, $url);
        curl_setopt($ch, CURLOPT_POST, true);
        curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($message));
        echo "<h3>Respuesta de Google:</h3>" . curl_exec($ch);
    }
} else {
    echo "❌ Error cargando llave: " . openssl_error_string();
}

function getAccessToken($config, $cleanKey) {
    $header = base64UrlEncode(json_encode(['alg' => 'RS256', 'typ' => 'JWT']));
    $payload = base64UrlEncode(json_encode(['iss' => $config['client_email'], 'scope' => 'https://www.googleapis.com/auth/firebase.messaging', 'aud' => $config['token_uri'], 'iat' => time(), 'exp' => time() + 3600]));
    $signature = '';
    openssl_sign($header . "." . $payload, $signature, $cleanKey, 'SHA256');
    $jwt = $header . "." . $payload . "." . base64UrlEncode($signature);
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, $config['token_uri']);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, http_build_query(['grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer', 'assertion' => $jwt]));
    $res = json_decode(curl_exec($ch), true);
    return $res['access_token'] ?? null;
}
function base64UrlEncode($data) { return str_replace(['+', '/', '='], ['-', '_', ''], base64_encode($data)); }

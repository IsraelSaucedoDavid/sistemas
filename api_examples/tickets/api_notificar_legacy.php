<?php
header('Content-Type: application/json');
require_once '../bd_reclutamiento.php';

/**
 * MÉTODO LEGACY (PLAN B)
 * Este método no requiere firma JWT ni service-account.json.
 * Solo requiere la "Server Key" de la consola de Firebase.
 */

// TODO: El usuario debe poner su Server Key aquí
$serverKey = 'AAAA6XzI-mY:APA91bG... (Reemplazar con la real)'; 

try {
    $stmt = $pdo_reclutamiento->query("SELECT token FROM tecnicos_tokens");
    $tokens = $stmt->fetchAll(PDO::FETCH_COLUMN);
    
    if (empty($tokens)) {
        die(json_encode(['success' => false, 'error' => 'No hay dispositivos registrados en tecnicos_tokens']));
    }

    $successCount = 0;
    $errors = [];
    
    foreach ($tokens as $token) {
        $url = 'https://fcm.googleapis.com/fcm/send';
        $fields = [
            'to' => $token,
            'notification' => [
                'title' => '🎫 Nuevo Ticket',
                'body' => 'Se ha recibido una nueva solicitud de soporte técnico.',
                'click_action' => 'FLUTTER_NOTIFICATION_CLICK',
                'sound' => 'default'
            ],
            'data' => [
                'type' => 'new_ticket',
                'click_action' => 'FLUTTER_NOTIFICATION_CLICK'
            ],
            'priority' => 'high'
        ];

        $headers = [
            'Authorization: key=' . $serverKey,
            'Content-Type: application/json'
        ];

        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, $url);
        curl_setopt($ch, CURLOPT_POST, true);
        curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
        curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($fields));
        
        $result = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        if ($httpCode == 200) {
            $successCount++;
        } else {
            $errors[] = "Error HTTP $httpCode: $result";
        }
    }

    echo json_encode([
        'success' => true, 
        'enviados' => $successCount, 
        'fallidos' => count($errors),
        'detalle_errores' => $errors,
        'nota' => 'Usando método Legacy para bypass de OpenSSL'
    ]);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['success' => false, 'error' => $e->getMessage()]);
}

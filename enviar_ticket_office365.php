<?php
// Prevenir errores de salida antes de JSON
ob_start();
error_reporting(E_ALL);
ini_set('display_errors', 0);
ini_set('log_errors', 1);

// Incluir autoload primero
try {
    require '../../vendor/autoload.php';
} catch (Exception $e) {
    ob_end_clean();
    header('Content-Type: application/json');
    echo json_encode(['success' => false, 'error' => 'Error cargando PHPMailer: ' . $e->getMessage()]);
    exit;
}

// Incluir PHPMailer
use PHPMailer\PHPMailer\PHPMailer;
use PHPMailer\PHPMailer\Exception;

try {
    include '../config_ticket.php';
    include '../config.php';
    $secrets = include __DIR__ . '/../secrets.php';
} catch (Exception $e) {
    ob_end_clean();
    header('Content-Type: application/json');
    echo json_encode(['success' => false, 'error' => 'Error cargando configuración: ' . $e->getMessage()]);
    exit;
}

// Limpiar output
ob_end_clean();

// Iniciar sesión si no está iniciada
if (session_status() === PHP_SESSION_NONE) {
    session_start();
}

// Obtener datos del formulario
$nombre = $_POST['nombre'] ?? 'No especificado';
$email = $_POST['email'] ?? 'No especificado';
$telefono = $_POST['telefono'] ?? 'No especificado';
$departamento = $_POST['departamento'] ?? 'No especificado';
$prioridad = $_POST['prioridad'] ?? 'Baja';
$asunto_ticket = $_POST['asunto_ticket'] ?? 'No especificado';
$descripcion = $_POST['descripcion'] ?? 'No especificado';
$fecha = date('Y-m-d H:i:s');

// Obtener ID de usuario si hay sesión activa
$id_usuario_creador = isset($_SESSION['user_id']) ? intval($_SESSION['user_id']) : null;

// Calcular tipo_solicitud y tiempo límite automáticamente desde prioridad
// Según indicadores TI: Urgentes (24h), Programables (1 semana), Especiales (depende)
if (in_array($prioridad, ['Crítica', 'Alta'])) {
    // Prioridad Alta o Crítica → Urgente (24 horas)
    $tipo_solicitud = 'Urgente';
    $tiempo_limite_horas = 24;
} else {
    // Prioridad Media o Baja → Programable (1 semana = 168 horas)
    $tipo_solicitud = 'Programable';
    $tiempo_limite_horas = 168;
}

// Calcular fecha límite
$fecha_limite = date('Y-m-d H:i:s', strtotime("+{$tiempo_limite_horas} hours"));

$respuesta = [];
$ticket_id_db = null;

try {
    // Verificar conexión a BD
    if (!isset($conn) || !$conn || $conn->connect_error) {
        throw new Exception('Error de conexión a la base de datos: ' . ($conn->connect_error ?? 'No hay conexión'));
    }

    // Verificar que secrets.php existe y tiene la configuración correcta
    if (!isset($secrets) || !is_array($secrets) || !isset($secrets['smtp'])) {
        throw new Exception('Error en la configuración de email (secrets.php no válido)');
    }

    // Generar ticket_id único
    $ticket_id = 'T' . date('YmdHis') . rand(100, 999);

    // Verificar que el ticket_id sea único
    $sql_check = "SELECT ticket_id FROM tickets_asistencia WHERE ticket_id = ?";
    $stmt_check = $conn->prepare($sql_check);
    $stmt_check->bind_param("s", $ticket_id);
    $stmt_check->execute();
    $result_check = $stmt_check->get_result();

    if ($result_check->num_rows > 0) {
        // Si ya existe, generar uno nuevo
        $ticket_id = 'T' . date('YmdHis') . rand(1000, 9999);
    }
    $stmt_check->close();

    // 1. GUARDAR EN BASE DE DATOS
    // Preparar consulta según si hay id_usuario_creador o no
    if ($id_usuario_creador === null || $id_usuario_creador <= 0) {
        // Sin id_usuario_creador
        $sql_insert = "INSERT INTO tickets_asistencia (
            ticket_id,
            nombre,
            email,
            telefono,
            departamento,
            prioridad,
            tipo_solicitud,
            tiempo_limite_horas,
            fecha_limite,
            asunto,
            descripcion,
            estado,
            canal,
            created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'Abierto', 'web', NOW())";

        $stmt = $conn->prepare($sql_insert);
        if (!$stmt) {
            throw new Exception('Error al preparar la consulta: ' . $conn->error);
        }

        $stmt->bind_param(
            "sssssssisss",
            $ticket_id,
            $nombre,
            $email,
            $telefono,
            $departamento,
            $prioridad,
            $tipo_solicitud,
            $tiempo_limite_horas,
            $fecha_limite,
            $asunto_ticket,
            $descripcion
        );
    } else {
        // Con id_usuario_creador
        $sql_insert = "INSERT INTO tickets_asistencia (
            ticket_id,
            nombre,
            email,
            telefono,
            departamento,
            prioridad,
            tipo_solicitud,
            tiempo_limite_horas,
            fecha_limite,
            asunto,
            descripcion,
            estado,
            canal,
            id_usuario_creador,
            created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'Abierto', 'web', ?, NOW())";

        $stmt = $conn->prepare($sql_insert);
        if (!$stmt) {
            throw new Exception('Error al preparar la consulta: ' . $conn->error);
        }

        $stmt->bind_param(
            "sssssssisssi",
            $ticket_id,
            $nombre,
            $email,
            $telefono,
            $departamento,
            $prioridad,
            $tipo_solicitud,
            $tiempo_limite_horas,
            $fecha_limite,
            $asunto_ticket,
            $descripcion,
            $id_usuario_creador
        );
    }

    if ($stmt->execute()) {
        $ticket_id_db = $conn->insert_id;

        // --- NOTIFICACIÓN PUSH Y REGISTRO EN SUPABASE (HÍBRIDO) ---
        try {
            // 1. Primero registrar en Supabase para el historial de la App
            $supabaseUrl = 'https://smnaclfbrefnzrjblfhp.supabase.co';
            $supabaseKey = 'sb_publishable_ZVwXs8zxnrqRg-0pjtGq_g_AkR2nFu_';
            $notif_data = [
                'ticket_id' => $ticket_id,
                'title'     => "Nuevo Ticket: $asunto_ticket",
                'body'      => "De: $nombre ($departamento)",
                'type'      => 'ticket_new'
            ];
            $ch_sb = curl_init("$supabaseUrl/rest/v1/notifications");
            curl_setopt($ch_sb, CURLOPT_RETURNTRANSFER, true);
            curl_setopt($ch_sb, CURLOPT_POST, true);
            curl_setopt($ch_sb, CURLOPT_POSTFIELDS, json_encode($notif_data));
            curl_setopt($ch_sb, CURLOPT_TIMEOUT, 3);
            curl_setopt($ch_sb, CURLOPT_CONNECTTIMEOUT, 2);
            curl_setopt($ch_sb, CURLOPT_SSL_VERIFYPEER, false);
            curl_setopt($ch_sb, CURLOPT_HTTPHEADER, ["apikey: $supabaseKey", "Authorization: Bearer $supabaseKey", "Content-Type: application/json", "Prefer: return=minimal"]);
            curl_exec($ch_sb);
            curl_close($ch_sb);

            // 2. Ahora enviar Push a Firebase
            $sql_tokens = "SELECT token FROM tecnicos_tokens";
            $res_tokens = $conn->query($sql_tokens);
            $tokens_fcm = [];
            if ($res_tokens) {
                while ($row = $res_tokens->fetch_assoc()) { $tokens_fcm[] = $row['token']; }
            }

            if (!empty($tokens_fcm)) {
                $posibles_rutas = [
                    __DIR__ . '/../../api-sistemas/tickets/sistemas-25486-firebase-adminsdk-fbsvc-35160549db.json',
                    __DIR__ . '/../api-sistemas/tickets/sistemas-25486-firebase-adminsdk-fbsvc-35160549db.json',
                    __DIR__ . '/sistemas-25486-firebase-adminsdk-fbsvc-35160549db.json'
                ];
                
                $fcmConfigPath = null;
                foreach ($posibles_rutas as $ruta) { if (file_exists($ruta)) { $fcmConfigPath = $ruta; break; } }

                if ($fcmConfigPath) {
                    $fcmConfig = json_decode(file_get_contents($fcmConfigPath), true);
                    $raw_key = $fcmConfig['private_key'];
                    $key_body = str_replace(["-----BEGIN PRIVATE KEY-----", "-----END PRIVATE KEY-----", "-----BEGIN RSA PRIVATE KEY-----", "-----END RSA PRIVATE KEY-----", "\n", "\r", " ", "\\n"], "", $raw_key);
                    $formatted_key = "-----BEGIN RSA PRIVATE KEY-----\n" . chunk_split($key_body, 64, "\n") . "-----END RSA PRIVATE KEY-----";
                    
                    $header = str_replace(['+', '/', '='], ['-', '_', ''], base64_encode(json_encode(['alg' => 'RS256', 'typ' => 'JWT'])));
                    $payload = str_replace(['+', '/', '='], ['-', '_', ''], base64_encode(json_encode([
                        'iss' => $fcmConfig['client_email'],
                        'scope' => 'https://www.googleapis.com/auth/firebase.messaging',
                        'aud' => $fcmConfig['token_uri'],
                        'iat' => time(),
                        'exp' => time() + 3600
                    ])));
                    
                    $signature = '';
                    if (openssl_sign("$header.$payload", $signature, $formatted_key, 'SHA256')) {
                        $jwt = "$header.$payload." . str_replace(['+', '/', '='], ['-', '_', ''], base64_encode($signature));
                        $ch_auth = curl_init();
                        curl_setopt($ch_auth, CURLOPT_URL, $fcmConfig['token_uri']);
                        curl_setopt($ch_auth, CURLOPT_POST, true);
                        curl_setopt($ch_auth, CURLOPT_RETURNTRANSFER, true);
                        curl_setopt($ch_auth, CURLOPT_POSTFIELDS, http_build_query(['grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer', 'assertion' => $jwt]));
                        $res_auth = json_decode(curl_exec($ch_auth), true);
                        curl_close($ch_auth);
                        
                        $accessToken = $res_auth['access_token'] ?? null;
                        if ($accessToken) {
                            foreach ($tokens_fcm as $tk) {
                                $url_fcm = "https://fcm.googleapis.com/v1/projects/{$fcmConfig['project_id']}/messages:send";
                                $msg_fcm = [
                                    'message' => [
                                        'token' => $tk,
                                        'notification' => [
                                            'title' => '🎫 Nuevo Ticket #' . $ticket_id,
                                            'body' => "$asunto_ticket ($nombre)"
                                        ],
                                        'android' => [
                                            'priority' => 'high',
                                            'notification' => [
                                                'channel_id' => 'tickets_channel',
                                                'click_action' => 'FLUTTER_NOTIFICATION_CLICK',
                                                'sound' => 'default'
                                            ]
                                        ],
                                        'data' => [
                                            'click_action' => 'FLUTTER_NOTIFICATION_CLICK',
                                            'type' => 'new_ticket',
                                            'ticket_id' => $ticket_id
                                        ]
                                    ]
                                ];
                                $ch_send = curl_init();
                                curl_setopt($ch_send, CURLOPT_URL, $url_fcm);
                                curl_setopt($ch_send, CURLOPT_POST, true);
                                curl_setopt($ch_send, CURLOPT_HTTPHEADER, ['Authorization: Bearer ' . $accessToken, 'Content-Type: application/json']);
                                curl_setopt($ch_send, CURLOPT_RETURNTRANSFER, true);
                                curl_setopt($ch_send, CURLOPT_POSTFIELDS, json_encode($msg_fcm));
                                curl_exec($ch_send);
                                curl_close($ch_send);
                            }
                        }
                    }
                }
            }
        } catch (Exception $e_fcm) {
            error_log("Notification Error: " . $e_fcm->getMessage());
        }
        // --- FIN NOTIFICACIÓN ---

        // Registrar en historial
        try {
            $nombre_historial = $id_usuario_creador
                ? ($_SESSION['nombre_completo'] ?? $_SESSION['usuario'] ?? $nombre)
                : $nombre;

            $sql_historial = "INSERT INTO tickets_historial (
                ticket_id,
                accion,
                descripcion,
                realizado_por,
                created_at
            ) VALUES (?, 'Creación', 'Ticket creado por el usuario', ?, NOW())";

            $stmt_hist = $conn->prepare($sql_historial);
            if ($stmt_hist) {
                $stmt_hist->bind_param("ss", $ticket_id, $nombre_historial);
                $stmt_hist->execute();
                $stmt_hist->close();
            }
        } catch (Exception $e) {
            // Si falla el historial, no es crítico
            error_log("Error en historial: " . $e->getMessage());
        }

        $stmt->close();

        // 2. ENVIAR EMAIL
        try {
            $mail = new PHPMailer(true);
            $mail->CharSet = 'UTF-8';
            $smtp = $secrets['smtp'];
            $mail->isSMTP();
            $mail->Host       = $smtp['host'];
            $mail->SMTPAuth   = true;
            $mail->Username   = $smtp['username'];
            $mail->Password   = $smtp['password'];
            $mail->SMTPSecure = PHPMailer::ENCRYPTION_STARTTLS;
            $mail->Port       = $smtp['port'];
            $mail->setFrom($smtp['from_email'], 'Sistema de Tickets - Promsan');
            $mail->addAddress('david.munoz@promsan.com.mx', 'David Muñoz');
            if (filter_var($email, FILTER_VALIDATE_EMAIL)) {
                $mail->addReplyTo($email, $nombre);
            }

            $mail->isHTML(true);
            $mail->Subject = '🚨 Nuevo Ticket de Asistencia #' . $ticket_id;

            // Calcular tiempo restante para el email
            $tiempo_restante = "{$tiempo_limite_horas} horas";
            if ($tiempo_limite_horas >= 24) {
                $dias = floor($tiempo_limite_horas / 24);
                $tiempo_restante = "{$dias} día(s)";
            }

            $mail->Body = "<div style='font-family: Arial, sans-serif; max-width: 600px; margin: auto; border: 1px solid #ddd; padding: 20px; border-radius: 10px;'>
                <h2 style='color: #007bff;'>🚨 Nuevo Ticket de Asistencia</h2>
                <div style='background: #28a745; color: white; padding: 15px; border-radius: 5px; text-align: center; margin-bottom: 20px;'>
                    <strong>🆔 Ticket #$ticket_id</strong>
                </div>
                <p><strong>👤 Nombre del Usuario:</strong> $nombre</p>
                <p><strong>📧 Email:</strong> $email</p>
                <p><strong>📱 Teléfono:</strong> $telefono</p>
                <p><strong>🏢 Departamento:</strong> $departamento</p>
                <p><strong>⚡ Prioridad:</strong> $prioridad</p>
                <p><strong>🏷️ Tipo de Solicitud:</strong> $tipo_solicitud</p>
                <p><strong>⏱️ Tiempo Límite:</strong> $tiempo_restante</p>
                <p><strong>📅 Fecha Límite:</strong> " . date('d/m/Y H:i', strtotime($fecha_limite)) . "</p>
                <p><strong>📋 Asunto:</strong> $asunto_ticket</p>
                <p><strong>📝 Descripción:</strong> $descripcion</p>
                <p><strong>🕒 Fecha y Hora:</strong> $fecha</p>
            </div>";

            // PROCESAR ADJUNTOS
            $adjuntos_nombres = [];
            if (isset($_FILES['adjuntos']) && !empty($_FILES['adjuntos']['name'][0])) {
                $upload_dir = __DIR__ . '/../../uploads/tickets/';
                if (!is_dir($upload_dir)) {
                    mkdir($upload_dir, 0777, true);
                }

                foreach ($_FILES['adjuntos']['tmp_name'] as $key => $tmp_name) {
                    if ($_FILES['adjuntos']['error'][$key] === UPLOAD_ERR_OK) {
                        $name = $_FILES['adjuntos']['name'][$key];
                        $ext = strtolower(pathinfo($name, PATHINFO_EXTENSION));
                        
                        // Validar extensión (Solo JPG, JPEG, PNG, IMG solicitado por user)
                        if (in_array($ext, ['jpg', 'jpeg', 'png', 'img'])) {
                            $new_name = $ticket_id . '_' . $key . '.' . $ext;
                            $dest = $upload_dir . $new_name;
                            
                            if (move_uploaded_file($tmp_name, $dest)) {
                                $adjuntos_nombres[] = $new_name;
                                // Adjuntar al correo
                                $mail->addAttachment($dest, $name);
                            }
                        }
                    }
                }
            }

            // Actualizar registro en BD con los nombres de los adjuntos
            if (!empty($adjuntos_nombres)) {
                $adjuntos_json = json_encode($adjuntos_nombres);
                $sql_update = "UPDATE tickets_asistencia SET adjuntos = ? WHERE id = ?";
                $stmt_upd = $conn->prepare($sql_update);
                $stmt_upd->bind_param("si", $adjuntos_json, $ticket_id_db);
                $stmt_upd->execute();
                $stmt_upd->close();
            }

            $mail->send();
            $email_enviado = true;
        } catch (Exception $e) {
            error_log("Error enviando email: " . $e->getMessage());
            $email_enviado = false;
        }

        $respuesta['success'] = true;
        $respuesta['message'] = "Ticket #$ticket_id creado exitosamente. Nos pondremos en contacto contigo pronto.";
        $respuesta['ticket_id'] = $ticket_id;
        $respuesta['email_enviado'] = $email_enviado;
    } else {
        throw new Exception('Error al guardar el ticket en la base de datos: ' . $stmt->error);
    }
} catch (Exception $e) {
    $respuesta['success'] = false;
    $respuesta['message'] = 'Error al crear el ticket. Por favor, intenta nuevamente.';
    $respuesta['error'] = $e->getMessage();
    $respuesta['error_detail'] = $e->getFile() . ':' . $e->getLine();
    error_log("Error en enviar_ticket_office365.php: " . $e->getMessage() . " en " . $e->getFile() . " línea " . $e->getLine());
} catch (Error $e) {
    $respuesta['success'] = false;
    $respuesta['message'] = 'Error fatal al crear el ticket.';
    $respuesta['error'] = $e->getMessage();
    $respuesta['error_detail'] = $e->getFile() . ':' . $e->getLine();
    error_log("Error fatal en enviar_ticket_office365.php: " . $e->getMessage() . " en " . $e->getFile() . " línea " . $e->getLine());
}

// Devolver respuesta JSON
header('Content-Type: application/json');
echo json_encode($respuesta);

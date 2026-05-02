<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, X-API-KEY');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

use PHPMailer\PHPMailer\PHPMailer;
use PHPMailer\PHPMailer\Exception;

require_once __DIR__ . '/../vendor/autoload.php';

$secretsPath = __DIR__ . '/secret.php';
$secrets = file_exists($secretsPath) ? (include $secretsPath) : [];

$apiToken = trim((string)($secrets['mail_bridge_token'] ?? ''));
$headerToken = $_SERVER['HTTP_X_API_KEY'] ?? '';
if ($apiToken === '') {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'error' => 'mail_bridge_token no configurado en secret.php'
    ], JSON_UNESCAPED_UNICODE);
    exit;
}
if ($apiToken !== '' && $headerToken !== $apiToken) {
    http_response_code(401);
    echo json_encode(['success' => false, 'error' => 'Unauthorized'], JSON_UNESCAPED_UNICODE);
    exit;
}

$raw = file_get_contents('php://input');
$payload = json_decode($raw, true);
if (!is_array($payload)) {
    http_response_code(400);
    echo json_encode(['success' => false, 'error' => 'JSON invalido'], JSON_UNESCAPED_UNICODE);
    exit;
}

$toEmail = trim((string)($payload['toEmail'] ?? ''));
$subject = trim((string)($payload['subject'] ?? 'Confirmacion de asignacion de equipo TI'));
$html = (string)($payload['html'] ?? '');
$pdfBase64 = (string)($payload['pdfBase64'] ?? '');
$attachmentFileName = trim((string)($payload['attachmentFileName'] ?? 'acta_asignacion.pdf'));

if ($toEmail === '' || $html === '' || $pdfBase64 === '') {
    http_response_code(400);
    echo json_encode([
        'success' => false,
        'error' => 'Faltan datos requeridos (toEmail, html, pdfBase64).'
    ], JSON_UNESCAPED_UNICODE);
    exit;
}

$pdfBinary = base64_decode($pdfBase64, true);
if ($pdfBinary === false) {
    http_response_code(400);
    echo json_encode(['success' => false, 'error' => 'pdfBase64 invalido'], JSON_UNESCAPED_UNICODE);
    exit;
}

// Config SMTP (ideal: desde secret.php)
$smtp = $secrets['smtp'] ?? [];
$smtpHost = $smtp['host'] ?? 'smtp.office365.com';
$smtpPort = (int)($smtp['port'] ?? 587);
$smtpUser = $smtp['username'] ?? 'reclutamiento@promsan.com.mx';
$smtpPass = trim((string)($smtp['password'] ?? ''));
$smtpFrom = $smtp['from_email'] ?? $smtpUser;
$smtpFromName = $smtp['from_name'] ?? 'Promsan TI';
$smtpSecureRaw = strtolower((string)($smtp['secure'] ?? ($smtp['encryption'] ?? 'tls')));
$smtpSecure = $smtpSecureRaw === 'ssl'
    ? PHPMailer::ENCRYPTION_SMTPS
    : PHPMailer::ENCRYPTION_STARTTLS;
$smtpDebug = isset($smtp['debug']) ? (int)$smtp['debug'] : 0;

if ($smtpPass === '') {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'error' => 'SMTP password no configurado en secret.php'
    ], JSON_UNESCAPED_UNICODE);
    exit;
}

try {
    $mail = new PHPMailer(true);
    $mail->CharSet = 'UTF-8';
    $mail->isSMTP();
    $mail->Host = $smtpHost;
    $mail->SMTPAuth = true;
    $mail->Username = $smtpUser;
    $mail->Password = $smtpPass;
    $mail->SMTPSecure = $smtpSecure;
    $mail->Port = $smtpPort;
    $mail->SMTPDebug = $smtpDebug;
    $mail->Debugoutput = 'error_log';

    $mail->setFrom($smtpFrom, $smtpFromName);
    $mail->addAddress($toEmail);
    // Opcional: copia a TI
    // $mail->addBCC('ti@promsan.com.mx', 'TI Promsan');

    $mail->isHTML(true);
    $mail->Subject = $subject;
    $mail->Body = $html;
    $mail->addStringAttachment($pdfBinary, $attachmentFileName, 'base64', 'application/pdf');
    $mail->send();

    echo json_encode([
        'success' => true,
        'message' => 'Correo enviado correctamente'
    ], JSON_UNESCAPED_UNICODE);
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'error' => 'Error enviando correo SMTP',
        'details' => $mail->ErrorInfo
    ], JSON_UNESCAPED_UNICODE);
}


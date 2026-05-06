<?php
// Configuración de conexión para la base de datos de Reclutamiento (Hostinger)
$host_reclutamiento = 'localhost';
$db_reclutamiento   = 'u714254685_reclutamiento';
$user_reclutamiento = 'u714254685_reclutamiento';
$pass_reclutamiento = 'u#l{%dJ2C941';
$charset_reclutamiento = 'utf8mb4';

$dsn_reclutamiento = "mysql:host=$host_reclutamiento;dbname=$db_reclutamiento;charset=$charset_reclutamiento";
$options_reclutamiento = [
    PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    PDO::ATTR_EMULATE_PREPARES   => false,
];

try {
     $pdo_reclutamiento = new PDO($dsn_reclutamiento, $user_reclutamiento, $pass_reclutamiento, $options_reclutamiento);
} catch (\PDOException $e) {
     $error_reclutamiento = $e;
     error_log("Error de conexión a Reclutamiento: " . $e->getMessage());
}

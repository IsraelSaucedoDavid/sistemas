<?php
// ARCHIVO DE DIAGNÓSTICO DE BASE DE DATOS
// Úsalo para saber los nombres exactos de las tablas y columnas

if (file_exists('bd_reclutamiento.php')) {
    require_once 'bd_reclutamiento.php';
} elseif (file_exists('../bd_reclutamiento.php')) {
    require_once '../bd_reclutamiento.php';
} else {
    die("ERROR: No se encontró bd_reclutamiento.php");
}

header('Content-Type: text/plain; charset=utf-8');

try {
    echo "=== DIAGNÓSTICO DE SISTEMA ===\n\n";

    echo "1. LISTA DE TABLAS EN LA BASE DE DATOS:\n";
    $stmt = $pdo_reclutamiento->query("SHOW TABLES");
    $tables = $stmt->fetchAll(PDO::FETCH_COLUMN);
    foreach ($tables as $table) {
        echo "   - $table\n";
    }

    echo "\n2. BUSCANDO TABLA DE TICKETS...\n";
    $tabla_encontrada = '';
    foreach ($tables as $table) {
        if (stripos($table, 'ticket') !== false) {
            $tabla_encontrada = $table;
            echo "   [!] Se encontró la tabla: $table\n";
            
            echo "   --- ESTRUCTURA DE '$table' ---\n";
            $stmtCol = $pdo_reclutamiento->query("DESCRIBE $table");
            while ($col = $stmtCol->fetch(PDO::FETCH_ASSOC)) {
                echo "       * " . $col['Field'] . " (" . $col['Type'] . ")\n";
            }
        }
    }

    if (empty($tabla_encontrada)) {
        echo "   [X] No se encontró ninguna tabla con la palabra 'ticket'.\n";
    }

    echo "\n3. BUSCANDO TABLAS DE HISTORIAL/EVALUACIÓN...\n";
    foreach ($tables as $table) {
        if (stripos($table, 'historial') !== false || stripos($table, 'evalua') !== false) {
            echo "   [!] Se encontró: $table\n";
        }
    }

} catch (Exception $e) {
    echo "\n[ERROR CRÍTICO]: " . $e->getMessage();
}

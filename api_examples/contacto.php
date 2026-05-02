<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, X-API-KEY');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

// DEBUG temporal (quitalo cuando quede estable)
ini_set('display_errors', 1);
ini_set('display_startup_errors', 1);
error_reporting(E_ALL);

// Seguridad por token simple (opcional; descomenta si la usaras)
/*
$apiToken = 'cambia_este_token';
$headerToken = $_SERVER['HTTP_X_API_KEY'] ?? '';
if ($apiToken !== '' && $headerToken !== $apiToken) {
    http_response_code(401);
    echo json_encode(['success' => false, 'error' => 'Unauthorized'], JSON_UNESCAPED_UNICODE);
    exit;
}
*/

// Busca tu archivo de conexion en rutas comunes.
$configCandidates = [
    __DIR__ . '/bd_reclutamiento.php',
    __DIR__ . '/../config/bd_reclutamiento.php',
    __DIR__ . '/../../config/bd_reclutamiento.php',
];

$configLoaded = false;
foreach ($configCandidates as $cfg) {
    if (file_exists($cfg)) {
        require_once $cfg;
        $configLoaded = true;
        break;
    }
}

if (!$configLoaded) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'error' => 'No se encontro bd_reclutamiento.php en rutas esperadas'
    ], JSON_UNESCAPED_UNICODE);
    exit;
}

if (!isset($pdo_reclutamiento) || !$pdo_reclutamiento instanceof PDO) {
    $msg = isset($error_reclutamiento) && $error_reclutamiento ? $error_reclutamiento->getMessage() : 'Conexion no disponible';
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'error' => 'No hay conexion disponible a reclutamiento',
        'details' => $msg,
    ], JSON_UNESCAPED_UNICODE);
    exit;
}

function pickExistingColumn(array $availableColumns, array $candidates): ?string
{
    foreach ($candidates as $name) {
        if (in_array($name, $availableColumns, true)) {
            return $name;
        }
    }
    return null;
}

$q = trim($_GET['q'] ?? '');
if (strlen($q) < 2) {
    echo json_encode([
        'success' => true,
        'data' => [],
        'total' => 0
    ], JSON_UNESCAPED_UNICODE);
    exit;
}

$tokens = preg_split('/\s+/', $q) ?: [];
$tokens = array_values(array_filter($tokens, static fn($t) => strlen(trim($t)) >= 2));
if (count($tokens) === 0) {
    echo json_encode([
        'success' => true,
        'data' => [],
        'total' => 0
    ], JSON_UNESCAPED_UNICODE);
    exit;
}

try {
    $colStmt = $pdo_reclutamiento->query("DESCRIBE contacto");
    $colsRaw = $colStmt->fetchAll(PDO::FETCH_ASSOC);
    $columns = array_map(static fn($r) => $r['Field'], $colsRaw);

    $idCol = pickExistingColumn($columns, ['id', 'id_contacto', 'contacto_id']);
    $nameCol = pickExistingColumn($columns, [
        'nombrecontacto', 'nombre', 'nombre_completo', 'full_name', 'name'
    ]);
    $apellidoPaternoCol = pickExistingColumn($columns, ['apellido_paterno']);
    $apellidoMaternoCol = pickExistingColumn($columns, ['apellido_materno']);
    $emailCol = pickExistingColumn($columns, ['correo', 'email', 'correo_electronico']);
    $deptCol = pickExistingColumn($columns, ['departamento', 'area', 'depto', 'nombre_planta']);
    $empCodeCol = pickExistingColumn($columns, ['numero_empleado', 'employee_code', 'codigo_empleado']);
    $estatusCol = pickExistingColumn($columns, ['id_estatus', 'estatus', 'status', 'activo']);
    $plantaCol = pickExistingColumn($columns, ['id_planta']);
    $reingresoCol = pickExistingColumn($columns, ['es_reingreso']);

    if ($nameCol === null) {
        http_response_code(500);
        echo json_encode([
            'success' => false,
            'error' => 'La tabla contacto no tiene columna de nombre compatible'
        ], JSON_UNESCAPED_UNICODE);
        exit;
    }

    $selectParts = [];
    $selectParts[] = ($idCol !== null ? "$idCol AS id" : "NULL AS id");
    $selectParts[] = "$nameCol AS nombrecontacto";
    $selectParts[] = ($apellidoPaternoCol !== null ? "$apellidoPaternoCol AS apellido_paterno" : "NULL AS apellido_paterno");
    $selectParts[] = ($apellidoMaternoCol !== null ? "$apellidoMaternoCol AS apellido_materno" : "NULL AS apellido_materno");
    $selectParts[] = ($emailCol !== null ? "$emailCol AS correo" : "NULL AS correo");
    $selectParts[] = ($deptCol !== null ? "$deptCol AS departamento" : "NULL AS departamento");
    $selectParts[] = ($empCodeCol !== null ? "$empCodeCol AS numero_empleado" : "NULL AS numero_empleado");
    $selectParts[] = ($estatusCol !== null ? "$estatusCol AS id_estatus" : "NULL AS id_estatus");
    $selectParts[] = ($plantaCol !== null ? "$plantaCol AS id_planta" : "NULL AS id_planta");
    $selectParts[] = ($reingresoCol !== null ? "$reingresoCol AS es_reingreso" : "NULL AS es_reingreso");

    $params = [];
    $tokenGroups = [];
    $addLike = static function (string $column, string $token) use (&$params): string {
        $placeholder = ':q' . (count($params) + 1);
        $params[$placeholder] = "%$token%";
        return "$column LIKE $placeholder";
    };
    $nameExpr = "$nameCol";
    if ($apellidoPaternoCol !== null || $apellidoMaternoCol !== null) {
        $nameExpr = "CONCAT_WS(' ', $nameCol" .
            ($apellidoPaternoCol !== null ? ", $apellidoPaternoCol" : "") .
            ($apellidoMaternoCol !== null ? ", $apellidoMaternoCol" : "") .
            ")";
    }

    foreach ($tokens as $token) {
        $orParts = [];
        $orParts[] = $addLike($nameExpr, $token);
        $orParts[] = $addLike($nameCol, $token);
        if ($idCol !== null) $orParts[] = $addLike("CAST($idCol AS CHAR)", $token);
        if ($apellidoPaternoCol !== null) $orParts[] = $addLike($apellidoPaternoCol, $token);
        if ($apellidoMaternoCol !== null) $orParts[] = $addLike($apellidoMaternoCol, $token);
        if ($emailCol !== null) $orParts[] = $addLike($emailCol, $token);
        if ($empCodeCol !== null) $orParts[] = $addLike($empCodeCol, $token);
        $tokenGroups[] = '(' . implode(' OR ', $orParts) . ')';
    }

    $fullContainsPlaceholder = ':full_contains';
    $fullStartsPlaceholder = ':full_starts';
    $fullEqualsPlaceholder = ':full_equals';
    $params[$fullContainsPlaceholder] = "%$q%";
    $params[$fullStartsPlaceholder] = "$q%";
    $params[$fullEqualsPlaceholder] = $q;

    $relevanceExpr = "(" .
        "CASE WHEN $nameExpr = $fullEqualsPlaceholder THEN 120 ELSE 0 END + " .
        "CASE WHEN $nameExpr LIKE $fullStartsPlaceholder THEN 80 ELSE 0 END + " .
        "CASE WHEN $nameExpr LIKE $fullContainsPlaceholder THEN 40 ELSE 0 END" .
    ")";

    $sql = "SELECT " . implode(", ", $selectParts) .
           ", $relevanceExpr AS relevance_score " .
           " FROM contacto WHERE (" . implode(" AND ", $tokenGroups) . ")";

    // Si existe id_estatus, filtramos contratados por defecto (3)
    if ($estatusCol === 'id_estatus') {
        $sql .= " AND $estatusCol = 3";
    }

    $orderCol = $apellidoPaternoCol ?? $nameCol;
    $sql .= " ORDER BY relevance_score DESC, $orderCol ASC, $nameCol ASC LIMIT 120";

    $stmt = $pdo_reclutamiento->prepare($sql);
    $stmt->execute($params);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    echo json_encode([
        'success' => true,
        'data' => $rows,
        'total' => count($rows)
    ], JSON_UNESCAPED_UNICODE);
} catch (Throwable $e) {
    error_log('contacto.php error: ' . $e->getMessage());
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'error' => 'Server error',
        'details' => $e->getMessage()
    ], JSON_UNESCAPED_UNICODE);
}

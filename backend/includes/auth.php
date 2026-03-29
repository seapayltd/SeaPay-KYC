<?php
/**
 * Authentication and utility helpers.
 */

require_once __DIR__ . '/db.php';

function uuid(): string {
    return sprintf('%04x%04x-%04x-%04x-%04x-%04x%04x%04x',
        mt_rand(0, 0xffff), mt_rand(0, 0xffff), mt_rand(0, 0xffff),
        mt_rand(0, 0x0fff) | 0x4000, mt_rand(0, 0x3fff) | 0x8000,
        mt_rand(0, 0xffff), mt_rand(0, 0xffff), mt_rand(0, 0xffff));
}

function generateToken(): string {
    return bin2hex(random_bytes(32));
}

function generateWorkspaceCode(): string {
    $chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // No I/O/0/1 confusion
    $code = '';
    for ($i = 0; $i < WORKSPACE_CODE_LENGTH; $i++) {
        $code .= $chars[random_int(0, strlen($chars) - 1)];
    }
    return $code;
}

/**
 * Authenticate request via Bearer token.
 * Returns [workspace_id, agent_id, agent_name] or sends 401.
 */
function authenticate(): array {
    $header = $_SERVER['HTTP_AUTHORIZATION'] ?? '';
    if (!preg_match('/Bearer\s+(\S+)/', $header, $m)) {
        jsonError(401, 'Missing or invalid Authorization header');
    }
    $token = $m[1];

    $db = getDB();
    $stmt = $db->prepare("SELECT wa.workspace_id, wa.agent_id, wa.agent_name, wa.is_active
                          FROM workspace_agents wa WHERE wa.token = ?");
    $stmt->execute([$token]);
    $agent = $stmt->fetch();

    if (!$agent) { jsonError(401, 'Invalid token'); }
    if (!$agent['is_active']) { jsonError(403, 'Agent deactivated from workspace'); }

    // Update last activity
    $db->prepare("UPDATE workspace_agents SET last_sync = NOW() WHERE token = ?")->execute([$token]);

    return $agent;
}

function jsonResponse(array $data, int $code = 200): never {
    http_response_code($code);
    header('Content-Type: application/json');
    echo json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE);
    exit;
}

function jsonError(int $code, string $message): never {
    jsonResponse(['error' => $message], $code);
}

function getJSON(): array {
    $raw = file_get_contents('php://input');
    if (strlen($raw) > MAX_SNAPSHOT_SIZE) {
        jsonError(413, 'Payload too large');
    }
    $data = json_decode($raw, true);
    if ($data === null && json_last_error() !== JSON_ERROR_NONE) {
        jsonError(400, 'Invalid JSON: ' . json_last_error_msg());
    }
    return $data ?? [];
}

function logActivity(string $workspaceId, string $agentId, string $agentName,
                     string $action, string $entityType = '', string $entityName = '', ?string $detail = null): void {
    $db = getDB();
    $stmt = $db->prepare("INSERT INTO activity_log (id, workspace_id, agent_id, agent_name, action, entity_type, entity_name, detail)
                          VALUES (?, ?, ?, ?, ?, ?, ?, ?)");
    $stmt->execute([uuid(), $workspaceId, $agentId, $agentName, $action, $entityType, $entityName, $detail]);
}

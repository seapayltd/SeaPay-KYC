<?php
/**
 * OceanCheck Agent Backup API — Server-side data redundancy
 *
 * POST  /api/backup.php?action=push    — Push full backup (vessels + checks)
 * GET   /api/backup.php?action=pull    — Pull latest backup
 * GET   /api/backup.php?action=status  — Check backup status
 */

require_once __DIR__ . '/../includes/db.php';

header('Content-Type: application/json');
$action = $_GET['action'] ?? '';

// Auth: agent_id in header or body — no workspace token needed
function authenticateAgent() {
    $agentId = $_SERVER['HTTP_X_AGENT_ID'] ?? null;
    $apiKey = $_SERVER['HTTP_X_API_KEY'] ?? null;
    if (!$agentId) {
        jsonError(401, 'X-Agent-Id header required');
    }
    return ['agent_id' => $agentId, 'api_key' => $apiKey];
}

// Ensure backup table exists
function initBackupSchema() {
    $db = getDB();
    $db->exec("CREATE TABLE IF NOT EXISTS agent_backups (
        id VARCHAR(36) PRIMARY KEY,
        agent_id VARCHAR(36) NOT NULL,
        agent_name VARCHAR(100) DEFAULT '',
        vessels_json LONGTEXT,
        checks_json LONGTEXT,
        vessel_count INT DEFAULT 0,
        check_count INT DEFAULT 0,
        backup_version INT NOT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_agent_version (agent_id, backup_version DESC),
        INDEX idx_agent_time (agent_id, created_at DESC)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
}

switch ($action) {

    // ─── PUSH BACKUP ───
    case 'push':
        $auth = authenticateAgent();
        $data = getJSON();

        $vessels = $data['vessels'] ?? null;
        $checks = $data['checks'] ?? null;
        $agentName = trim($data['agent_name'] ?? '');

        // Safety: reject empty backup if server has non-empty data
        $vesselCount = is_array($vessels) ? count($vessels) : 0;
        $checkCount = is_array($checks) ? count($checks) : 0;

        if ($vesselCount === 0 && $checkCount === 0) {
            jsonError(400, 'Empty backup rejected — refusing to overwrite server data with empty payload');
        }

        $db = getDB();
        initBackupSchema();

        // Get next version
        $stmt = $db->prepare("SELECT COALESCE(MAX(backup_version), 0) + 1 as next_ver FROM agent_backups WHERE agent_id = ?");
        $stmt->execute([$auth['agent_id']]);
        $nextVersion = (int)$stmt->fetch()['next_ver'];

        $backupId = uuid();
        $vesselsJson = $vessels !== null ? json_encode($vessels, JSON_UNESCAPED_UNICODE) : null;
        $checksJson = $checks !== null ? json_encode($checks, JSON_UNESCAPED_UNICODE) : null;

        $db->prepare("INSERT INTO agent_backups (id, agent_id, agent_name, vessels_json, checks_json, vessel_count, check_count, backup_version)
                      VALUES (?, ?, ?, ?, ?, ?, ?, ?)")
           ->execute([$backupId, $auth['agent_id'], $agentName, $vesselsJson, $checksJson, $vesselCount, $checkCount, $nextVersion]);

        // Prune old backups (keep last 20 per agent)
        $pruneThreshold = max(0, $nextVersion - 20);
        $db->prepare("DELETE FROM agent_backups WHERE agent_id = ? AND backup_version <= ?")
           ->execute([$auth['agent_id'], $pruneThreshold]);

        jsonResponse([
            'backup_id' => $backupId,
            'backup_version' => $nextVersion,
            'vessel_count' => $vesselCount,
            'check_count' => $checkCount,
        ], 201);
        break;

    // ─── PULL LATEST BACKUP ───
    case 'pull':
        $auth = authenticateAgent();

        $db = getDB();
        initBackupSchema();

        $stmt = $db->prepare("SELECT id, agent_name, vessels_json, checks_json, vessel_count, check_count, backup_version, created_at
                              FROM agent_backups WHERE agent_id = ?
                              ORDER BY backup_version DESC LIMIT 1");
        $stmt->execute([$auth['agent_id']]);
        $backup = $stmt->fetch();

        if (!$backup) {
            jsonResponse(['backup' => null, 'message' => 'No backup found for this agent']);
            break;
        }

        $backup['vessels'] = $backup['vessels_json'] ? json_decode($backup['vessels_json'], true) : [];
        $backup['checks'] = $backup['checks_json'] ? json_decode($backup['checks_json'], true) : [];
        unset($backup['vessels_json'], $backup['checks_json']);

        jsonResponse(['backup' => $backup]);
        break;

    // ─── BACKUP STATUS ───
    case 'status':
        $auth = authenticateAgent();

        $db = getDB();
        initBackupSchema();

        $stmt = $db->prepare("SELECT backup_version, vessel_count, check_count, created_at
                              FROM agent_backups WHERE agent_id = ?
                              ORDER BY backup_version DESC LIMIT 1");
        $stmt->execute([$auth['agent_id']]);
        $latest = $stmt->fetch();

        jsonResponse([
            'has_backup' => $latest !== false,
            'latest_version' => $latest ? (int)$latest['backup_version'] : 0,
            'vessel_count' => $latest ? (int)$latest['vessel_count'] : 0,
            'check_count' => $latest ? (int)$latest['check_count'] : 0,
            'last_backup' => $latest ? $latest['created_at'] : null,
        ]);
        break;

    default:
        jsonError(400, 'Unknown action. Use: push, pull, status');
}

<?php
/**
 * OceanCheck Collaboration API — Data Sync
 *
 * POST  /api/sync.php?action=push    — Push local changes (new snapshot)
 * GET   /api/sync.php?action=pull    — Pull latest snapshot
 * GET   /api/sync.php?action=status  — Check if new data available (lightweight)
 */

require_once __DIR__ . '/../includes/auth.php';

header('Content-Type: application/json');
$action = $_GET['action'] ?? '';

switch ($action) {

    // ─── PUSH (upload snapshot) ───
    case 'push':
        $auth = authenticate();
        $data = getJSON();

        $vessels = $data['vessels'] ?? null;
        $checks = $data['checks'] ?? null;
        $vesselId = $data['vessel_id'] ?? null;

        if ($vessels === null && $checks === null) {
            jsonError(400, 'Nothing to sync — provide vessels and/or checks');
        }

        $db = getDB();

        // Ensure vessel_id column exists (auto-migrate)
        try { $db->exec("ALTER TABLE sync_snapshots ADD COLUMN vessel_id VARCHAR(36) DEFAULT NULL"); } catch (Exception $e) { /* already exists */ }
        try { $db->exec("ALTER TABLE sync_snapshots ADD COLUMN vessel_name VARCHAR(100) DEFAULT ''"); } catch (Exception $e) { /* already exists */ }

        // Get next version number
        $stmt = $db->prepare("SELECT COALESCE(MAX(version), 0) + 1 as next_ver FROM sync_snapshots WHERE workspace_id = ?");
        $stmt->execute([$auth['workspace_id']]);
        $nextVersion = (int)$stmt->fetch()['next_ver'];

        $snapshotId = uuid();
        $vesselsJson = $vessels !== null ? json_encode($vessels, JSON_UNESCAPED_UNICODE) : null;
        $checksJson = $checks !== null ? json_encode($checks, JSON_UNESCAPED_UNICODE) : null;
        $vesselName = '';
        if ($vesselId && is_array($vessels) && count($vessels) > 0) {
            $vesselName = $vessels[0]['name'] ?? '';
        }

        $db->prepare("INSERT INTO sync_snapshots (id, workspace_id, agent_id, agent_name, version, vessels_json, checks_json, vessel_id, vessel_name)
                      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)")
           ->execute([$snapshotId, $auth['workspace_id'], $auth['agent_id'], $auth['agent_name'], $nextVersion, $vesselsJson, $checksJson, $vesselId, $vesselName]);

        // Log activity for significant changes
        $vesselCount = is_array($vessels) ? count($vessels) : 0;
        $checkCount = is_array($checks) ? count($checks) : 0;
        logActivity($auth['workspace_id'], $auth['agent_id'], $auth['agent_name'],
                    'data_synced', 'sync', "v{$nextVersion}",
                    "{$vesselCount} vessels, {$checkCount} checks");

        // Prune old snapshots (keep last 50)
        $db->prepare("DELETE FROM sync_snapshots WHERE workspace_id = ? AND version <= (SELECT * FROM (SELECT COALESCE(MAX(version), 0) - 50 FROM sync_snapshots WHERE workspace_id = ?) AS sub)")
           ->execute([$auth['workspace_id'], $auth['workspace_id']]);

        jsonResponse([
            'version' => $nextVersion,
            'snapshot_id' => $snapshotId,
        ], 201);
        break;

    // ─── PULL (download latest or specific version) ───
    case 'pull':
        $auth = authenticate();
        $sinceVersion = (int)($_GET['since'] ?? 0);
        $vesselIdFilter = $_GET['vessel_id'] ?? null;

        $db = getDB();

        if ($vesselIdFilter) {
            // Pull latest snapshot for a specific vessel
            $stmt = $db->prepare("SELECT id, agent_id, agent_name, version, vessels_json, checks_json, created_at
                                  FROM sync_snapshots WHERE workspace_id = ? AND vessel_id = ?
                                  ORDER BY version DESC LIMIT 1");
            $stmt->execute([$auth['workspace_id'], $vesselIdFilter]);
            $snapshot = $stmt->fetch();
            if (!$snapshot) jsonResponse(['snapshot' => null, 'version' => 0]);
            $snapshot['vessels'] = $snapshot['vessels_json'] ? json_decode($snapshot['vessels_json'], true) : null;
            $snapshot['checks'] = $snapshot['checks_json'] ? json_decode($snapshot['checks_json'], true) : null;
            unset($snapshot['vessels_json'], $snapshot['checks_json']);
            jsonResponse(['snapshot' => $snapshot, 'version' => (int)$snapshot['version']]);
        } elseif ($sinceVersion > 0) {
            // Get all snapshots since the given version (for incremental merge)
            $stmt = $db->prepare("SELECT id, agent_id, agent_name, version, vessels_json, checks_json, created_at
                                  FROM sync_snapshots WHERE workspace_id = ? AND version > ?
                                  ORDER BY version ASC LIMIT 20");
            $stmt->execute([$auth['workspace_id'], $sinceVersion]);
            $snapshots = $stmt->fetchAll();

            foreach ($snapshots as &$s) {
                $s['vessels'] = $s['vessels_json'] ? json_decode($s['vessels_json'], true) : null;
                $s['checks'] = $s['checks_json'] ? json_decode($s['checks_json'], true) : null;
                unset($s['vessels_json'], $s['checks_json']);
            }

            jsonResponse([
                'snapshots' => $snapshots,
                'count' => count($snapshots),
            ]);
        } else {
            // Get the latest snapshot
            $stmt = $db->prepare("SELECT id, agent_id, agent_name, version, vessels_json, checks_json, created_at
                                  FROM sync_snapshots WHERE workspace_id = ?
                                  ORDER BY version DESC LIMIT 1");
            $stmt->execute([$auth['workspace_id']]);
            $snapshot = $stmt->fetch();

            if (!$snapshot) jsonResponse(['snapshot' => null, 'version' => 0]);

            $snapshot['vessels'] = $snapshot['vessels_json'] ? json_decode($snapshot['vessels_json'], true) : null;
            $snapshot['checks'] = $snapshot['checks_json'] ? json_decode($snapshot['checks_json'], true) : null;
            unset($snapshot['vessels_json'], $snapshot['checks_json']);

            jsonResponse([
                'snapshot' => $snapshot,
                'version' => (int)$snapshot['version'],
            ]);
        }
        break;

    // ─── STATUS (lightweight check) ───
    case 'status':
        $auth = authenticate();
        $localVersion = (int)($_GET['local_version'] ?? 0);

        $db = getDB();
        $stmt = $db->prepare("SELECT COALESCE(MAX(version), 0) as latest FROM sync_snapshots WHERE workspace_id = ?");
        $stmt->execute([$auth['workspace_id']]);
        $latest = (int)$stmt->fetch()['latest'];

        $stmt = $db->prepare("SELECT COUNT(*) as cnt FROM workspace_agents WHERE workspace_id = ? AND is_active = 1");
        $stmt->execute([$auth['workspace_id']]);
        $agentCount = (int)$stmt->fetch()['cnt'];

        jsonResponse([
            'latest_version' => $latest,
            'has_updates' => $latest > $localVersion,
            'updates_available' => max(0, $latest - $localVersion),
            'active_agents' => $agentCount,
        ]);
        break;

    default:
        jsonError(400, 'Unknown action. Use: push, pull, status');
}

<?php
/**
 * OceanCheck Collaboration API — Workspace Management
 *
 * POST   /api/workspace.php?action=create   — Create a new workspace
 * POST   /api/workspace.php?action=join     — Join with workspace code
 * GET    /api/workspace.php?action=info      — Get workspace info + agents
 * POST   /api/workspace.php?action=leave     — Leave workspace
 * POST   /api/workspace.php?action=update    — Update workspace name/scenario
 */

require_once __DIR__ . '/../includes/auth.php';

header('Content-Type: application/json');
$action = $_GET['action'] ?? '';

switch ($action) {

    // ─── CREATE WORKSPACE ───
    case 'create':
        $data = getJSON();
        $name = trim($data['name'] ?? '');
        $agentId = trim($data['agent_id'] ?? '');
        $agentName = trim($data['agent_name'] ?? '');
        $agentOrg = trim($data['agent_org'] ?? '');
        $agentRole = trim($data['agent_role'] ?? '');

        if (!$name) jsonError(400, 'Workspace name required');
        if (!$agentId || !$agentName) jsonError(400, 'Agent ID and name required');

        $db = getDB();
        initSchema();

        $workspaceId = uuid();
        $code = generateWorkspaceCode();
        $token = generateToken();

        $db->beginTransaction();
        try {
            $db->prepare("INSERT INTO workspaces (id, name, code, created_by) VALUES (?, ?, ?, ?)")
               ->execute([$workspaceId, $name, $code, $agentId]);

            $db->prepare("INSERT INTO workspace_agents (id, workspace_id, agent_id, agent_name, agent_org, agent_role, token)
                          VALUES (?, ?, ?, ?, ?, ?, ?)")
               ->execute([uuid(), $workspaceId, $agentId, $agentName, $agentOrg, $agentRole, $token]);

            logActivity($workspaceId, $agentId, $agentName, 'workspace_created', 'workspace', $name);
            $db->commit();
        } catch (Exception $e) {
            $db->rollBack();
            jsonError(500, 'Failed to create workspace');
        }

        jsonResponse([
            'workspace_id' => $workspaceId,
            'code' => $code,
            'name' => $name,
            'token' => $token,
        ], 201);
        break;

    // ─── JOIN WORKSPACE ───
    case 'join':
        $data = getJSON();
        $code = strtoupper(trim($data['code'] ?? ''));
        $agentId = trim($data['agent_id'] ?? '');
        $agentName = trim($data['agent_name'] ?? '');
        $agentOrg = trim($data['agent_org'] ?? '');
        $agentRole = trim($data['agent_role'] ?? '');

        if (!$code) jsonError(400, 'Workspace code required');
        if (!$agentId || !$agentName) jsonError(400, 'Agent ID and name required');

        $db = getDB();
        initSchema();

        $stmt = $db->prepare("SELECT id, name FROM workspaces WHERE code = ?");
        $stmt->execute([$code]);
        $workspace = $stmt->fetch();
        if (!$workspace) jsonError(404, 'Workspace not found. Check the code.');

        // Check agent limit
        $stmt = $db->prepare("SELECT COUNT(*) as cnt FROM workspace_agents WHERE workspace_id = ? AND is_active = 1");
        $stmt->execute([$workspace['id']]);
        if ($stmt->fetch()['cnt'] >= MAX_WORKSPACE_AGENTS) jsonError(409, 'Workspace is full');

        // Check if already joined
        $stmt = $db->prepare("SELECT token, is_active FROM workspace_agents WHERE workspace_id = ? AND agent_id = ?");
        $stmt->execute([$workspace['id'], $agentId]);
        $existing = $stmt->fetch();

        if ($existing) {
            if ($existing['is_active']) {
                jsonResponse(['workspace_id' => $workspace['id'], 'name' => $workspace['name'], 'token' => $existing['token'], 'code' => $code]);
            }
            // Reactivate
            $token = generateToken();
            $db->prepare("UPDATE workspace_agents SET is_active = 1, token = ?, agent_name = ? WHERE workspace_id = ? AND agent_id = ?")
               ->execute([$token, $agentName, $workspace['id'], $agentId]);
        } else {
            $token = generateToken();
            $db->prepare("INSERT INTO workspace_agents (id, workspace_id, agent_id, agent_name, agent_org, agent_role, token)
                          VALUES (?, ?, ?, ?, ?, ?, ?)")
               ->execute([uuid(), $workspace['id'], $agentId, $agentName, $agentOrg, $agentRole, $token]);
        }

        logActivity($workspace['id'], $agentId, $agentName, 'agent_joined', 'agent', $agentName);

        jsonResponse([
            'workspace_id' => $workspace['id'],
            'name' => $workspace['name'],
            'token' => $token,
            'code' => $code,
        ]);
        break;

    // ─── WORKSPACE INFO ───
    case 'info':
        $auth = authenticate();

        $db = getDB();
        $stmt = $db->prepare("SELECT id, name, code, created_at FROM workspaces WHERE id = ?");
        $stmt->execute([$auth['workspace_id']]);
        $workspace = $stmt->fetch();
        if (!$workspace) jsonError(404, 'Workspace not found');

        $stmt = $db->prepare("SELECT agent_id, agent_name, agent_org, agent_role, joined_at, last_sync, is_active
                              FROM workspace_agents WHERE workspace_id = ? ORDER BY joined_at");
        $stmt->execute([$auth['workspace_id']]);
        $agents = $stmt->fetchAll();
        // Cast MySQL TINYINT to proper boolean for Swift Codable
        foreach ($agents as &$a) { $a['is_active'] = (int)$a['is_active']; }

        $stmt = $db->prepare("SELECT MAX(version) as latest FROM sync_snapshots WHERE workspace_id = ?");
        $stmt->execute([$auth['workspace_id']]);
        $latest = $stmt->fetch()['latest'] ?? 0;

        jsonResponse([
            'workspace' => $workspace,
            'agents' => $agents,
            'latest_version' => (int)$latest,
        ]);
        break;

    // ─── UPDATE WORKSPACE ───
    case 'update':
        $auth = authenticate();
        $data = getJSON();
        $name = trim($data['name'] ?? '');
        $scenario = trim($data['scenario'] ?? '');

        if (!$name) jsonError(400, 'Workspace name required');

        $db = getDB();
        $db->prepare("UPDATE workspaces SET name = ? WHERE id = ?")
           ->execute([$name, $auth['workspace_id']]);

        // Update scenario on all vessels in this workspace if provided
        if ($scenario) {
            $db->prepare("UPDATE workspace_vessels SET scenario = ? WHERE workspace_id = ?")
               ->execute([$scenario, $auth['workspace_id']]);
        }

        logActivity($auth['workspace_id'], $auth['agent_id'], $auth['agent_name'], 'workspace_updated', 'workspace', $name);

        jsonResponse(['ok' => true, 'name' => $name]);
        break;

    // ─── LEAVE WORKSPACE ───
    case 'leave':
        $auth = authenticate();
        $db = getDB();
        $db->prepare("UPDATE workspace_agents SET is_active = 0 WHERE workspace_id = ? AND agent_id = ?")
           ->execute([$auth['workspace_id'], $auth['agent_id']]);
        logActivity($auth['workspace_id'], $auth['agent_id'], $auth['agent_name'], 'agent_left');
        jsonResponse(['ok' => true]);
        break;

    // ─── ADD VESSEL TO WORKSPACE ───
    case 'add_vessel':
        $auth = authenticate();
        $data = getJSON();
        $vesselId = trim($data['vessel_id'] ?? '');
        $vesselName = trim($data['vessel_name'] ?? '');
        $vesselIMO = trim($data['vessel_imo'] ?? '');
        $scenario = trim($data['scenario'] ?? '');

        if (!$vesselId) jsonError(400, 'vessel_id required');

        $db = getDB();
        initSchema(); // ensure workspace_vessels table exists

        // Check if already added
        $stmt = $db->prepare("SELECT id FROM workspace_vessels WHERE workspace_id = ? AND vessel_id = ?");
        $stmt->execute([$auth['workspace_id'], $vesselId]);
        if ($stmt->fetch()) jsonResponse(['ok' => true, 'message' => 'Vessel already in workspace']);

        $db->prepare("INSERT INTO workspace_vessels (id, workspace_id, vessel_id, vessel_name, vessel_imo, scenario, added_by_agent, added_by_name)
                      VALUES (?, ?, ?, ?, ?, ?, ?, ?)")
           ->execute([uuid(), $auth['workspace_id'], $vesselId, $vesselName, $vesselIMO, $scenario, $auth['agent_id'], $auth['agent_name']]);

        logActivity($auth['workspace_id'], $auth['agent_id'], $auth['agent_name'], 'vessel_added', 'vessel', $vesselName);

        // Audit trail
        $db->prepare("INSERT INTO audit_trail (id, workspace_id, vessel_id, agent_id, agent_name, action, entity_type, entity_name)
                      VALUES (?, ?, ?, ?, ?, 'add_vessel', 'vessel', ?)")
           ->execute([uuid(), $auth['workspace_id'], $vesselId, $auth['agent_id'], $auth['agent_name'], $vesselName]);

        jsonResponse(['ok' => true], 201);
        break;

    // ─── REMOVE VESSEL FROM WORKSPACE ───
    case 'remove_vessel':
        $auth = authenticate();
        $data = getJSON();
        $vesselId = trim($data['vessel_id'] ?? '');
        if (!$vesselId) jsonError(400, 'vessel_id required');

        $db = getDB();

        // Get vessel name for audit
        $stmt = $db->prepare("SELECT vessel_name FROM workspace_vessels WHERE workspace_id = ? AND vessel_id = ?");
        $stmt->execute([$auth['workspace_id'], $vesselId]);
        $vn = $stmt->fetch()['vessel_name'] ?? '';

        $db->prepare("DELETE FROM workspace_vessels WHERE workspace_id = ? AND vessel_id = ?")
           ->execute([$auth['workspace_id'], $vesselId]);

        logActivity($auth['workspace_id'], $auth['agent_id'], $auth['agent_name'], 'vessel_removed', 'vessel', $vn);

        // Audit trail (vessel removal — data still in sync_snapshots)
        $db->prepare("INSERT INTO audit_trail (id, workspace_id, vessel_id, agent_id, agent_name, action, entity_type, entity_name)
                      VALUES (?, ?, ?, ?, ?, 'remove_vessel', 'vessel', ?)")
           ->execute([uuid(), $auth['workspace_id'], $vesselId, $auth['agent_id'], $auth['agent_name'], $vn]);

        jsonResponse(['ok' => true]);
        break;

    // ─── LIST WORKSPACE VESSELS ───
    case 'list_vessels':
        $auth = authenticate();
        $db = getDB();
        initSchema();

        $stmt = $db->prepare("SELECT vessel_id, vessel_name, vessel_imo, scenario, added_by_agent, added_by_name, added_at
                              FROM workspace_vessels WHERE workspace_id = ? ORDER BY added_at");
        $stmt->execute([$auth['workspace_id']]);

        jsonResponse(['vessels' => $stmt->fetchAll()]);
        break;

    // ─── VESSEL AUDIT TRAIL ───
    case 'audit':
        $auth = authenticate();
        $vesselId = $_GET['vessel_id'] ?? null;
        $limit = min((int)($_GET['limit'] ?? 30), 100);

        $db = getDB();

        if ($vesselId) {
            $stmt = $db->prepare("SELECT id, vessel_id, agent_id, agent_name, action, entity_type, entity_id, entity_name, created_at
                                  FROM audit_trail WHERE workspace_id = ? AND vessel_id = ?
                                  ORDER BY created_at DESC LIMIT ?");
            $stmt->execute([$auth['workspace_id'], $vesselId, $limit]);
        } else {
            $stmt = $db->prepare("SELECT id, vessel_id, agent_id, agent_name, action, entity_type, entity_id, entity_name, created_at
                                  FROM audit_trail WHERE workspace_id = ?
                                  ORDER BY created_at DESC LIMIT ?");
            $stmt->execute([$auth['workspace_id'], $limit]);
        }

        jsonResponse(['events' => $stmt->fetchAll()]);
        break;

    default:
        jsonError(400, 'Unknown action. Use: create, join, info, leave, add_vessel, remove_vessel, list_vessels, audit');
}

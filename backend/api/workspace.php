<?php
/**
 * OceanCheck Collaboration API — Workspace Management
 *
 * POST   /api/workspace.php?action=create   — Create a new workspace
 * POST   /api/workspace.php?action=join     — Join with workspace code
 * GET    /api/workspace.php?action=info      — Get workspace info + agents
 * POST   /api/workspace.php?action=leave     — Leave workspace
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

    // ─── LEAVE WORKSPACE ───
    case 'leave':
        $auth = authenticate();
        $db = getDB();
        $db->prepare("UPDATE workspace_agents SET is_active = 0 WHERE workspace_id = ? AND agent_id = ?")
           ->execute([$auth['workspace_id'], $auth['agent_id']]);
        logActivity($auth['workspace_id'], $auth['agent_id'], $auth['agent_name'], 'agent_left');
        jsonResponse(['ok' => true]);
        break;

    default:
        jsonError(400, 'Unknown action. Use: create, join, info, leave');
}

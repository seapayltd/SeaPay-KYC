<?php
/**
 * OceanCheck Collaboration API — Activity Feed
 *
 * GET /api/activity.php              — Recent activity (last 50)
 * GET /api/activity.php?since=<iso>  — Activity since timestamp
 */

require_once __DIR__ . '/../includes/auth.php';

header('Content-Type: application/json');

$auth = authenticate();
$since = $_GET['since'] ?? null;
$limit = min((int)($_GET['limit'] ?? 50), 100);

$db = getDB();

if ($since) {
    $stmt = $db->prepare("SELECT id, agent_id, agent_name, action, entity_type, entity_name, detail, created_at
                          FROM activity_log WHERE workspace_id = ? AND created_at > ?
                          ORDER BY created_at DESC LIMIT ?");
    $stmt->execute([$auth['workspace_id'], $since, $limit]);
} else {
    $stmt = $db->prepare("SELECT id, agent_id, agent_name, action, entity_type, entity_name, detail, created_at
                          FROM activity_log WHERE workspace_id = ?
                          ORDER BY created_at DESC LIMIT ?");
    $stmt->execute([$auth['workspace_id'], $limit]);
}

$events = $stmt->fetchAll();

jsonResponse([
    'events' => $events,
    'count' => count($events),
]);

<?php
/**
 * One-time setup — run this once to initialize the database tables.
 * Access via: https://seapay.me/oceancheck/setup.php
 * DELETE THIS FILE after setup.
 */

require_once __DIR__ . '/includes/db.php';

try {
    initSchema();
    echo json_encode([
        'status' => 'ok',
        'message' => 'Database tables created successfully.',
        'tables' => ['workspaces', 'workspace_agents', 'sync_snapshots', 'activity_log'],
    ], JSON_PRETTY_PRINT);
} catch (PDOException $e) {
    http_response_code(500);
    echo json_encode([
        'status' => 'error',
        'message' => $e->getMessage(),
    ], JSON_PRETTY_PRINT);
}

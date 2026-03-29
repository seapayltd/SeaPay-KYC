<?php
/**
 * Database connection and schema initialization.
 */

require_once __DIR__ . '/config.php';

function getDB(): PDO {
    static $pdo = null;
    if ($pdo === null) {
        $dsn = 'mysql:host=' . DB_HOST . ';dbname=' . DB_NAME . ';charset=utf8mb4';
        $pdo = new PDO($dsn, DB_USER, DB_PASS, [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
        ]);
    }
    return $pdo;
}

function initSchema(): void {
    $db = getDB();

    $db->exec("CREATE TABLE IF NOT EXISTS workspaces (
        id VARCHAR(36) PRIMARY KEY,
        name VARCHAR(100) NOT NULL,
        code VARCHAR(16) NOT NULL UNIQUE,
        created_by VARCHAR(36) NOT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        INDEX idx_code (code)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

    $db->exec("CREATE TABLE IF NOT EXISTS workspace_agents (
        id VARCHAR(36) PRIMARY KEY,
        workspace_id VARCHAR(36) NOT NULL,
        agent_id VARCHAR(36) NOT NULL,
        agent_name VARCHAR(100) NOT NULL,
        agent_org VARCHAR(100) DEFAULT '',
        agent_role VARCHAR(50) DEFAULT '',
        token VARCHAR(64) NOT NULL UNIQUE,
        joined_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        last_sync DATETIME DEFAULT NULL,
        is_active TINYINT(1) DEFAULT 1,
        FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE,
        UNIQUE KEY unique_agent_workspace (workspace_id, agent_id),
        INDEX idx_token (token)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

    $db->exec("CREATE TABLE IF NOT EXISTS sync_snapshots (
        id VARCHAR(36) PRIMARY KEY,
        workspace_id VARCHAR(36) NOT NULL,
        agent_id VARCHAR(36) NOT NULL,
        agent_name VARCHAR(100) NOT NULL,
        version INT NOT NULL,
        vessels_json LONGTEXT,
        checks_json LONGTEXT,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE,
        INDEX idx_workspace_version (workspace_id, version DESC)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

    $db->exec("CREATE TABLE IF NOT EXISTS workspace_vessels (
        id VARCHAR(36) PRIMARY KEY,
        workspace_id VARCHAR(36) NOT NULL,
        vessel_id VARCHAR(36) NOT NULL,
        vessel_name VARCHAR(100) DEFAULT '',
        vessel_imo VARCHAR(20) DEFAULT '',
        scenario VARCHAR(50) DEFAULT '',
        added_by_agent VARCHAR(36),
        added_by_name VARCHAR(100) DEFAULT '',
        added_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE,
        UNIQUE KEY unique_vessel_workspace (workspace_id, vessel_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

    $db->exec("CREATE TABLE IF NOT EXISTS audit_trail (
        id VARCHAR(36) PRIMARY KEY,
        workspace_id VARCHAR(36) NOT NULL,
        vessel_id VARCHAR(36) DEFAULT NULL,
        agent_id VARCHAR(36),
        agent_name VARCHAR(100) DEFAULT '',
        action VARCHAR(50) NOT NULL,
        entity_type VARCHAR(30) DEFAULT '',
        entity_id VARCHAR(36) DEFAULT NULL,
        entity_name VARCHAR(100) DEFAULT '',
        before_json LONGTEXT DEFAULT NULL,
        after_json LONGTEXT DEFAULT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE,
        INDEX idx_vessel (workspace_id, vessel_id, created_at DESC)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

    // Add soft delete to sync_snapshots if not present
    try { $db->exec("ALTER TABLE sync_snapshots ADD COLUMN is_deleted TINYINT(1) DEFAULT 0"); } catch (Exception $e) {}
    try { $db->exec("ALTER TABLE sync_snapshots ADD COLUMN vessel_id VARCHAR(36) DEFAULT NULL"); } catch (Exception $e) {}
    try { $db->exec("ALTER TABLE sync_snapshots ADD COLUMN vessel_name VARCHAR(100) DEFAULT ''"); } catch (Exception $e) {}

    $db->exec("CREATE TABLE IF NOT EXISTS workspace_files (
        id VARCHAR(36) PRIMARY KEY,
        workspace_id VARCHAR(36) NOT NULL,
        vessel_id VARCHAR(36) DEFAULT NULL,
        filename VARCHAR(255) NOT NULL,
        original_name VARCHAR(255) DEFAULT '',
        mime_type VARCHAR(50) DEFAULT 'image/jpeg',
        size_bytes INT DEFAULT 0,
        uploaded_by_agent VARCHAR(36),
        uploaded_by_name VARCHAR(100) DEFAULT '',
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE,
        INDEX idx_workspace_vessel (workspace_id, vessel_id),
        UNIQUE KEY unique_file (workspace_id, filename)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

    $db->exec("CREATE TABLE IF NOT EXISTS activity_log (
        id VARCHAR(36) PRIMARY KEY,
        workspace_id VARCHAR(36) NOT NULL,
        agent_id VARCHAR(36) NOT NULL,
        agent_name VARCHAR(100) NOT NULL,
        action VARCHAR(50) NOT NULL,
        entity_type VARCHAR(30) DEFAULT '',
        entity_name VARCHAR(100) DEFAULT '',
        detail TEXT DEFAULT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE,
        INDEX idx_workspace_time (workspace_id, created_at DESC)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
}

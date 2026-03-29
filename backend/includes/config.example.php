<?php
/**
 * OceanCheck Collaboration API — Configuration
 *
 * SETUP:
 * 1. Copy this file to config.php (same directory)
 * 2. Fill in your Gandi database credentials below
 * 3. Upload ONLY config.php to the server via SFTP
 * 4. NEVER commit config.php to git (it's in .gitignore)
 */

// Database — from your Gandi hosting dashboard → Databases section
define('DB_HOST', 'localhost');
define('DB_NAME', 'your_database_name');
define('DB_USER', 'your_db_username');
define('DB_PASS', 'YOUR_PASSWORD_HERE');

// API Security — leave as-is (already randomized)
define('API_VERSION', '1');
define('HMAC_SECRET', '4bc66f0b98dddae4fe48f97aaf5cc2da57cfb4a6b653957d46c4d6078216be3a');

// Limits (no need to change)
define('RATE_LIMIT_REQUESTS', 60);
define('RATE_LIMIT_WINDOW', 60);
define('MAX_SNAPSHOT_SIZE', 10 * 1024 * 1024);
define('MAX_WORKSPACE_AGENTS', 20);
define('WORKSPACE_CODE_LENGTH', 8);

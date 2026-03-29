<?php
/**
 * OceanCheck Collaboration API — File Storage
 *
 * POST  /api/files.php?action=upload        — Upload a file (multipart)
 * GET   /api/files.php?action=download&file_id=X  — Download a file
 * GET   /api/files.php?action=list&vessel_id=X    — List files for a vessel
 * GET   /api/files.php?action=list                — List all files in workspace
 */

require_once __DIR__ . '/../includes/auth.php';

$action = $_GET['action'] ?? '';

// Files stored under: backend/files/{workspace_id}/
$filesRoot = __DIR__ . '/../files';
if (!is_dir($filesRoot)) { mkdir($filesRoot, 0755, true); }

switch ($action) {

    // ─── UPLOAD FILE ───
    case 'upload':
        $auth = authenticate();

        if (empty($_FILES['file'])) {
            jsonError(400, 'No file uploaded. Use multipart/form-data with field name "file".');
        }

        $file = $_FILES['file'];
        if ($file['error'] !== UPLOAD_ERR_OK) {
            jsonError(400, 'Upload error code: ' . $file['error']);
        }

        // Validate size (max 10MB)
        if ($file['size'] > 10 * 1024 * 1024) {
            jsonError(413, 'File too large. Maximum 10MB.');
        }

        // Validate type
        $allowed = ['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'application/pdf'];
        $mime = $file['type'] ?: mime_content_type($file['tmp_name']);
        if (!in_array($mime, $allowed)) {
            jsonError(400, 'Unsupported file type: ' . $mime);
        }

        $vesselId = $_POST['vessel_id'] ?? null;
        $filename = basename($_POST['filename'] ?? $file['name']);

        // Sanitize filename
        $filename = preg_replace('/[^a-zA-Z0-9._-]/', '_', $filename);

        // Create workspace directory
        $wsDir = $filesRoot . '/' . $auth['workspace_id'];
        if (!is_dir($wsDir)) { mkdir($wsDir, 0755, true); }

        $destPath = $wsDir . '/' . $filename;
        if (!move_uploaded_file($file['tmp_name'], $destPath)) {
            jsonError(500, 'Failed to store file.');
        }

        $db = getDB();
        initSchema();

        // Upsert — if same filename exists, update it
        $fileId = uuid();
        try {
            $db->prepare("INSERT INTO workspace_files (id, workspace_id, vessel_id, filename, original_name, mime_type, size_bytes, uploaded_by_agent, uploaded_by_name)
                          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                          ON DUPLICATE KEY UPDATE size_bytes = VALUES(size_bytes), uploaded_by_agent = VALUES(uploaded_by_agent), uploaded_by_name = VALUES(uploaded_by_name), created_at = NOW()")
               ->execute([$fileId, $auth['workspace_id'], $vesselId, $filename, $file['name'], $mime, $file['size'], $auth['agent_id'], $auth['agent_name']]);
        } catch (Exception $e) {
            jsonError(500, 'Database error: ' . $e->getMessage());
        }

        logActivity($auth['workspace_id'], $auth['agent_id'], $auth['agent_name'], 'file_uploaded', 'file', $filename);

        jsonResponse([
            'file_id' => $fileId,
            'filename' => $filename,
            'size' => $file['size'],
        ], 201);
        break;

    // ─── DOWNLOAD FILE ───
    case 'download':
        $auth = authenticate();

        $fileId = $_GET['file_id'] ?? '';
        $filename = $_GET['filename'] ?? '';

        $db = getDB();

        if ($fileId) {
            $stmt = $db->prepare("SELECT filename, mime_type FROM workspace_files WHERE id = ? AND workspace_id = ?");
            $stmt->execute([$fileId, $auth['workspace_id']]);
        } elseif ($filename) {
            $stmt = $db->prepare("SELECT filename, mime_type FROM workspace_files WHERE filename = ? AND workspace_id = ?");
            $stmt->execute([$filename, $auth['workspace_id']]);
        } else {
            jsonError(400, 'file_id or filename required');
        }

        $row = $stmt->fetch();
        if (!$row) jsonError(404, 'File not found');

        $filePath = $filesRoot . '/' . $auth['workspace_id'] . '/' . $row['filename'];
        if (!file_exists($filePath)) jsonError(404, 'File missing from storage');

        header('Content-Type: ' . ($row['mime_type'] ?: 'application/octet-stream'));
        header('Content-Disposition: inline; filename="' . $row['filename'] . '"');
        header('Content-Length: ' . filesize($filePath));
        readfile($filePath);
        exit;

    // ─── LIST FILES ───
    case 'list':
        $auth = authenticate();
        $vesselId = $_GET['vessel_id'] ?? null;

        $db = getDB();
        initSchema();

        if ($vesselId) {
            $stmt = $db->prepare("SELECT id, filename, original_name, mime_type, size_bytes, uploaded_by_name, created_at
                                  FROM workspace_files WHERE workspace_id = ? AND vessel_id = ?
                                  ORDER BY created_at DESC");
            $stmt->execute([$auth['workspace_id'], $vesselId]);
        } else {
            $stmt = $db->prepare("SELECT id, vessel_id, filename, original_name, mime_type, size_bytes, uploaded_by_name, created_at
                                  FROM workspace_files WHERE workspace_id = ?
                                  ORDER BY created_at DESC");
            $stmt->execute([$auth['workspace_id']]);
        }

        jsonResponse(['files' => $stmt->fetchAll()]);
        break;

    default:
        jsonError(400, 'Unknown action. Use: upload, download, list');
}

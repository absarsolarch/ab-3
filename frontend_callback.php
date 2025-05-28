<?php
session_start();

// Process callback from app tier
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $data = json_decode(file_get_contents('php://input'), true);
    
    if (isset($data['message'])) {
        $_SESSION['message'] = $data['message'];
    }
    
    if (isset($data['error'])) {
        $_SESSION['error'] = $data['error'];
    }
}

// Redirect back to frontend
header('Location: frontend.php');
exit;
?>

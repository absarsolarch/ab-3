<?php
// Start session for message passing between pages
session_start();

// Include required files
require_once "backend_cors.php";
require_once "backend_config.php";

// Initialize variables
$message = '';
$error = '';
$db_connected = false;
$redis = null;
$redis_prefix = "property:";

/**
 * Connect to the database
 * @return PDO|null Database connection or null on failure
 */
function connectToDatabase() {
    global $host, $dbname, $user, $password, $debug_mode, $redis, $redis_host, $redis_port;
    
    try {
        // For testing without a real database, use Redis
        if ($host === "DB_HOST_PLACEHOLDER" || $host === "YOUR_RDS_ENDPOINT" || $host === "TEST_MODE") {
            // Initialize Redis
            $redis = new Redis();
            $redis->connect($redis_host, $redis_port);
            
            // Add test data if empty
            $keys = $redis->keys($redis_prefix . "*");
            if (empty($keys)) {
                $id = $redis->incr("property_id_counter");
                $property = [
                    "id" => $id,
                    "title" => "Test Property 1",
                    "property_type" => "Apartment",
                    "price" => 450000,
                    "size_sqft" => 1200,
                    "bedrooms" => 3,
                    "bathrooms" => 2,
                    "location" => "Kuala Lumpur",
                    "status" => "Available",
                    "description" => "This is a test property for development purposes.",
                    "created_at" => date("Y-m-d H:i:s")
                ];
                $redis->set($redis_prefix . $id, json_encode($property));
            }
            
            return true;
        } else {
            // Real PostgreSQL connection
            $pdo = new PDO("pgsql:host=$host;dbname=$dbname", $user, $password);
            $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
            
            // Create table if not exists
            $pdo->exec("CREATE TABLE IF NOT EXISTS properties (
                id SERIAL PRIMARY KEY,
                title VARCHAR(200) NOT NULL,
                property_type VARCHAR(50) NOT NULL,
                price DECIMAL(12,2) NOT NULL,
                size_sqft INTEGER NOT NULL,
                bedrooms INTEGER,
                bathrooms INTEGER,
                location VARCHAR(200) NOT NULL,
                status VARCHAR(50) DEFAULT 'Available',
                description TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )");
            
            return $pdo;
        }
    } catch(PDOException $e) {
        if ($debug_mode) {
            error_log("Database connection error: " . $e->getMessage());
        }
        return null;
    }
}

// Try to connect to the database
$pdo = connectToDatabase();
$db_connected = ($pdo === true) || ($pdo instanceof PDO);

// Process form submissions if database is connected
if ($db_connected && $_SERVER["REQUEST_METHOD"] == "POST") {
    if (isset($_POST['action'])) {
        try {
            $callback_url = isset($_POST['callback_url']) ? $_POST['callback_url'] : null;
            
            switch ($_POST['action']) {
                case 'create':
                    if ($pdo === true) {
                        // Using Redis
                        $id = $redis->incr("property_id_counter");
                        $property = [
                            'id' => $id,
                            'title' => $_POST['title'],
                            'property_type' => $_POST['property_type'],
                            'price' => $_POST['price'],
                            'size_sqft' => $_POST['size_sqft'],
                            'bedrooms' => $_POST['bedrooms'] ?? null,
                            'bathrooms' => $_POST['bathrooms'] ?? null,
                            'location' => $_POST['location'],
                            'status' => $_POST['status'],
                            'description' => $_POST['description'] ?? '',
                            'created_at' => date("Y-m-d H:i:s")
                        ];
                        $redis->set($redis_prefix . $id, json_encode($property));
                    } else {
                        // Using PostgreSQL
                        $stmt = $pdo->prepare("INSERT INTO properties (title, property_type, price, size_sqft, bedrooms, bathrooms, location, status, description) 
                                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)");
                        $stmt->execute([
                            $_POST['title'],
                            $_POST['property_type'],
                            $_POST['price'],
                            $_POST['size_sqft'],
                            $_POST['bedrooms'] ?? null,
                            $_POST['bathrooms'] ?? null,
                            $_POST['location'],
                            $_POST['status'],
                            $_POST['description'] ?? ''
                        ]);
                    }
                    $message = "Property listed successfully!";
                    break;

                case 'update':
                    if ($pdo === true) {
                        // Using Redis
                        $data = $redis->get($redis_prefix . $_POST['id']);
                        if ($data) {
                            $property = json_decode($data, true);
                            $property['status'] = $_POST['status'];
                            $redis->set($redis_prefix . $_POST['id'], json_encode($property));
                        }
                    } else {
                        // Using PostgreSQL
                        $stmt = $pdo->prepare("UPDATE properties SET status=? WHERE id=?");
                        $stmt->execute([$_POST['status'], $_POST['id']]);
                    }
                    $message = "Property status updated successfully!";
                    break;

                case 'delete':
                    if ($pdo === true) {
                        // Using Redis
                        $redis->del($redis_prefix . $_POST['id']);
                    } else {
                        // Using PostgreSQL
                        $stmt = $pdo->prepare("DELETE FROM properties WHERE id=?");
                        $stmt->execute([$_POST['id']]);
                    }
                    $message = "Property listing removed successfully!";
                    break;
            }
            
            // Handle callback or redirect
            if ($callback_url) {
                // Send JSON response to callback URL
                $ch = curl_init("http://" . $callback_url);
                curl_setopt($ch, CURLOPT_POST, 1);
                curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode(['message' => $message]));
                curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
                curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
                curl_exec($ch);
                curl_close($ch);
                
                // Return success response
                header('Content-Type: application/json');
                echo json_encode(['status' => 'success', 'message' => $message]);
                exit;
            } else {
                $_SESSION['message'] = $message;
            }
        } catch (Exception $e) {
            $error_msg = $debug_mode ? $e->getMessage() : "An error occurred while processing your request.";
            
            if ($callback_url) {
                // Send error to callback URL
                $ch = curl_init("http://" . $callback_url);
                curl_setopt($ch, CURLOPT_POST, 1);
                curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode(['error' => $error_msg]));
                curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
                curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
                curl_exec($ch);
                curl_close($ch);
                
                // Return error response
                header('Content-Type: application/json');
                echo json_encode(['status' => 'error', 'error' => $error_msg]);
                exit;
            } else {
                $_SESSION['error'] = $error_msg;
            }
        }
        
        // Redirect if no callback URL and not already exited
        if (!$callback_url) {
            header("Location: frontend.php");
            exit;
        }
    }
}

// Fetch all properties if database is connected
$properties = [];
if ($db_connected) {
    try {
        if ($pdo === true) {
            // Using Redis
            $keys = $redis->keys($redis_prefix . "*");
            foreach ($keys as $key) {
                $property = json_decode($redis->get($key), true);
                if ($property) {
                    $properties[] = $property;
                }
            }
            // Sort by created_at desc
            usort($properties, function($a, $b) {
                return strtotime($b['created_at']) - strtotime($a['created_at']);
            });
        } else {
            // Using PostgreSQL
            $stmt = $pdo->query("SELECT * FROM properties ORDER BY created_at DESC");
            $properties = $stmt->fetchAll(PDO::FETCH_ASSOC);
        }
    } catch (Exception $e) {
        if ($debug_mode) {
            $error = $e->getMessage();
            error_log("Error fetching properties: " . $e->getMessage());
        }
    }
}

// If this file is accessed directly (API mode), return JSON
if (basename($_SERVER['PHP_SELF']) == basename(__FILE__)) {
    header('Content-Type: application/json');
    
    // Check if this is a test request
    if (isset($_GET['test'])) {
        echo json_encode([
            'status' => 'ok',
            'db_connected' => $db_connected,
            'message' => 'Backend is functioning correctly',
            'post_data' => $_POST,
            'session_data' => $_SESSION
        ]);
        exit;
    }
    
    // Simple API endpoint handling
    if (isset($_GET['api'])) {
        if (!$db_connected) {
            echo json_encode(['error' => 'Database connection failed']);
            exit;
        }
        
        try {
            switch ($_GET['api']) {
                case 'properties':
                    echo json_encode($properties);
                    break;
                case 'property':
                    if (isset($_GET['id'])) {
                        if ($pdo === true) {
                            // Using Redis
                            $data = $redis->get($redis_prefix . $_GET['id']);
                            $property = $data ? json_decode($data, true) : null;
                            echo json_encode($property ?: ['error' => 'Property not found']);
                        } else {
                            // Using PostgreSQL
                            $stmt = $pdo->prepare("SELECT * FROM properties WHERE id = ?");
                            $stmt->execute([$_GET['id']]);
                            $property = $stmt->fetch(PDO::FETCH_ASSOC);
                            echo json_encode($property ?: ['error' => 'Property not found']);
                        }
                    } else {
                        echo json_encode(['error' => 'Property ID required']);
                    }
                    break;
                case 'clear':
                    if ($pdo === true) {
                        // Using Redis
                        $keys = $redis->keys($redis_prefix . "*");
                        if (!empty($keys)) {
                            $redis->del($keys);
                        }
                        $redis->set("property_id_counter", 0);
                        echo json_encode(['status' => 'success', 'message' => 'Database cleared']);
                    } else {
                        // Using PostgreSQL
                        $pdo->exec("TRUNCATE TABLE properties RESTART IDENTITY");
                        echo json_encode(['status' => 'success', 'message' => 'Database cleared']);
                    }
                    break;
                default:
                    echo json_encode(['error' => 'Unknown API endpoint']);
            }
        } catch (Exception $e) {
            echo json_encode(['error' => $debug_mode ? $e->getMessage() : 'API error']);
        }
        exit;
    }
}
?>

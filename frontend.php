<?php
// Start session for message passing between pages
session_start();

// Include frontend components
require_once "frontend_config.php";
require_once "frontend_api_client.php";

// Initialize variables
$message = '';
$error = '';

// Check if app_tier_endpoint is still a placeholder
if ($app_tier_endpoint == "APP_TIER_ENDPOINT_PLACEHOLDER") {
    // Try to get the app tier endpoint from the environment
    $app_tier_endpoint = getenv('APP_TIER_ENDPOINT');
    if (!$app_tier_endpoint) {
        // Fallback to localhost for testing
        $app_tier_endpoint = "http://localhost";
    }
}

$properties = getProperties();
$db_connected = !empty($properties);

// Check for session messages
if (isset($_SESSION['message'])) {
    $message = $_SESSION['message'];
    unset($_SESSION['message']);
}

if (isset($_SESSION['error'])) {
    $error = $_SESSION['error'];
    unset($_SESSION['error']);
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Anycompany Properties Sdn Bhd - Property Management</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
    <style>
        :root {
            --primary-color: #2c3e50;
            --secondary-color: #e74c3c;
        }
        .navbar {
            background-color: var(--primary-color) !important;
        }
        .btn-primary {
            background-color: var(--secondary-color);
            border-color: var(--secondary-color);
        }
        .btn-primary:hover {
            background-color: #c0392b;
            border-color: #c0392b;
        }
        .card {
            margin-bottom: 20px;
            box-shadow: 0 2px 5px rgba(0,0,0,0.1);
        }
        .property-card {
            height: 100%;
        }
        .status-badge {
            position: absolute;
            top: 10px;
            right: 10px;
            padding: 5px 10px;
            border-radius: 3px;
        }
        .price-tag {
            font-size: 1.5em;
            color: var(--secondary-color);
            font-weight: bold;
        }
        .property-features {
            margin: 10px 0;
        }
        .feature-icon {
            margin-right: 15px;
            color: var(--primary-color);
        }
        .system-status {
            font-size: 0.8em;
            margin-bottom: 20px;
        }
        .debug-info {
            font-size: 0.8em;
            background-color: #f8f9fa;
            padding: 10px;
            border-radius: 5px;
            margin-top: 20px;
        }
    </style>
</head>
<body>
    <nav class="navbar navbar-dark mb-4">
        <div class="container">
            <span class="navbar-brand mb-0 h1">
                <i class="fas fa-building"></i> Anycompany Properties Sdn Bhd
            </span>
        </div>
    </nav>

    <div class="container">
        <?php if (isset($message) && $message): ?>
            <div class="alert alert-success"><?php echo htmlspecialchars($message); ?></div>
        <?php endif; ?>
        
        <?php if (isset($error) && $error): ?>
            <div class="alert alert-danger"><?php echo htmlspecialchars($error); ?></div>
        <?php endif; ?>
        
        <?php if (!$db_connected): ?>
            <div class="alert alert-warning">
                <strong>Note:</strong> Unable to connect to the application tier or database. 
                Please check your configuration.
            </div>
        <?php endif; ?>

        <div class="row">
            <div class="col-md-4">
                <div class="card">
                    <div class="card-header bg-primary text-white">
                        <i class="fas fa-plus"></i> Add New Property
                    </div>
                    <div class="card-body">
                        <form method="POST" action="<?php echo $app_tier_endpoint; ?>/backend_api.php">
                            <input type="hidden" name="action" value="create">
                            <input type="hidden" name="callback_url" value="<?php echo (isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on' ? 'https://' : 'http://') . $_SERVER['HTTP_HOST']; ?>/frontend_callback.php">
                            <div class="mb-3">
                                <label class="form-label">Property Title</label>
                                <input type="text" name="title" class="form-control" required>
                            </div>
                            <div class="mb-3">
                                <label class="form-label">Property Type</label>
                                <select name="property_type" class="form-control" required>
                                    <option value="Apartment">Apartment</option>
                                    <option value="House">House</option>
                                    <option value="Land">Land</option>
                                    <option value="Commercial">Commercial</option>
                                </select>
                            </div>
                            <div class="mb-3">
                                <label class="form-label">Price (MYR)</label>
                                <input type="number" name="price" class="form-control" required>
                            </div>
                            <div class="mb-3">
                                <label class="form-label">Size (sq ft)</label>
                                <input type="number" name="size_sqft" class="form-control" required>
                            </div>
                            <div class="row mb-3">
                                <div class="col">
                                    <label class="form-label">Bedrooms</label>
                                    <input type="number" name="bedrooms" class="form-control">
                                </div>
                                <div class="col">
                                    <label class="form-label">Bathrooms</label>
                                    <input type="number" name="bathrooms" class="form-control">
                                </div>
                            </div>
                            <div class="mb-3">
                                <label class="form-label">Location</label>
                                <input type="text" name="location" class="form-control" required>
                            </div>
                            <div class="mb-3">
                                <label class="form-label">Status</label>
                                <select name="status" class="form-control" required>
                                    <option value="Available">Available</option>
                                    <option value="Under Contract">Under Contract</option>
                                    <option value="Sold">Sold</option>
                                </select>
                            </div>
                            <div class="mb-3">
                                <label class="form-label">Description</label>
                                <textarea name="description" class="form-control" rows="3"></textarea>
                            </div>
                            <button type="submit" class="btn btn-primary">Add Property</button>
                        </form>
                    </div>
                </div>
            </div>

            <div class="col-md-8">
                <h2 class="mb-4">Property Listings</h2>
                <?php if (empty($properties)): ?>
                    <div class="alert alert-info">No properties found. Add your first property using the form.</div>
                <?php else: ?>
                    <div class="row">
                        <?php foreach ($properties as $property): ?>
                            <div class="col-md-6 mb-4">
                                <div class="card property-card">
                                    <div class="card-body">
                                        <span class="status-badge bg-<?php 
                                            echo $property['status'] == 'Available' ? 'success' : 
                                                ($property['status'] == 'Under Contract' ? 'warning' : 'danger'); 
                                        ?>">
                                            <?php echo htmlspecialchars($property['status']); ?>
                                        </span>
                                        <h5 class="card-title"><?php echo htmlspecialchars($property['title']); ?></h5>
                                        <div class="price-tag"><?php echo formatPrice($property['price']); ?></div>
                                        <div class="property-features">
                                            <span class="feature-icon">
                                                <i class="fas fa-ruler-combined"></i> <?php echo htmlspecialchars($property['size_sqft']); ?> sq ft
                                            </span>
                                            <span class="feature-icon">
                                                <i class="fas fa-bed"></i> <?php echo htmlspecialchars($property['bedrooms'] ?? 'N/A'); ?>
                                            </span>
                                            <span class="feature-icon">
                                                <i class="fas fa-bath"></i> <?php echo htmlspecialchars($property['bathrooms'] ?? 'N/A'); ?>
                                            </span>
                                        </div>
                                        <p><i class="fas fa-map-marker-alt"></i> <?php echo htmlspecialchars($property['location']); ?></p>
                                        <p class="card-text"><?php echo htmlspecialchars($property['description'] ?? ''); ?></p>
                                        
                                        <div class="d-flex justify-content-between mt-3">
                                            <form method="POST" action="<?php echo $app_tier_endpoint; ?>/backend_api.php" class="me-2">
                                                <input type="hidden" name="action" value="update">
                                                <input type="hidden" name="id" value="<?php echo $property['id']; ?>">
                                                <input type="hidden" name="callback_url" value="<?php echo (isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on' ? 'https://' : 'http://') . $_SERVER['HTTP_HOST']; ?>/frontend_callback.php">
                                                <select name="status" class="form-select form-select-sm" onchange="this.form.submit()">
                                                    <option value="Available" <?php echo $property['status'] == 'Available' ? 'selected' : ''; ?>>Available</option>
                                                    <option value="Under Contract" <?php echo $property['status'] == 'Under Contract' ? 'selected' : ''; ?>>Under Contract</option>
                                                    <option value="Sold" <?php echo $property['status'] == 'Sold' ? 'selected' : ''; ?>>Sold</option>
                                                </select>
                                            </form>
                                            <form method="POST" action="<?php echo $app_tier_endpoint; ?>/backend_api.php" style="display: inline;">
                                                <input type="hidden" name="action" value="delete">
                                                <input type="hidden" name="id" value="<?php echo $property['id']; ?>">
                                                <input type="hidden" name="callback_url" value="<?php echo (isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on' ? 'https://' : 'http://') . $_SERVER['HTTP_HOST']; ?>/frontend_callback.php">
                                                <button type="submit" class="btn btn-danger btn-sm" onclick="return confirm('Are you sure you want to delete this property?')">
                                                    <i class="fas fa-trash"></i> Delete
                                                </button>
                                            </form>
                                        </div>
                                    </div>
                                </div>
                            </div>
                        <?php endforeach; ?>
                    </div>
                <?php endif; ?>
            </div>
        </div>
        
        <footer class="mt-5 pt-3 border-top text-muted">
            <div class="system-status">
                <p>System Status: <?php echo $db_connected ? 'Connected to application tier' : 'Unable to connect to application tier'; ?></p>
            </div>
            
            <?php if ($debug_mode): ?>
            <div class="debug-info">
                <h5>Debug Information</h5>
                <p>PHP Version: <?php echo phpversion(); ?></p>
                <p>Session ID: <?php echo session_id(); ?></p>
                <p>Properties Count: <?php echo count($properties); ?></p>
                <p>App Tier Endpoint: <?php echo $app_tier_endpoint; ?></p>
                <p>Redis Host: <?php echo $redis_host; ?></p>
            </div>
            <?php endif; ?>
        </footer>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>

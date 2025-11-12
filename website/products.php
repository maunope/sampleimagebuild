<!DOCTYPE html>
<?php

require __DIR__ . '/vendor/autoload.php'; // Composer autoloader

use Google\Cloud\SecretManager\V1\SecretManagerServiceClient;

?>
<html lang="en">

<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Our Products - The Pet Shop</title>
    <style>
        @import url('https://fonts.googleapis.com/css2?family=Poppins:wght@400;700&display=swap');

        :root {
            --primary-color: #2980b9;
            --secondary-color: #2c3e50;
            --accent-color: #f39c12;
            --bg-color: #ecf0f1;
        }

        body {
            font-family: 'Poppins', -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            margin: 0;
            background-color: var(--bg-color);
            color: var(--secondary-color);
            display: flex;
            flex-direction: column;
            min-height: 100vh;
        }

        .container {
            width: 90%;
            max-width: 1100px;
            margin: 0 auto;
        }

        header {
            background: #fff;
            box-shadow: 0 2px 5px rgba(0, 0, 0, 0.1);
            padding: 1rem 0;
            position: sticky;
            top: 0;
            z-index: 1000;
        }

        nav {
            display: flex;
            justify-content: space-between;
            align-items: center;
            width: 90%;
            max-width: 1100px;
            margin: 0 auto;
        }

        .logo {
            font-size: 1.8rem;
            font-weight: 700;
            color: var(--primary-color);
            text-decoration: none;
        }

        main {
            flex: 1;
            padding: 2rem 1rem;
        }

        h1 {
            text-align: center;
            margin-bottom: 2rem;
            font-size: 2.5rem;
        }

        .product-list {
            list-style-type: none;
            padding: 0;
            display: flex;
            flex-wrap: wrap;
            justify-content: center;
            gap: 2rem;
        }

        .product-list li {
            background-color: white;
            border-radius: 8px;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
            padding: 2rem 1.5rem;
            width: 220px;
            text-align: center;
            font-size: 1.1rem;
            font-weight: bold;
            transition: transform 0.2s ease-out, box-shadow 0.2s;
        }

        .product-list li:hover {
            transform: translateY(-5px);
            box-shadow: 0 8px 15px rgba(0, 0, 0, 0.15);
        }

        footer {
            background-color: #333;
            color: white;
            text-align: center;
            padding: 1rem 0;
            margin-top: 2rem;
        }
    </style>
</head>

<body>
    <header>
        <nav class="container">
            <a href="index.php" class="logo">The Pet Shop</a>
        </nav>
    </header>

    <main>
        <h1>Our Awesome Pet Products</h1>
        <div class="container">
            <ul class="product-list">
                <?php

                // Function to get database credentials from Secret Manager with caching
                function getDbCredentials() {
                    static $credentials = null; // Static variable for in-memory caching within the request

                    if ($credentials === null) {
                        // Create the Secret Manager client
                        $client = new SecretManagerServiceClient();
                        
                        // Get the project ID from the metadata server
                        $projectId = file_get_contents('http://metadata.google.internal/computeMetadata/v1/project/project-id', false, stream_context_create([
                            'http' => ['header' => 'Metadata-Flavor: Google']
                        ]));
                        
                        // The name of the secret to access
                        $secretName = 'projects/' . $projectId . '/secrets/petshop-db-credentials';
                        try {
                            // Access the secret version
                            $response = $client->accessSecretVersion($secretName . '/versions/latest');
                            $secretPayload = $response->getPayload()->getData();

                            // Decode the JSON payload
                            $credentials = json_decode($secretPayload, true);

                            if (json_last_error() !== JSON_ERROR_NONE) {
                                error_log("Error decoding secret payload: " . json_last_error_msg());
                                $credentials = false; // Indicate failure
                            }

                        } catch (Exception $e) {
                            error_log("Failed to access secret: " . $e->getMessage());
                            $credentials = false; // Indicate failure
                        } finally {
                            $client->close();
                        }
                    }
                    return $credentials;
                }

                $dbcredentials = getDbCredentials();
                $servername = "petshop-db.petshop.internal"; // Still use the internal DNS name
                $dbname = "petshop"; // Database name

                if ($dbcredentials === false || !isset($dbcredentials['username']) || !isset($dbcredentials['password'])) {
                    echo "<li>Database connection failed. Please try again later.</li>";
                } else {
                    // Create connection
                    $conn = new mysqli($servername, $dbcredentials['username'], $dbcredentials['password'], $dbname);

                    // Check connection
                    if ($conn->connect_error) {
                        echo "<li>Database connection failed: " . $conn->connect_error . "</li>";
                    } else {
                        $sql = "SELECT id, name FROM products";
                        $result = $conn->query($sql);

                        if ($result->num_rows > 0) {
                            // output data of each row
                            while($row = $result->fetch_assoc()) {
                                echo "<li>" . htmlspecialchars($row["name"]) . "</li>";
                            }
                        } else {
                            echo "<li>No products found. Check back soon!</li>";
                        }
                        $conn->close();
                    }
                }
                ?>
            </ul>
        </div>
    </main>

    <footer class="container">
        <p>&copy; 2025 The Pet Shop. All Rights Reserved.</p>
    </footer>
</body>

</html>
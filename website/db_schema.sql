-- Create the database if it doesn't already exist.
CREATE DATABASE IF NOT EXISTS petshop;

-- Switch to the petshop database.
USE petshop;

-- Create a simple 'pets' table.
CREATE TABLE pets (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    breed VARCHAR(255) NOT NULL,
    age INT,
    price DECIMAL(10, 2)
);

-- Insert some sample data into the 'pets' table.
INSERT INTO pets (name, breed, age, price) VALUES
('Buddy', 'Golden Retriever', 2, 500.00),
('Lucy', 'Labrador', 1, 450.00),
('Max', 'German Shepherd', 3, 600.00),
('Whiskers', 'Siamese Cat', 2, 300.00),
('Rocky', 'Boxer', 4, 550.00);

-- Grant privileges to the application user on the new database.
-- Note: In a real environment, the password should be managed securely.
GRANT ALL PRIVILEGES ON petshop.* TO 'petshopuser'@'%' IDENTIFIED BY 'password';
FLUSH PRIVILEGES;

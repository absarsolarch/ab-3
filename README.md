# Property Management System

A simple web-based property management system for Anycompany Properties Sdn Bhd. This application allows users to list, manage, and track property listings.

## Features

- Add new property listings with details (title, type, price, size, etc.)
- Update property status (Available, Under Contract, Sold)
- Delete property listings
- View all property listings with their details
- Responsive design for desktop and mobile devices

## Architecture

The application is split into two main components:

1. **Frontend (frontend.php)**: Handles the user interface and presentation
2. **Backend (backend.php)**: Handles data processing, database operations, and business logic

## Requirements

- PHP 7.4 or higher
- PostgreSQL database (or SQLite for testing)
- Web server (Apache, Nginx, etc.)

## Installation

1. Clone the repository:
   ```
   git clone https://github.com/absarsolarch/ab3.git
   ```

2. Configure your database connection in `backend.php`:
   ```php
   $host = "YOUR_RDS_ENDPOINT";
   $dbname = "myappdb";
   $user = "YOUR_DB_USER";
   $password = "YOUR_DB_PASSWORD";
   ```

3. Upload the files to your web server or run a local development server:
   ```
   php -S localhost:8000
   ```

4. Access the application in your browser:
   ```
   http://localhost:8000/
   ```

## Testing

The application includes a test script (`test.php`) that verifies the basic functionality:

1. Run the test script in your browser:
   ```
   http://localhost:8000/test.php
   ```

2. Or run from the command line:
   ```
   php test.php
   ```

## Test Mode

If you don't have a PostgreSQL database configured, the application will automatically run in test mode using an in-memory SQLite database. This is perfect for development and testing.

## API Endpoints

The backend also provides simple API endpoints:

- `backend.php?api=properties` - Get all properties as JSON
- `backend.php?api=property&id=1` - Get a specific property by ID
- `backend.php?test=1` - Test if the backend is functioning correctly

## Security Considerations

- The application includes basic input validation and sanitization
- All database queries use prepared statements to prevent SQL injection
- HTML output is escaped to prevent XSS attacks

## Future Improvements

- User authentication and authorization
- Image uploads for properties
- Advanced search and filtering
- Pagination for large property listings
- Email notifications for status changes

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Author

Anycompany Properties Sdn Bhd

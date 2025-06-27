#!/bin/bash
set -e
# set -x # Uncomment this line to enable debug output, which will print every command executed by the script, helpful for debugging

# Custom entrypoint for db-importer service

# Ensure 'mysql' user and group exist (usually exist in Debian base image, but as a safeguard)
if ! id "mysql" &>/dev/null; then
    echo "Creating mysql user and group..."
    adduser --system --no-create-home --group mysql
fi

# Initialize MySQL data directory (if it hasn't been initialized yet)
# Check if /var/lib/mysql/mysql directory exists, which is a sign that MySQL database has been initialized
if [ ! -d "/var/lib/mysql/mysql" ]; then
    echo "Initializing MySQL data directory..."
    # Ensure correct permissions for data directory
    chown -R mysql:mysql /var/lib/mysql
    chmod 700 /var/lib/mysql # Recommended stricter permissions for production environments

    # Execute MySQL data directory initialization
    # --initialize-insecure: Create data directory and set up a temporary passwordless root user
    # --log-error=/var/log/mysql/error.log: Output initialization error logs to a file
    mysqld --initialize-insecure --user=mysql --datadir=/var/lib/mysql --log-error=/var/log/mysql/error.log
    echo "MySQL data directory initialized."

    # Start a temporary MySQL server for initial setup
    echo "Starting temporary MySQL server for initial setup..."
    # --skip-networking: Prevent network connections
    # --skip-grant-tables: Disable privilege checks, allowing passwordless root login
    # --log-error=/var/log/mysql/temp_error.log: Error log for the temporary service
    /usr/sbin/mysqld --user=mysql --datadir=/var/lib/mysql --skip-networking --skip-grant-tables --log-error=/var/log/mysql/temp_error.log &
    MYSQL_TEMP_PID=$!
    sleep 15 # Give MySQL more time to start the temporary server (increased from 10s to 15s)
    echo "Temporary MySQL server running (PID: $MYSQL_TEMP_PID)."

    # Wait for the temporary MySQL server to be ready
    # Redirect stderr to /dev/null to suppress irrelevant output
    # Still use passwordless root connection here, as unix_socket is typically effective at this stage
    until mysql -u root -e "SELECT 1;" &>/dev/null; do
        echo "Waiting for temporary MySQL server to be ready (initial setup loop)..."
        sleep 5 # Increased sleep interval (from 2s to 5s)
    done
    echo "Temporary MySQL server ready."

    # Execute MySQL initial setup steps (set root password, create users/databases)
    echo "Running MySQL initial setup and user configuration..."

    # --- Key change: Modify root@localhost authentication ---
    # First, drop existing root@localhost (it might default to unix_socket)
    echo "Dropping existing 'root'@'localhost' user to clear unix_socket default..."
    mysql -u root -e "DROP USER IF EXISTS 'root'@'localhost';" || { echo "WARNING: Could not drop 'root'@'localhost'. It might not exist or permissions are restrictive for DROP. Proceeding..."; }

    # Recreate 'root' user, explicitly specifying 'mysql_native_password' plugin
    # Set it to connect from any host '%' to ensure password authentication takes effect
    echo "Creating 'root'@'%' with mysql_native_password and specified password..."
    mysql -u root -e "CREATE USER 'root'@'%' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASSWORD}';" || { echo "ERROR: Failed to create 'root'@'%'."; cat /var/log/mysql/temp_error.log; exit 1; }
    mysql -u root -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;" || { echo "ERROR: Failed to grant privileges to 'root'@'%'."; cat /var/log/mysql/temp_error.log; exit 1; }

    # Create database
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "CREATE DATABASE IF NOT EXISTS ${MYSQL_DATABASE};" || { echo "ERROR: Failed to create database."; cat /var/log/mysql/temp_error.log; exit 1; }

    # --- Revised application user creation and authorization logic ---
    # First, drop any existing application user entries to clear old authentication or host configurations
    echo "Dropping existing application user '${MYSQL_USER}'@'localhost' and '${MYSQL_USER}'@'127.0.0.1' if they exist..."
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "DROP USER IF EXISTS '${MYSQL_USER}'@'localhost';" || { echo "WARNING: Could not drop '${MYSQL_USER}'@'localhost'."; }
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "DROP USER IF EXISTS '${MYSQL_USER}'@'127.0.0.1';" || { echo "WARNING: Could not drop '${MYSQL_USER}'@'127.0.0.1'."; }

    # Create application user, primarily defined to connect from any host '%' and force mysql_native_password
    echo "Creating application user '${MYSQL_USER}'@'%' with mysql_native_password..."
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "CREATE USER '${MYSQL_USER}'@'%' IDENTIFIED WITH mysql_native_password BY '${MYSQL_PASSWORD}';" || { echo "ERROR: Failed to create user '${MYSQL_USER}'@'%'."; cat /var/log/mysql/temp_error.log; exit 1; }

    # Grant privileges to the application user for specific hosts (localhost and 127.0.0.1)
    echo "Granting privileges to application user '${MYSQL_USER}' for localhost and 127.0.0.1..."
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "GRANT ALL PRIVILEGES ON ${MYSQL_DATABASE}.* TO '${MYSQL_USER}'@'localhost';" || { echo "ERROR: Failed to grant privileges to '${MYSQL_USER}'@'localhost'."; cat /var/log/mysql/temp_error.log; exit 1; }
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "GRANT ALL PRIVILEGES ON ${MYSQL_DATABASE}.* TO '${MYSQL_USER}'@'127.0.0.1';" || { echo "ERROR: Failed to grant privileges to '${MYSQL_USER}'@'127.0.0.1'."; cat /var/log/mysql/temp_error.log; exit 1; }


    # Flush privileges and increase waiting time (revised)
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "FLUSH PRIVILEGES;" || { echo "ERROR: Failed to flush privileges."; cat /var/log/mysql/temp_error.log; exit 1; }
    sleep 10 # Give MySQL more time to process the flush (increased from 5s to 10s)
    sync # Force filesystem synchronization to ensure changes are written to disk

    # Stop temporary MySQL server
    echo "Stopping temporary MySQL server..."
    kill $MYSQL_TEMP_PID
    wait $MYSQL_TEMP_PID || true # `|| true` prevents script from exiting on error if process already terminated
    echo "Temporary MySQL server stopped. Initialization complete."
    sleep 15 # Give filesystem more time to sync, preventing the next mysqld process from reading old state (increased from 10s to 15s)
fi

# --- Key change: Start the main MySQL service process in the background here ---
# This ensures that the MySQL service is already running when importer.py attempts to connect.
echo "Starting main MySQL server in background (for importer and continued operation)..."
/usr/sbin/mysqld --user=mysql --datadir=/var/lib/mysql --log-error=/var/log/mysql/error.log &
MAIN_MYSQL_PID=$! # Capture PID of the main MySQL process

# Wait for the main MySQL server to be fully up and accessible before running importer
echo "Waiting for main MySQL server to be fully up and accessible before running importer..."
# --- Health check using the application user, explicitly specifying TCP connection ---
# Add --protocol=tcp to ensure unix_socket is not used
until mysql -h "127.0.0.1" -P "3306" -u "${MYSQL_USER}" -p"${MYSQL_PASSWORD}" --protocol=tcp -e "SELECT 1;"; do
    echo "MySQL is unavailable - sleeping (main server check)"
    # Check if the background MySQL process is still alive. If not, it indicates a problem.
    if ! kill -0 "$MAIN_MYSQL_PID" &>/dev/null; then
        echo "ERROR: Main MySQL process (PID $MAIN_MYSQL_PID) has died unexpectedly!"
        if [ -f "/var/log/mysql/error.log" ]; then
            echo "--- Latest MySQL Error Log ---"
            tail -n 20 /var/log/mysql/error.log
            echo "-----------------------------"
        fi
        exit 1 # If MySQL process dies, exit entrypoint
    fi

    # If log file exists, output last few lines for debugging
    if [ -f "/var/log/mysql/error.log" ]; then
        echo "--- Latest MySQL Error Log (during check) ---"
        tail -n 10 /var/log/mysql/error.log
        echo "---------------------------------------------"
    fi
    sleep 10 # Increased sleep interval (from 5s to 10s)
done
echo "Main MySQL server is up and running!"

# Run data importer script
echo "Running data importer..."
python3 /app/importer.py
echo "Data importer finished."

# Keep the main MySQL server process in the foreground
# Since mysqld is already started in the background, we use `wait` to keep the container alive.
# If `mysqld` exits for some reason, this will cause the container to exit as well.
echo "Importer finished. Keeping MySQL server running (PID: $MAIN_MYSQL_PID) in foreground."
wait "$MAIN_MYSQL_PID"

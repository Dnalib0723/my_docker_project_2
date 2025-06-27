#!/bin/bash
set -e
# set -x # 取消註解此行以啟用除錯輸出，這會輸出腳本執行的每個命令，有助於除錯

# Custom entrypoint for db-importer service

# 確保 'mysql' 用戶和組存在 (在 Debian 基礎映像中通常已經存在，但以防萬一)
if ! id "mysql" &>/dev/null; then
    echo "Creating mysql user and group..."
    adduser --system --no-create-home --group mysql
fi

# 初始化 MySQL 資料目錄 (如果它還沒有被初始化)
# 檢查 /var/lib/mysql/mysql 目錄是否存在，這是 MySQL 數據庫初始化後的標誌
if [ ! -d "/var/lib/mysql/mysql" ]; then
    echo "Initializing MySQL data directory..."
    # 確保數據目錄的所有權限正確
    chown -R mysql:mysql /var/lib/mysql
    chmod 700 /var/lib/mysql # 建議在生產環境中更嚴格的權限

    # 執行 MySQL 數據目錄初始化
    # --initialize-insecure: 創建數據目錄並設置臨時無密碼的 root 用戶
    # --log-error=/var/log/mysql/error.log: 將初始化錯誤日誌輸出到文件
    mysqld --initialize-insecure --user=mysql --datadir=/var/lib/mysql --log-error=/var/log/mysql/error.log
    echo "MySQL data directory initialized."

    # 啟動臨時 MySQL 伺服器，用於執行初始設置
    echo "Starting temporary MySQL server for initial setup..."
    # --skip-networking: 阻止網絡連接
    # --skip-grant-tables: 禁用權限檢查，允許無密碼 root 登錄
    # --log-error=/var/log/mysql/temp_error.log: 臨時服務的錯誤日誌
    /usr/sbin/mysqld --user=mysql --datadir=/var/lib/mysql --skip-networking --skip-grant-tables --log-error=/var/log/mysql/temp_error.log &
    MYSQL_TEMP_PID=$!
    sleep 10 # 給予 MySQL 足夠的時間來啟動
    echo "Temporary MySQL server running (PID: $MYSQL_TEMP_PID)."

    # 等待臨時 MySQL 伺服器準備就緒
    # 將 stderr 導向 /dev/null 防止無關輸出干擾
    # 這裡仍然使用無需密碼的 root 連接，因為 unix_socket 通常在這個階段是有效的
    until mysql -u root -e "SELECT 1;" &>/dev/null; do
        echo "Waiting for temporary MySQL server to be ready (initial setup loop)..."
        sleep 2
    done
    echo "Temporary MySQL server ready."

    # 執行 MySQL 的初始設置步驟 (設定 root 密碼，創建用戶/資料庫)
    echo "Running MySQL initial setup and user configuration..."

    # --- 關鍵修改：更換 root@localhost 的認證方式 ---
    # 先刪除可能存在的 root@localhost (它可能預設使用 unix_socket)
    echo "Dropping existing 'root'@'localhost' user to clear unix_socket default..."
    mysql -u root -e "DROP USER IF EXISTS 'root'@'localhost';" || { echo "WARNING: Could not drop 'root'@'localhost'. It might not exist or permissions are restrictive for DROP. Proceeding..."; }

    # 重新創建 'root' 用戶，並明確指定 'mysql_native_password' 認證插件
    # 設置為從任何主機 '%' 連接，以確保密碼認證生效
    echo "Creating 'root'@'%' with mysql_native_password and specified password..."
    mysql -u root -e "CREATE USER 'root'@'%' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASSWORD}';" || { echo "ERROR: Failed to create 'root'@'%'."; cat /var/log/mysql/temp_error.log; exit 1; }
    mysql -u root -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;" || { echo "ERROR: Failed to grant privileges to 'root'@'%'."; cat /var/log/mysql/temp_error.log; exit 1; }

    # 創建資料庫
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "CREATE DATABASE IF NOT EXISTS ${MYSQL_DATABASE};" || { echo "ERROR: Failed to create database."; cat /var/log/mysql/temp_error.log; exit 1; }

    # 創建應用用戶並授予權限 (同樣明確指定 mysql_native_password)
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "CREATE USER '${MYSQL_USER}'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_PASSWORD}';" || { echo "ERROR: Failed to create user for localhost."; cat /var/log/mysql/temp_error.log; exit 1; }
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "GRANT ALL PRIVILEGES ON ${MYSQL_DATABASE}.* TO '${MYSQL_USER}'@'localhost';" || { echo "ERROR: Failed to grant privileges to localhost."; cat /var/log/mysql/temp_error.log; exit 1; }

    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "CREATE USER '${MYSQL_USER}'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY '${MYSQL_PASSWORD}';" || { echo "ERROR: Failed to create user for 127.0.0.1."; cat /var/log/mysql/temp_error.log; exit 1; }
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "GRANT ALL PRIVILEGES ON ${MYSQL_DATABASE}.* TO '${MYSQL_USER}'@'127.0.0.1';" || { echo "ERROR: Failed to grant privileges to 127.0.0.1."; cat /var/log/mysql/temp_error.log; exit 1; }

    # 刷新權限並增加等待時間
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "FLUSH PRIVILEGES;" || { echo "ERROR: Failed to flush privileges."; cat /var/log/mysql/temp_error.log; exit 1; }
    sleep 5 # 給予 MySQL 更多時間來處理刷新
    sync # 強制文件系統同步，確保更改寫入磁碟

    # 關閉臨時 MySQL 伺服器
    echo "Stopping temporary MySQL server..."
    kill $MYSQL_TEMP_PID
    wait $MYSQL_TEMP_PID || true # `|| true` 防止在進程已經結束時腳本因錯誤而退出
    echo "Temporary MySQL server stopped. Initialization complete."
    sleep 10 # 給予文件系統更多時間來同步，避免下一個 mysqld 進程讀取到舊狀態
fi

# --- 關鍵改動：在這裡啟動主要的 MySQL 服務進程到背景 ---
# 這樣在 importer.py 嘗試連接時，MySQL 服務已經在運行。
echo "Starting main MySQL server in background (for importer and continued operation)..."
/usr/sbin/mysqld --user=mysql --datadir=/var/lib/mysql --log-error=/var/log/mysql/error.log &
MAIN_MYSQL_PID=$! # 捕獲主 MySQL 進程的 PID

# 等待主要的 MySQL 伺服器完全啟動並接受連接
echo "Waiting for main MySQL server to be fully up and accessible before running importer..."
# --- 健康檢查改用應用用戶，並明確指定透過 TCP 連接 ---
# 增加 --protocol=tcp 確保不使用 unix_socket
until mysql -h "127.0.0.1" -P "3306" -u "${MYSQL_USER}" -p"${MYSQL_PASSWORD}" --protocol=tcp -e "SELECT 1;"; do
    echo "MySQL is unavailable - sleeping (main server check)"
    # 檢查背景 MySQL 進程是否仍然存活。如果沒有，則表示出現問題。
    if ! kill -0 "$MAIN_MYSQL_PID" &>/dev/null; then
        echo "ERROR: Main MySQL process (PID $MAIN_MYSQL_PID) has died unexpectedly!"
        if [ -f "/var/log/mysql/error.log" ]; then
            echo "--- Latest MySQL Error Log ---"
            tail -n 20 /var/log/mysql/error.log
            echo "-----------------------------"
        fi
        exit 1 # 如果 MySQL 進程死亡，退出 entrypoint
    fi

    # 如果有日誌文件，輸出最後幾行以協助除錯
    if [ -f "/var/log/mysql/error.log" ]; then
        echo "--- Latest MySQL Error Log (during check) ---"
        tail -n 10 /var/log/mysql/error.log
        echo "---------------------------------------------"
    fi
    sleep 5 # 增加等待間隔，給予 MySQL 更多啟動時間
done
echo "Main MySQL server is up and running!"

# 運行資料匯入腳本
echo "Running data importer..."
python3 /app/importer.py
echo "Data importer finished."

# 保持主要的 MySQL 伺服器進程在前台運行
# 因為 mysqld 已經在背景中啟動，我們使用 `wait` 命令等待它，確保容器存活。
# 如果 `mysqld` 由於某些原因退出，這會導致容器也退出。
echo "Importer finished. Keeping MySQL server running (PID: $MAIN_MYSQL_PID) in foreground."
wait "$MAIN_MYSQL_PID"

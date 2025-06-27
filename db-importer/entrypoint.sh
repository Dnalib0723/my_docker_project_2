#!/bin/bash
set -e
# set -x # 取消註解此行以啟用除錯輸出

# Custom entrypoint for db-importer service

# 確保 'mysql' 用戶和組存在
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
    chmod 700 /var/lib/mysql # 限制權限以提高安全性

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
    until mysql -u root -e "SELECT 1;" &>/dev/null; do
        echo "Waiting for temporary MySQL server to be ready (initial setup loop)..."
        sleep 2
    done
    echo "Temporary MySQL server ready."

    # 執行 MySQL 的初始設置步驟 (設定 root 密碼，創建用戶/資料庫)
    echo "Running MySQL initial setup and user configuration..."
    # 設定 root 密碼
    mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}'; FLUSH PRIVILEGES;" || { echo "ERROR: Failed to set root password."; cat /var/log/mysql/temp_error.log; exit 1; }
    # 創建資料庫和用戶 (使用來自 docker-compose.yml 的環境變數)
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "CREATE DATABASE IF NOT EXISTS ${MYSQL_DATABASE};" || { echo "ERROR: Failed to create database."; cat /var/log/mysql/temp_error.log; exit 1; }
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "CREATE USER '${MYSQL_USER}'@'localhost' IDENTIFIED BY '${MYSQL_PASSWORD}';" || { echo "ERROR: Failed to create user."; cat /var/log/mysql/temp_error.log; exit 1; }
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "GRANT ALL PRIVILEGES ON ${MYSQL_DATABASE}.* TO '${MYSQL_USER}'@'localhost';" || { echo "ERROR: Failed to grant privileges."; cat /var/log/mysql/temp_error.log; exit 1; }
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "FLUSH PRIVILEGES;" || { echo "ERROR: Failed to flush privileges."; cat /var/log/mysql/temp_error.log; exit 1; }

    # 關閉臨時 MySQL 伺服器
    echo "Stopping temporary MySQL server..."
    kill $MYSQL_TEMP_PID
    wait $MYSQL_TEMP_PID || true # `|| true` 防止在進程已經結束時腳本因錯誤而退出
    echo "Temporary MySQL server stopped. Initialization complete."
    sleep 5 # 給予文件系統同步時間
fi

# 啟動主要的 MySQL 伺服器進程 (此時它將由 exec "$@" 命令在前台運行)
echo "Starting main MySQL server for the container's primary process..."
# 我們不再在這裡背景啟動 mysqld，而是讓它由 CMD 接管

# 等待主要的 MySQL 伺服器完全啟動並接受連接
echo "Waiting for main MySQL server to be fully up and accessible before running importer..."
# 使用在 docker-compose.yml 中設定的用戶和密碼進行連接檢查
until mysql -h "127.0.0.1" -P "3306" -u "${MYSQL_USER}" -p"${MYSQL_PASSWORD}" -e "SELECT 1;" &>/dev/null; do
    echo "MySQL is unavailable - sleeping (main server check)"
    # 如果 MySQL 遲遲未能啟動，檢查日誌文件
    if [ -f "/var/log/mysql/error.log" ]; then
        echo "--- Latest MySQL Error Log ---"
        tail -n 10 /var/log/mysql/error.log
        echo "-----------------------------"
    fi
    sleep 5 # 增加等待間隔
done
echo "MySQL is up and running in foreground/background!"

# 運行資料匯入腳本
echo "Running data importer..."
python3 /app/importer.py
echo "Data importer finished."

# 將主要的 MySQL 伺服器進程帶到前台
# `exec "$@"` 會替換當前 shell 進程為 CMD 中提供的命令 (即 `mysqld`)，
# 這樣 MySQL 伺服器就會成為容器的主進程，保持容器運行。
echo "Importer finished. Transferring control to MySQL server (CMD)."
exec "$@"

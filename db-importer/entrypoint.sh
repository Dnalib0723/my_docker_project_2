#!/bin/bash
set -e

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
    chmod 700 /var/lib/mysql # 限制權限以提高安全性

    # 執行 MySQL 數據目錄初始化
    # --initialize-insecure: 創建數據目錄並設置臨時無密碼的 root 用戶
    mysqld --initialize-insecure --user=mysql --datadir=/var/lib/mysql
    echo "MySQL data directory initialized."

    # 啟動臨時 MySQL 伺服器，用於執行初始設置
    echo "Starting temporary MySQL server for initial setup..."
    # --skip-networking: 阻止網絡連接
    # --skip-grant-tables: 禁用權限檢查，允許無密碼 root 登錄
    /usr/sbin/mysqld --user=mysql --datadir=/var/lib/mysql --skip-networking --skip-grant-tables &
    MYSQL_TEMP_PID=$!
    sleep 5 # 給予 MySQL 足夠的時間來啟動
    echo "Temporary MySQL server running (PID: $MYSQL_TEMP_PID)."

    # 等待臨時 MySQL 伺服器準備就緒
    until mysql -u root -e "SELECT 1;" > /dev/null 2>&1; do
        echo "Waiting for temporary MySQL server to be ready..."
        sleep 1
    done
    echo "Temporary MySQL server ready."

    # 執行 MySQL 的初始設置步驟 (設定 root 密碼，創建用戶/資料庫)
    echo "Running MySQL initial setup..."
    # 設定 root 密碼
    mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}'; FLUSH PRIVILEGES;"
    # 創建資料庫和用戶 (使用來自 docker-compose.yml 的環境變數)
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "CREATE DATABASE IF NOT EXISTS ${MYSQL_DATABASE};"
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "CREATE USER '${MYSQL_USER}'@'localhost' IDENTIFIED BY '${MYSQL_PASSWORD}';"
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "GRANT ALL PRIVILEGES ON ${MYSQL_DATABASE}.* TO '${MYSQL_USER}'@'localhost';"
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "FLUSH PRIVILEGES;"

    # 關閉臨時 MySQL 伺服器
    kill $MYSQL_TEMP_PID
    wait $MYSQL_TEMP_PID || true # `|| true` 防止在進程已經結束時腳本因錯誤而退出
    echo "Temporary MySQL server stopped. Initialization complete."
fi

# 啟動主要的 MySQL 伺服器進程 (在背景)
echo "Starting main MySQL server in background..."
# /usr/sbin/mysqld 是 MySQL 伺服器的可執行檔路徑
/usr/sbin/mysqld --user=mysql --datadir=/var/lib/mysql &
BACKGROUND_MYSQL_PID=$!

# 等待 MySQL 伺服器完全啟動並接受連接
echo "Waiting for background MySQL server to be fully up and accessible..."
# 使用在 docker-compose.yml 中設定的用戶和密碼進行連接檢查
until mysql -h "127.0.0.1" -P "3306" -u "${MYSQL_USER}" -p"${MYSQL_PASSWORD}" -e "SELECT 1;" > /dev/null 2>&1; do
    echo "MySQL is unavailable - sleeping"
    sleep 2
done
echo "MySQL is up and running in background!"

# 運行資料匯入腳本
echo "Running data importer..."
python3 /app/importer.py
echo "Data importer finished."

# 將主要的 MySQL 伺服器進程帶到前台
# `exec "$@"` 會替換當前 shell 進程為 CMD 中提供的命令 (即 `mysqld`)，
# 這樣 MySQL 伺服器就會成為容器的主進程，保持容器運行。
echo "Importer finished. Keeping MySQL server running in foreground."
exec "$@"

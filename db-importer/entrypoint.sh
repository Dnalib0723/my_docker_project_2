#!/bin/bash
set -e

# my_project/db-importer/entrypoint.sh

# 在這個容器中，MySQL 服務運行在本地
MYSQL_HOST="127.0.0.1" # 或 "localhost"
MYSQL_PORT="3306"

# 從 docker-compose.yml 獲取 root 密碼
# 這個變數應由 docker-compose.yml 傳入
# 確保這個變數在容器環境中可用
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD}"


echo "Waiting for MySQL at $MYSQL_HOST:$MYSQL_PORT to be ready..."
# 使用 mysql 命令進行更可靠的健康檢查
# 注意：這裡使用 root 用戶和其密碼進行檢查，請確保這些環境變數已在 docker-compose.yml 中正確配置
until mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u root -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1;" > /dev/null 2>&1; do
  echo "MySQL is unavailable - sleeping"
  sleep 2
done
echo "MySQL is up and running!"

# 現在運行資料匯入腳本
echo "Running data importer..."
# 執行 Dockerfile 中定義的 CMD 命令 (例如 python3 importer.py)
# `exec "$@"` 會將當前 shell 進程替換為 CMD 命令，確保 CMD 是容器的主進程。
exec "$@"

# 注意：如果 importer.py 是一個一次性腳本並在完成後退出，
# 則容器會在 importer.py 結束後自動停止。
# 如果 importer.py 是一個長時間運行的服務，它會保持容器運行。
# 不需要額外的 'wait' 命令，因為 exec "$@" 會處理進程管理。
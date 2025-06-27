#!/bin/bash
# my_project/db-importer/entrypoint.sh

# 這是 MySQL 官方映像檔的原始 entrypoint 腳本，用於啟動 MySQL
# 我們需要確保在我們運行 importer.py 之前 MySQL 已經完全啟動
# 方法一：呼叫 MySQL 官方 entrypoint，然後等待 MySQL 可用
/usr/local/bin/docker-entrypoint.sh mysqld & # 在後台啟動 MySQL

# 等待 MySQL 服務完全啟動
echo "Waiting for MySQL to be ready..."
until mysql -h 127.0.0.1 -u root -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1;" > /dev/null 2>&1; do
  echo "MySQL is unavailable - sleeping"
  sleep 2
done
echo "MySQL is up and running!"

# 現在運行資料匯入腳本
echo "Running data importer..."
python3 /app/importer.py

echo "Data importer finished."

# 保持容器運行，因為 MySQL 已經在後台運行
wait # 等待後台的 mysqld 進程結束 (這會確保容器不會立即退出)
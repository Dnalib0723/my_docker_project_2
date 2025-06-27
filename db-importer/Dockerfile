# my_project/db-importer/Dockerfile
# 使用 Debian slim 作為基礎映像檔，確保 apt 工具可用
FROM debian:buster-slim

# 設定環境變數，用於 MySQL 安裝和配置
ENV DEBIAN_FRONTEND=noninteractive
# 這些變數會在 docker-compose.yml 中被設定和覆寫，這裡僅為 Dockerfile 內部提供預設值
ENV MYSQL_ROOT_PASSWORD=root_password_temp
ENV MYSQL_DATABASE=my_database_temp
ENV MYSQL_USER=user_temp
ENV MYSQL_PASSWORD=password_temp
ENV CSV_PATH=/var/lib/mysql-files/titanic_passengers.csv

# --- 安裝 MySQL Server、Python 和相關工具 ---
# `default-mysql-server` 是主要用於安裝 MySQL 伺服器的套件
# `default-mysql-client` 用於提供 `mysql` 命令列客戶端，供 entrypoint.sh 使用
# `python3` 和 `python3-pip` 用於運行 importer.py
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        default-mysql-server \
        default-mysql-client \
        python3 \
        python3-pip \
        && \
    # 創建 MySQL 日誌目錄並設定權限
    mkdir -p /var/log/mysql && \
    chown mysql:mysql /var/log/mysql && \
    # 清理 apt 快取，以保持映像檔精簡
    rm -rf /var/lib/apt/lists/*

# 創建 MySQL 運行所需的目錄並設定正確的權限
# MySQL 數據目錄：/var/lib/mysql
# MySQL 運行時的套接字文件目錄：/var/run/mysqld
RUN mkdir -p /var/lib/mysql /var/run/mysqld && \
    chown -R mysql:mysql /var/lib/mysql /var/run/mysqld && \
    chmod 700 /var/lib/mysql # 建議在生產環境中更嚴格的權限

# 複製 Python 依賴清單檔案
WORKDIR /app
COPY requirements.txt .
# 安裝 Python 依賴，--no-cache-dir 避免安裝包的快取，減少映像檔大小
RUN pip3 install --no-cache-dir -r requirements.txt

# 複製 Python 匯入腳本
COPY importer.py .

# 複製 CSV 資料檔案到 MySQL 安全目錄
# /var/lib/mysql-files/ 是 MySQL 預設允許 LOAD DATA INFILE 的位置。
# 確保原始檔案名 "titanic passengers.csv" 在複製時被重新命名或處理為 "titanic_passengers.csv"
COPY titanic\ passengers.csv /var/lib/mysql-files/titanic_passengers.csv

# 複製自定義的 entrypoint 腳本
# 這個腳本將處理 MySQL 的初始化、啟動和 importer.py 的執行
COPY entrypoint.sh /usr/local/bin/custom-db-entrypoint.sh
RUN chmod +x /usr/local/bin/custom-db-entrypoint.sh

# 暴露 MySQL 端口
EXPOSE 3306

# 設定容器啟動時執行的 entrypoint
# custom-db-entrypoint.sh 將是容器啟動後第一個執行的腳本
ENTRYPOINT ["/usr/local/bin/custom-db-entrypoint.sh"]
# CMD 作為參數傳遞給 entrypoint，這裡傳遞 MySQL 服務啟動命令
# entrypoint.sh 將會處理 MySQL 的啟動、等待和 importer.py 的執行
# 之後，它會確保 mysqld 進程作為主進程保持運行
CMD ["mysqld"]

# my_project/db-importer/Dockerfile
# 從 MySQL 官方映像檔開始
FROM mysql:8.0

# 設定環境變數 (這些會被 entrypoint.sh 使用)
ENV MYSQL_DATABASE=my_database
ENV MYSQL_USER=user
ENV MYSQL_PASSWORD=password
ENV MYSQL_ROOT_PASSWORD=root_password
ENV CSV_FILENAME="titanic_passengers.csv"

# 安裝 Python 和 MySQL 連接器
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 複製 Python 依賴和程式碼
COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt

COPY importer.py .
# 將 CSV 複製到 /var/lib/mysql-files/，這是 MySQL 預設允許 LOAD DATA INFILE 的位置
COPY "$CSV_FILENAME" /var/lib/mysql-files/

# 複製自定義的 entrypoint 腳本
COPY entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh

# 將自定義 entrypoint 設定為容器啟動命令
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# MySQL 預設的 CMD 會被我們的 ENTRYPOINT 呼叫
CMD ["mysqld"]
# my_project/db-importer/Dockerfile
# 使用官方 MySQL 映像作為基礎映像，確保它能運行 MySQL 伺服器
# 選擇一個穩定的版本，例如 8.0 或 5.7
FROM mysql:8.0

# --- 安裝 Python 和 MySQL 客戶端以運行 importer.py 和 entrypoint.sh 中的健康檢查 ---
# 更新套件列表並安裝必要的工具：
# python3: 用於運行 importer.py
# python3-pip: 用於安裝 Python 套件 (mysql-connector-python)
# default-mysql-client: 提供 'mysql' 命令，用於 entrypoint.sh 中的健康檢查
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        python3 python3-pip default-mysql-client && \
    # 清理 apt 快取，以保持映像檔精簡
    rm -rf /var/lib/apt/lists/*

# --- 設定 MySQL 環境變數 (這些將由 docker-compose.yml 覆寫) ---
# 在這裡設定預設值有助於理解，但實際值由 docker-compose.yml 提供
ENV MYSQL_DATABASE=my_database
ENV MYSQL_USER=user
ENV MYSQL_PASSWORD=password
ENV MYSQL_ROOT_PASSWORD=root_password
# 定義 CSV 檔案在容器內的路徑，MySQL 將從這裡讀取
ENV CSV_PATH=/var/lib/mysql-files/titanic_passengers.csv

# --- 複製並安裝 importer.py 的 Python 依賴 ---
# 設定工作目錄為 /app
WORKDIR /app
COPY db-importer/requirements.txt .
# 安裝 Python 依賴，--no-cache-dir 避免安裝包的快取，減少映像檔大小
RUN pip3 install --no-cache-dir -r requirements.txt

# --- 複製匯入腳本和 CSV 資料檔案 ---
# 複製 Python 匯入腳本
COPY db-importer/importer.py .
# 複製 CSV 檔案到 MySQL 的安全檔案目錄。
# /var/lib/mysql-files/ 是 MySQL 預設允許 LOAD DATA INFILE 的位置。
# 注意：如果原始檔案名包含空格，最好在 COPY 時重新命名或處理。
# 這裡假設已將 "titanic passengers.csv" 重新命名為 "titanic_passengers.csv"
COPY db-importer/titanic_passengers.csv /var/lib/mysql-files/titanic_passengers.csv

# --- 複製並設定自定義的 entrypoint 腳本 ---
# 這個 entrypoint 腳本將處理等待 MySQL 就緒，然後運行匯入程序。
COPY db-importer/entrypoint.sh /usr/local/bin/custom-mysql-entrypoint.sh
# 賦予 entrypoint 腳本執行權限
RUN chmod +x /usr/local/bin/custom-mysql-entrypoint.sh

# --- 設定容器啟動時執行的 entrypoint 和預設命令 ---
# 自定義的 entrypoint 腳本將首先被執行。
# 它會確保 MySQL 伺服器啟動並準備就緒，然後執行 CMD 中提供的命令。
ENTRYPOINT ["/usr/local/bin/custom-mysql-entrypoint.sh"]
# CMD 中的命令將作為參數 ($@) 傳遞給 ENTRYPOINT 腳本。
# 這確保了在 MySQL 準備就緒後，importer.py 腳本會被執行。
CMD ["python3", "/app/importer.py"]
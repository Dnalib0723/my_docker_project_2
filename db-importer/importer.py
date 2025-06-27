# my_project/db-importer/importer.py
import mysql.connector
import os
import time

def import_data():
    # 在這個合併的容器中，MySQL 在同一個主機上，所以使用 localhost
    db_host = '127.0.0.1' # 或 'localhost'
    db_name = os.getenv('MYSQL_DATABASE')
    db_user = os.getenv('MYSQL_USER')
    db_password = os.getenv('MYSQL_PASSWORD')
    root_password = os.getenv('MYSQL_ROOT_PASSWORD') # 為了在初始化時使用 root 用戶
    csv_path = os.getenv('CSV_PATH', '/var/lib/mysql-files/titanic passengers.csv') # MySQL 可存取的位置

    print(f"Connecting to MySQL at {db_host}...")
    try:
        # 使用 root 帳戶連接，確保有足夠權限執行 CREATE TABLE 和 LOAD DATA INFILE
        cnx = mysql.connector.connect(
            host=db_host,
            user='root',
            password=root_password,
            database=db_name
        )
        print("Successfully connected to MySQL as root.")
    except mysql.connector.Error as err:
        print(f"Connection failed: {err}")
        return

    cursor = cnx.cursor()

    # 1. 檢查並建立 'passengers' 表格
    try:
        cursor.execute(f"USE {db_name}") # 確保使用正確的資料庫
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS passengers (
                PassengerId INT,
                Survived INT,
                Pclass INT,
                Name VARCHAR(255),
                Sex VARCHAR(10),
                Age FLOAT,
                SibSp INT,
                Parch INT,
                Ticket VARCHAR(50),
                Fare FLOAT,
                Cabin VARCHAR(50),
                Embarked VARCHAR(1)
            )
        """)
        print("Table 'passengers' checked/created successfully.")
        cnx.commit()
    except mysql.connector.Error as err:
        print(f"Error creating table: {err}")
        cnx.close()
        return

    # 2. 清空表格（如果需要重新載入）
    try:
        cursor.execute("TRUNCATE TABLE passengers")
        print("Table 'passengers' truncated (if it contained data).")
        cnx.commit()
    except mysql.connector.Error as err:
        print(f"Error truncating table: {err}")
        pass

    # 3. 執行 LOAD DATA INFILE 命令
    # 注意 CSV 檔案名和路徑必須與 Dockerfile 中複製到 MySQL 安全目錄的路徑一致
    load_sql = f"""
    LOAD DATA INFILE '{csv_path}'
    INTO TABLE passengers
    FIELDS TERMINATED BY ','
    ENCLOSED BY '"'
    LINES TERMINATED BY '\\n'
    IGNORE 1 ROWS;
    """
    try:
        print(f"Executing LOAD DATA INFILE from {csv_path}...")
        cursor.execute(load_sql)
        cnx.commit()
        print("Data loaded successfully into 'passengers' table.")

        # 驗證載入的資料量
        cursor.execute("SELECT COUNT(*) FROM passengers")
        count = cursor.fetchone()[0]
        print(f"Total rows in 'passengers' table: {count}")

    except mysql.connector.Error as err:
        print(f"Error loading data: {err}")
        print("Please ensure:")
        print("1. The CSV file path in LOAD DATA INFILE matches the file's location in the MySQL container (/var/lib/mysql-files/).")
        print("2. The MySQL user (root in this case) has FILE privilege.")
    finally:
        cursor.close()
        cnx.close()
        print("Database connection closed.")

if __name__ == "__main__":
    print("Data Importer Script started within the MySQL container.")
    import_data()
    print("Data Importer Script finished.")
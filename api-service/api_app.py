# my_project/api-service/api_app.py
from flask import Flask, jsonify
import mysql.connector
import os

app = Flask(__name__)

# 資料庫連接函數
def get_db_connection():
    # DB_HOST 現在是 'db-importer' (docker-compose 中的服務名稱)
    db_host = os.getenv('DB_HOST')
    db_name = os.getenv('DB_NAME')
    db_user = os.getenv('DB_USER')
    db_password = os.getenv('DB_PASSWORD')
    try:
        cnx = mysql.connector.connect(
            host=db_host,
            user=db_user,
            password=db_password,
            database=db_name
        )
        return cnx
    except mysql.connector.Error as err:
        print(f"Error connecting to database: {err}")
        return None

@app.route('/')
def hello_world():
    return 'Hello from Flask API Service!'

@app.route('/status')
def status():
    return jsonify({"status": "API service is running", "framework": "Flask"})

@app.route('/data')
def get_data():
    cnx = get_db_connection()
    if cnx is None:
        return jsonify({"error": "Database connection failed"}), 500

    cursor = cnx.cursor(dictionary=True) # dictionary=True 讓結果以字典形式返回
    try:
        cursor.execute("SELECT * FROM passengers LIMIT 10") # 從 passengers 表格獲取資料
        data = cursor.fetchall()
        return jsonify({"message": "Data from MySQL", "passengers": data})
    except mysql.connector.Error as err:
        print(f"Error fetching data: {err}")
        return jsonify({"error": f"Failed to fetch data: {err}"}), 500
    finally:
        if cnx:
            cursor.close()
            cnx.close()

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0')
# my_project/api-service/Dockerfile
FROM python:3.9-slim-buster

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY api_app.py .

CMD ["flask", "run", "--host=0.0.0.0"]
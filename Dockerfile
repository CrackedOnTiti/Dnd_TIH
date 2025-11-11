FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY back/ ./back/
COPY front/ ./front/

EXPOSE 5000

CMD ["python", "back/app.py"]

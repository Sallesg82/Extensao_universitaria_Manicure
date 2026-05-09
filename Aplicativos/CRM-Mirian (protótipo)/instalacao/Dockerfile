FROM python:3.14-slim

WORKDIR /app

RUN pip install --no-cache-dir flask flask-cors

COPY ../src ./src
COPY ../backend ./backend

EXPOSE 3001

VOLUME ["/app/backend/db"]

CMD ["python", "backend/server.py"]

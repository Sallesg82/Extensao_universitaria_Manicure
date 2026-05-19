FROM python:3.14-slim

WORKDIR /app

RUN pip install --no-cache-dir flask flask-cors flask-socketio gunicorn requests supabase werkzeug google-auth google-auth-oauthlib google-api-python-client python-dateutil postgrest

COPY ./src ./src
COPY ./backend ./backend

EXPOSE 3001

VOLUME ["/app/backend/db"]

CMD ["gunicorn", "-k", "gthread", "-w", "1", "--threads", "10", "--bind", "0.0.0.0:3001", "backend.wsgi:app"]

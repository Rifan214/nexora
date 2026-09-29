FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PLAYWRIGHT_BROWSERS_PATH=/ms-playwright

WORKDIR /app

RUN apt-get update && \
    apt-get install --yes --no-install-recommends ffmpeg && \
    rm -rf /var/lib/apt/lists/* && \
    adduser --disabled-password --gecos "" appuser

COPY pyproject.toml README.md ./
COPY app ./app
COPY tests ./tests

RUN pip install --upgrade pip && \
    pip install ".[dev]" && \
    playwright install --with-deps chromium && \
    rm -rf /var/lib/apt/lists/* && \
    chmod -R 755 /ms-playwright && \
    mkdir -p /app/storage/temp && \
    chown -R appuser:appuser /app/storage

USER appuser

EXPOSE 8000

CMD ["sh", "-c", "exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]

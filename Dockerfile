# syntax=docker/dockerfile:1

# Multi-stage build for a small, production-ready image.
# - Build deps in builder stage (wheels)
# - Runtime uses slim image, non-root user, minimal env

FROM python:3.12-slim AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /build

# Install build tooling only in the builder stage
RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt ./

# Build wheels to avoid compilers in the runtime image
RUN python -m pip install --upgrade pip \
    && pip wheel --no-cache-dir --wheel-dir /wheels -r requirements.txt


FROM python:3.12-slim AS runtime

# Reasonable defaults for containers
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    # gunicorn logs to stdout/stderr
    GUNICORN_CMD_ARGS="--bind 0.0.0.0:8000 --workers 2 --threads 4 --access-logfile - --error-logfile -"

WORKDIR /app

# Create an unprivileged user
RUN addgroup --system app \
    && adduser --system --ingroup app app

# Install runtime dependencies from prebuilt wheels
COPY --from=builder /wheels /wheels
COPY requirements.txt ./
RUN python -m pip install --no-cache-dir --no-index --find-links=/wheels -r requirements.txt \
    && rm -rf /wheels

# Copy application code
COPY app ./app

# Default DB path is in a volume-friendly location (override if needed)
ENV DB_PATH=/data/app.db

# Ensure the default data dir exists and is writable by the app user
RUN mkdir -p /data \
    && chown -R app:app /data /app

USER app

EXPOSE 8000

# Start via WSGI server
CMD ["gunicorn", "app.main:app"]

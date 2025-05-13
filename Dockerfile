# Stage 1: Build stage (optimized for security & caching)
FROM python:3.12.2-alpine3.19 AS builder

# Set secure environment variables
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Install system dependencies (minimal set)
RUN apk update && apk add --no-cache \
    build-base \
    postgresql-dev \
    libffi-dev \
    linux-headers \
    && rm -rf /var/cache/apk/*

WORKDIR /app

# Copy only requirements first for better layer caching
COPY req.txt .

# Install Python deps in isolated virtual environment
RUN python -m venv /opt/venv && \
    /opt/venv/bin/pip install --upgrade pip && \
    /opt/venv/bin/pip install -r req.txt

# ---

# Stage 2: Runtime stage (ultra-lean)
FROM python:3.12.2-alpine3.19

# Security hardening
RUN addgroup -S django && \
    adduser -S django -G django && \
    apk update && \
    apk add --no-cache libpq && \
    rm -rf /var/cache/apk/*

WORKDIR /app

# Copy from builder
COPY --from=builder /opt/venv /opt/venv
COPY . .

# Ensure proper permissions
RUN chown -R django:django /app && \
    find /app -type d -exec chmod 755 {} \; && \
    find /app -type f -exec chmod 644 {} \;

# Activate virtual environment
ENV PATH="/opt/venv/bin:$PATH"

# Switch to non-root user
USER django

# Health check (adjust as needed)
HEALTHCHECK --interval=30s --timeout=3s \
    CMD curl -f http://localhost:8000/health/ || exit 1

# Expose and run
EXPOSE 8000
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--worker-tmp-dir", "/dev/shm", "--workers=4", "app.wsgi:application"]
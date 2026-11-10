# ==============================================================================
# STAGE 1: TEST TARGET
# This stage installs development/testing binaries and configures the test run.
# ==============================================================================
FROM python:3.12-slim-bookworm AS test

# INSTRUCTIONS & CONTRACT FOR THE INSTRUCTOR:
# 1. Python environment optimizations inside the container.
# 2. Layer caching optimization: Copy and install packages BEFORE copying app code.
# 3. Secure runtime execution context under UID/GID 10001.
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# Copy dependency manifests first to optimize Docker build caching layers
COPY requirements.txt requirements-dev.txt /app/

# Install full development and unit-testing framework packages
RUN python -m pip install --no-cache-dir -r requirements-dev.txt

# Copy application layers, configuration files, and automation test suites
COPY app/ /app/app/
COPY gunicorn.conf.py /app/
COPY tests/ /app/tests/
COPY pytest.ini /app/

# Establish secure non-root OS-level primitives (UID 10001 & GID 10001)
RUN groupadd -g 10001 appgroup && \
    useradd -u 10001 -g appgroup -m appuser && \
    chown -R 10001:10001 /app

# Enforce secure least-privilege boundary context
USER 10001:10001

# Default runtime entrypoint command for integration testing
# Disables pytest cache-writing because the filesystem must remain read-only
CMD ["python", "-m", "pytest", "-q", "-p", "no:cacheprovider"]


# ==============================================================================
# STAGE 2: RUNTIME TARGET (PRODUCTION ENVIRONMENT)
# This stage is placed last so that a default "docker build" yields this artifact.
# ==============================================================================
FROM python:3.12-slim-bookworm AS runtime

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Inject the build-time deployment version SHA as an environment variable
ARG APP_VERSION=local
ENV APP_VERSION=${APP_VERSION}

WORKDIR /app

# Copy and install production dependencies only (highly cached layer)
COPY requirements.txt /app/
RUN python -m pip install --no-cache-dir -r requirements.txt

# Copy runtime production source files strictly needed for serving traffic
COPY app/ /app/app/
COPY gunicorn.conf.py /app/

# Re-establish identical secure non-root context parameters (10001:10001)
RUN groupadd -g 10001 appgroup && \
    useradd -u 10001 -g appgroup -m appuser && \
    chown -R 10001:10001 /app

USER 10001:10001

# Informational directive documenting the runtime web-traffic interface port
EXPOSE 8000

# Exec JSON array format allows Gunicorn to catch OS shutdown signals (SIGTERM)
CMD ["gunicorn", "--config", "gunicorn.conf.py", "app:create_app()"]

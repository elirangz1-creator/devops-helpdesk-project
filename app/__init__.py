"""RT Helpdesk: a supplied application for the DevOps final project."""
import json
import logging
import os
import sys
import time
import uuid

import psycopg
from flask import Flask, g, jsonify, render_template, request
from prometheus_client import (
    CONTENT_TYPE_LATEST, CollectorRegistry, Counter, Gauge, GCCollector,
    Histogram, PlatformCollector, ProcessCollector, generate_latest,
)
from werkzeug.exceptions import HTTPException

from app.db import connect, register_commands


def create_app(config=None):
    app = Flask(__name__)
    app.config.from_mapping(
        DB_HOST=os.getenv("DB_HOST", "db"),
        DB_PORT=int(os.getenv("DB_PORT", "5432")),
        DB_NAME=os.getenv("DB_NAME", "helpdesk"),
        DB_USER=os.getenv("DB_USER", "helpdesk_app"),
        DB_PASSWORD=os.getenv("DB_PASSWORD", ""),
        DB_SSLMODE=os.getenv("DB_SSLMODE", "prefer"),
        APP_VERSION=os.getenv("APP_VERSION", "local"),
        APP_ENV=os.getenv("APP_ENV", "development"),
        MAX_CONTENT_LENGTH=16 * 1024,
    )
    if config:
        app.config.update(config)
    if not app.config["DB_PASSWORD"]:
        raise RuntimeError("Set DB_PASSWORD before starting the app")

    app.logger.handlers.clear()
    app.logger.addHandler(logging.StreamHandler(sys.stdout))
    app.logger.setLevel(logging.INFO)
    app.logger.propagate = False
    registry = CollectorRegistry()
    ProcessCollector(registry=registry)
    PlatformCollector(registry=registry)
    GCCollector(registry=registry)
    requests = Counter("helpdesk_http_requests_total", "HTTP responses",
                       ["method", "route", "status"], registry=registry)
    duration = Histogram("helpdesk_http_request_duration_seconds", "Request duration",
                         ["method", "route"], registry=registry,
                         buckets=(.01, .05, .1, .25, .5, 1, 2.5, 5, 10))
    db_up = Gauge("helpdesk_database_up", "Database and tickets table reachable",
                  registry=registry)
    app.extensions["metrics_registry"] = registry

    @app.before_request
    def begin_request():
        g.started = time.monotonic()
        g.request_id = uuid.uuid4().hex

    @app.after_request
    def finish_request(response):
        elapsed = time.monotonic() - g.started
        # Route templates prevent one time series per ticket ID or arbitrary URL.
        route = request.url_rule.rule if request.url_rule else "unmatched"
        method = request.method if request.method in {"GET", "HEAD", "POST", "PATCH", "OPTIONS", "DELETE", "PUT"} else "OTHER"
        if route != "/metrics":
            requests.labels(method, route, str(response.status_code)).inc()
            duration.labels(method, route).observe(elapsed)
            app.logger.info(json.dumps({
                "event": "http_request", "request_id": g.request_id,
                "method": method, "route": route, "status": response.status_code,
                "duration_ms": round(elapsed * 1000, 2),
            }))
        response.headers["X-Request-ID"] = g.request_id
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Cache-Control"] = "no-store"
        return response

    @app.errorhandler(HTTPException)
    def http_error(error):
        return jsonify(error=error.name, message=error.description), error.code

    @app.errorhandler(psycopg.Error)
    def database_error(error):
        # Never log connection strings, SQL parameters or submitted ticket text.
        app.logger.error(json.dumps({"event": "database_error", "type": type(error).__name__}))
        return jsonify(error="database_unavailable", message="Database operation failed"), 503

    def database_ready():
        try:
            with connect() as conn:
                conn.execute("SELECT id FROM helpdesk.tickets LIMIT 1").fetchone()
            db_up.set(1)
            return True
        except psycopg.Error:
            db_up.set(0)
            return False

    @app.get("/")
    def index():
        return render_template("index.html", version=app.config["APP_VERSION"])

    @app.get("/healthz")
    def health():
        # Liveness deliberately does not depend on PostgreSQL.
        return jsonify(status="ok")

    @app.get("/readyz")
    def ready():
        ok = database_ready()
        return jsonify(status="ready" if ok else "not_ready"), 200 if ok else 503

    @app.get("/version")
    def version():
        return jsonify(version=app.config["APP_VERSION"], environment=app.config["APP_ENV"])

    @app.get("/metrics")
    def metrics():
        database_ready()
        return app.response_class(generate_latest(registry), content_type=CONTENT_TYPE_LATEST)

    from app.routes import tickets
    app.register_blueprint(tickets)
    register_commands(app)
    return app

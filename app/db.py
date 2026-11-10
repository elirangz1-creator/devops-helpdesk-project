"""Short-lived PostgreSQL connections: one transaction per operation."""
import time
from pathlib import Path

import click
import psycopg
from flask import current_app
from psycopg.rows import dict_row


def connect():
    cfg = current_app.config
    # Keyword arguments safely handle punctuation in passwords.
    return psycopg.connect(
        host=cfg["DB_HOST"], port=cfg["DB_PORT"], dbname=cfg["DB_NAME"],
        user=cfg["DB_USER"], password=cfg["DB_PASSWORD"],
        sslmode=cfg["DB_SSLMODE"], connect_timeout=3,
        options="-c statement_timeout=5000 -c lock_timeout=3000",
        row_factory=dict_row,
    )


def init_schema():
    # Run once as a deployment step, NOT in each web worker's startup path.
    with connect() as conn:
        conn.execute("SELECT pg_advisory_xact_lock(865421)")
        conn.execute(Path(__file__).with_name("schema.sql").read_text(encoding="utf-8"))


def register_commands(app):
    @app.cli.command("init-db")
    @click.option("--attempts", type=click.IntRange(1, 30), default=10)
    def init_db(attempts):
        """Create the initial schema without deleting existing tickets."""
        for attempt in range(attempts):
            try:
                init_schema()
                click.echo("Database schema ready")
                return
            except psycopg.OperationalError:
                if attempt + 1 == attempts:
                    raise click.ClickException("Database unavailable; check DB settings and server health") from None
                time.sleep(1)
        # DDL/permission errors are intentionally not retried forever.

    @app.cli.command("seed-db")
    def seed_db():
        """Insert five fictional tickets. Re-running does not duplicate them."""
        samples = [
            ("demo-1", "Cannot connect to training VM", "SSH connection times out.", "Demo Student A", "open"),
            ("demo-2", "Course recording missing", "The latest recording is not visible.", "Demo Student B", "open"),
            ("demo-3", "Docker image fails to start", "Please check the supplied configuration.", "Demo Student C", "open"),
            ("demo-4", "Lab access restored", "Access was restored after checking permissions.", "Demo Student D", "closed"),
            ("demo-5", "בקשת גישה למעבדה", "זוהי פנייה לדוגמה בלבד.", "סטודנט לדוגמה", "open"),
        ]
        with connect() as conn:
            for row in samples:
                conn.execute(
                    """INSERT INTO helpdesk.tickets(seed_key, title, description, requester, status)
                       VALUES (%s, %s, %s, %s, %s) ON CONFLICT (seed_key) DO NOTHING""", row)
        click.echo("Demo tickets ready")

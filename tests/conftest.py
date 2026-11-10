import os

import pytest

from app import create_app
from app.db import connect, init_schema


@pytest.fixture
def app():
    return create_app({"TESTING": True, "DB_PASSWORD": os.getenv("DB_PASSWORD", "unit-test-only"), "APP_VERSION": "test-sha"})


@pytest.fixture
def client(app):
    return app.test_client()


@pytest.fixture
def db_app():
    if os.getenv("RUN_DB_TESTS") != "1":
        pytest.skip("Set RUN_DB_TESTS=1 and point DB_* to a disposable PostgreSQL test database")
    name = os.getenv("DB_NAME", "")
    if not name.endswith("_test"):
        pytest.fail("Refusing to clear data: DB_NAME must end in _test")
    app = create_app({"TESTING": True})
    with app.app_context():
        with connect() as conn:
            conn.execute("CREATE SCHEMA IF NOT EXISTS helpdesk")
        init_schema()
        with connect() as conn:
            conn.execute("TRUNCATE helpdesk.tickets RESTART IDENTITY")
    yield app


@pytest.fixture
def db_client(db_app):
    return db_app.test_client()

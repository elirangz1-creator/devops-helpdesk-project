import pytest
import psycopg

from app.db import connect, init_schema

pytestmark = pytest.mark.integration


def make_ticket(client, title="Demo issue"):
    response = client.post("/api/tickets", json={"title": title, "requester": "Student", "description": "Demo details"})
    assert response.status_code == 201
    return response.json


def test_create_list_read_close_reopen(db_client):
    ticket = make_ticket(db_client)
    assert ticket["status"] == "open"
    assert db_client.get("/api/tickets").json["items"][0]["id"] == ticket["id"]
    assert db_client.get(f"/api/tickets/{ticket['id']}").json["title"] == "Demo issue"
    for state in ("closed", "open"):
        response = db_client.patch(f"/api/tickets/{ticket['id']}", json={"status": state})
        assert response.status_code == 200
        assert response.json["status"] == state


def test_missing_ticket(db_client):
    assert db_client.get("/api/tickets/999").status_code == 404
    assert db_client.patch("/api/tickets/999", json={"status": "closed"}).status_code == 404


def test_sql_injection_is_data_and_unicode_roundtrips(db_client):
    value = "'); DROP TABLE helpdesk.tickets; -- שלום"
    ticket = make_ticket(db_client, value)
    assert db_client.get(f"/api/tickets/{ticket['id']}").json["title"] == value
    assert len(db_client.get("/api/tickets").json["items"]) == 1


def test_pagination(db_client):
    for n in range(3):
        make_ticket(db_client, f"Issue {n}")
    first = db_client.get("/api/tickets?limit=2").json
    second = db_client.get("/api/tickets?limit=2&offset=2").json
    assert first["has_more"] is True
    assert second["has_more"] is False
    assert len({item["id"] for item in first["items"]+second["items"]}) == 3


def test_database_rejects_invalid_status(db_app):
    with db_app.app_context():
        with pytest.raises(psycopg.errors.CheckViolation):
            with connect() as conn:
                conn.execute("INSERT INTO helpdesk.tickets(title,requester,status) VALUES ('x','y','invalid')")


def test_init_and_seed_are_repeatable_without_data_loss(db_app, db_client):
    ticket = make_ticket(db_client)
    with db_app.app_context():
        init_schema()
        init_schema()
    runner = db_app.test_cli_runner()
    assert runner.invoke(args=["seed-db"]).exit_code == 0
    assert runner.invoke(args=["seed-db"]).exit_code == 0
    assert len(db_client.get("/api/tickets").json["items"]) == 6
    assert db_client.get(f"/api/tickets/{ticket['id']}").status_code == 200


def test_health_readiness_and_metrics(db_client):
    assert db_client.get("/healthz").status_code == 200
    assert db_client.get("/readyz").status_code == 200
    make_ticket(db_client)
    text = db_client.get("/metrics").text
    assert "helpdesk_database_up 1.0" in text
    assert 'method="POST",route="/api/tickets",status="201"' in text
    assert "helpdesk_http_request_duration_seconds_bucket" in text


def test_separate_app_instances_share_persistent_data(db_app, db_client):
    from app import create_app
    ticket = make_ticket(db_client)
    second = create_app({"TESTING": True}).test_client()
    assert second.get(f"/api/tickets/{ticket['id']}").json["title"] == ticket["title"]

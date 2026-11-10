import pytest
import psycopg
from app import create_app


def test_health_does_not_connect(client, monkeypatch):
    monkeypatch.setattr("app.connect", lambda: (_ for _ in ()).throw(AssertionError("No DB access allowed")))
    assert client.get("/healthz").json == {"status": "ok"}


def test_version_and_request_id(client):
    response = client.get("/version")
    assert response.json["version"] == "test-sha"
    assert len(response.headers["X-Request-ID"]) == 32


def test_web_page_and_assets(client):
    assert b"RT Helpdesk" in client.get("/").data
    assert client.get("/static/app.js").status_code == 200


@pytest.mark.parametrize("body", [None, [], {}, {"title": "", "requester": "A"}, {"title": 3, "requester": "A"}, {"title": "x"*121, "requester": "A"}, {"title": "ok", "requester": " "}, {"title": "ok", "requester": "A", "extra": True}, {"title": "ok", "requester": "A", "description": "x"*2001}, {"title": "bad\x00", "requester": "A"}])
def test_invalid_ticket_input(client, body):
    import json
    assert client.post("/api/tickets", data=json.dumps(body), content_type="application/json").status_code == 400


@pytest.mark.parametrize("query", ["limit=0", "limit=101", "offset=-1", "limit=bad", "offset=1000001"])
def test_invalid_pagination(client, query):
    assert client.get("/api/tickets?"+query).status_code == 400


@pytest.mark.parametrize("body", [{}, {"status": "pending"}, {"status": []}, {"status": "closed", "title": "x"}])
def test_invalid_status(client, body):
    assert client.patch("/api/tickets/1", json=body).status_code == 400


def test_content_types_and_limits(client):
    assert client.post("/api/tickets", data="x").status_code == 415
    assert client.post("/api/tickets", data="{", content_type="application/json").status_code == 400
    assert client.post("/api/tickets", data="x"*17000, content_type="application/json").status_code == 413


def test_not_found_json(client):
    assert client.get("/does-not-exist").status_code == 404
    assert client.get("/api/tickets/99999999999999999999999").status_code == 404


def test_readiness_database_failure(client, monkeypatch):
    def fail():
        raise psycopg.OperationalError("sensitive connection details")
    monkeypatch.setattr("app.connect", fail)
    assert client.get("/readyz").status_code == 503
    assert client.get("/healthz").status_code == 200
    metrics = client.get("/metrics")
    assert metrics.status_code == 200
    assert b"helpdesk_database_up 0.0" in metrics.data
    assert b"sensitive" not in metrics.data


def test_database_failure_response_redacts_details(client, monkeypatch):
    def fail():
        raise psycopg.OperationalError("password=secret123")
    monkeypatch.setattr("app.routes.connect", fail)
    response = client.get("/api/tickets")
    assert response.status_code == 503
    assert b"secret123" not in response.data


def test_metrics_route_labels_do_not_contain_urls(client, monkeypatch):
    def fail():
        raise psycopg.OperationalError()
    monkeypatch.setattr("app.connect", fail)
    client.get("/private-unique-path")
    text = client.get("/metrics").text
    assert 'route="unmatched"' in text
    assert "private-unique-path" not in text


def test_missing_password_fails_startup(monkeypatch):
    monkeypatch.delenv("DB_PASSWORD", raising=False)
    with pytest.raises(RuntimeError, match="DB_PASSWORD"):
        create_app()

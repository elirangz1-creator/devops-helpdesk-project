from flask import Blueprint, abort, jsonify, request, url_for

from app.db import connect

tickets = Blueprint("tickets", __name__, url_prefix="/api/tickets")
FIELDS = "id, title, description, requester, status, created_at, updated_at"


def serialize(row):
    result = dict(row)
    for field in ("created_at", "updated_at"):
        result[field] = result[field].isoformat()
    return result


def json_object(allowed):
    value = request.get_json()  # Flask returns 415 for non-JSON and 400 for malformed JSON.
    if not isinstance(value, dict):
        abort(400, description="Expected a JSON object")
    if set(value) - allowed:
        abort(400, description="Unexpected field")
    return value


def text_value(data, name, maximum, required=True):
    value = data.get(name, "")
    if not isinstance(value, str):
        abort(400, description=f"{name} must be a string")
    value = value.strip()
    if "\x00" in value or (required and not value) or len(value) > maximum:
        abort(400, description=f"{name} must contain {'1' if required else '0'} to {maximum} characters and no null bytes")
    return value


@tickets.get("")
def list_tickets():
    try:
        limit = int(request.args.get("limit", "20"))
        offset = int(request.args.get("offset", "0"))
    except ValueError:
        abort(400, description="limit and offset must be integers")
    if not 1 <= limit <= 100 or not 0 <= offset <= 1_000_000:
        abort(400, description="limit must be 1..100 and offset 0..1000000")
    with connect() as conn:
        rows = conn.execute(
            f"SELECT {FIELDS} FROM helpdesk.tickets ORDER BY created_at DESC, id DESC LIMIT %s OFFSET %s",
            (limit + 1, offset),
        ).fetchall()
    return jsonify(items=[serialize(r) for r in rows[:limit]], limit=limit, offset=offset, has_more=len(rows) > limit)


@tickets.post("")
def create_ticket():
    data = json_object({"title", "description", "requester"})
    values = (text_value(data, "title", 120), text_value(data, "description", 2000, False), text_value(data, "requester", 80))
    with connect() as conn:
        row = conn.execute(
            f"INSERT INTO helpdesk.tickets(title, description, requester) VALUES (%s, %s, %s) RETURNING {FIELDS}", values
        ).fetchone()
    return jsonify(serialize(row)), 201, {"Location": url_for("tickets.get_ticket", ticket_id=row["id"])}


@tickets.get("/<int:ticket_id>")
def get_ticket(ticket_id):
    if ticket_id > 9223372036854775807:
        abort(404)
    with connect() as conn:
        row = conn.execute(f"SELECT {FIELDS} FROM helpdesk.tickets WHERE id=%s", (ticket_id,)).fetchone()
    if row is None:
        abort(404, description="Ticket not found")
    return jsonify(serialize(row))


@tickets.patch("/<int:ticket_id>")
def update_status(ticket_id):
    data = json_object({"status"})
    if data.get("status") not in ("open", "closed"):
        abort(400, description="status must be open or closed")
    if ticket_id > 9223372036854775807:
        abort(404)
    with connect() as conn:
        row = conn.execute(
            f"UPDATE helpdesk.tickets SET status=%s, updated_at=CURRENT_TIMESTAMP WHERE id=%s RETURNING {FIELDS}",
            (data["status"], ticket_id),
        ).fetchone()
    if row is None:
        abort(404, description="Ticket not found")
    return jsonify(serialize(row))

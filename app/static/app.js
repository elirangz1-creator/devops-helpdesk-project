let offset = 0;
const limit = 10;
const notice = document.getElementById('notice');
function message(text, error = false) { notice.textContent = text; notice.className = error ? 'error' : 'success'; }
async function api(path, options = {}) {
  const response = await fetch(path, options);
  const data = await response.json();
  if (!response.ok) throw new Error(data.message || data.error || 'Request failed');
  return data;
}
async function load() {
  try {
    const data = await api(`/api/tickets?limit=${limit}&offset=${offset}`);
    const list = document.getElementById('tickets'); list.replaceChildren();
    if (!data.items.length) { const p = document.createElement('p'); p.textContent = 'No tickets on this page.'; list.append(p); }
    for (const ticket of data.items) {
      const item = document.createElement('article');
      const heading = document.createElement('h3'); heading.textContent = `#${ticket.id} ${ticket.title}`;
      const meta = document.createElement('p'); meta.className = 'meta'; meta.textContent = `${ticket.requester} · ${new Date(ticket.created_at).toLocaleString()} · ${ticket.status}`;
      const detail = document.createElement('p'); detail.textContent = ticket.description; detail.className = 'description'; detail.dir = 'auto';
      const toggle = document.createElement('button'); toggle.className = 'secondary'; toggle.textContent = ticket.status === 'open' ? 'Close ticket' : 'Reopen ticket';
      toggle.addEventListener('click', async () => {
        toggle.disabled = true;
        try { await api(`/api/tickets/${ticket.id}`, {method: 'PATCH', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({status: ticket.status === 'open' ? 'closed' : 'open'})}); await load(); message('Ticket updated.'); }
        catch (error) { message(error.message, true); toggle.disabled = false; }
      });
      item.append(heading, meta, detail, toggle); list.append(item);
    }
    document.getElementById('previous').disabled = offset === 0;
    document.getElementById('next').disabled = !data.has_more;
    document.getElementById('page').textContent = `Page ${offset / limit + 1}`;
  } catch (error) { message(error.message, true); }
}
document.getElementById('ticket-form').addEventListener('submit', async (event) => {
  event.preventDefault(); const form = event.target; const button = form.querySelector('button'); button.disabled = true;
  try { await api('/api/tickets', {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(Object.fromEntries(new FormData(form)))}); form.reset(); offset = 0; await load(); message('Ticket created.'); }
  catch (error) { message(error.message, true); }
  finally { button.disabled = false; }
});
document.getElementById('refresh').addEventListener('click', load);
document.getElementById('previous').addEventListener('click', () => { offset = Math.max(0, offset - limit); load(); });
document.getElementById('next').addEventListener('click', () => { offset += limit; load(); });
load();

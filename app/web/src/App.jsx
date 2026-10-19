import { useCallback, useEffect, useState } from 'react';

// Minimal UI: shows which region served the request and lets you add/list items.
// data-testid attributes are the contract for the Playwright regression suite.
export default function App() {
  const [info, setInfo] = useState(null);
  const [items, setItems] = useState([]);
  const [text, setText] = useState('');
  const [error, setError] = useState('');

  const load = useCallback(async () => {
    setError('');
    try {
      const [i, list] = await Promise.all([
        fetch('/api/info').then((r) => r.json()),
        fetch('/api/items').then((r) => (r.ok ? r.json() : [])),
      ]);
      setInfo(i);
      setItems(list);
    } catch {
      setError('API unreachable');
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  async function addItem(e) {
    e.preventDefault();
    setError('');
    const res = await fetch('/api/items', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text }),
    });
    if (res.status === 201) {
      setText('');
      await load();
    } else {
      const body = await res.json().catch(() => ({}));
      setError(body.error ?? `Save failed (${res.status})`);
    }
  }

  return (
    <main>
      <h1>tflab-aws</h1>

      <section className="card" data-testid="region-card">
        <h2>Served by</h2>
        {info ? (
          <dl>
            <dt>Region</dt>
            <dd data-testid="region">{info.region}</dd>
            <dt>Database</dt>
            <dd data-testid="db-mode">
              {info.dbWritable === true ? 'writable' : info.dbWritable === false ? 'read-only standby' : 'unreachable'}
            </dd>
            <dt>Pod</dt>
            <dd data-testid="pod">{info.pod}</dd>
            <dt>Version</dt>
            <dd>{info.version}</dd>
          </dl>
        ) : (
          <p>Loading…</p>
        )}
      </section>

      <section className="card">
        <h2>Items</h2>
        <form onSubmit={addItem}>
          <label htmlFor="item-text">New item</label>
          <input
            id="item-text"
            data-testid="item-input"
            value={text}
            maxLength={200}
            onChange={(e) => setText(e.target.value)}
            required
          />
          <button type="submit" data-testid="item-submit">
            Add
          </button>
        </form>
        {error && (
          <p role="alert" data-testid="error">
            {error}
          </p>
        )}
        <ul data-testid="item-list">
          {items.map((it) => (
            <li key={it.id}>
              {it.text} <small>({it.region})</small>
            </li>
          ))}
        </ul>
      </section>
    </main>
  );
}

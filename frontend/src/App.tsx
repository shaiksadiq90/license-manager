import { useEffect, useState } from "react";

type License = { id: number; name: string; seats: number; status: string };

export default function App() {
  const [rows, setRows] = useState<License[]>([]);
  const [name, setName] = useState(""); const [seats, setSeats] = useState(1);
  const [error, setError] = useState("");

  const load = async () => setRows(await (await fetch("/api/licenses")).json());
  useEffect(() => { load(); }, []);

  const add = async () => {
    const r = await fetch("/api/licenses", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ name, seats }) });
    if (!r.ok) { setError((await r.json()).error); return; }
    setError(""); setName(""); setSeats(1); load();
  };
  const remove = async (id: number) => { await fetch(`/api/licenses/${id}`, { method: "DELETE" }); load(); };
  const toggle = async (l: License) => {
    await fetch(`/api/licenses/${l.id}`, { method: "PUT", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ status: l.status === "active" ? "suspended" : "active" }) });
    load();
  };

  return (
    <main style={{ fontFamily: "system-ui", maxWidth: 720, margin: "40px auto", padding: 16 }}>
      <h1>License Manager</h1>
      <div style={{ display: "flex", gap: 8 }}>
        <input placeholder="Product name" value={name} onChange={e => setName(e.target.value)} />
        <input type="number" min={1} value={seats} onChange={e => setSeats(+e.target.value)} style={{ width: 80 }} />
        <button onClick={add}>Add license</button>
      </div>
      {error && <p style={{ color: "crimson" }}>{error}</p>}
      <table style={{ width: "100%", marginTop: 16, borderCollapse: "collapse" }}>
        <thead><tr><th align="left">Name</th><th>Seats</th><th>Status</th><th></th></tr></thead>
        <tbody>{rows.map(l => (
          <tr key={l.id} style={{ borderTop: "1px solid #ddd" }}>
            <td>{l.name}</td><td align="center">{l.seats}</td>
            <td align="center"><button onClick={() => toggle(l)}>{l.status}</button></td>
            <td align="right"><button onClick={() => remove(l.id)}>Delete</button></td>
          </tr>))}</tbody>
      </table>
    </main>
  );
}

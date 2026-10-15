CREATE TABLE IF NOT EXISTS licenses (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  seats INTEGER NOT NULL CHECK (seats > 0),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','suspended','expired')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS users (id SERIAL PRIMARY KEY, email TEXT UNIQUE NOT NULL);
CREATE TABLE IF NOT EXISTS license_assignments (
  license_id INTEGER REFERENCES licenses(id) ON DELETE CASCADE,
  user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
  PRIMARY KEY (license_id, user_id)
);

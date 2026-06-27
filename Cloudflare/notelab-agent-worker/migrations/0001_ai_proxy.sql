CREATE TABLE IF NOT EXISTS subscriptions (
  original_transaction_id TEXT PRIMARY KEY,
  product_id TEXT NOT NULL,
  status TEXT NOT NULL,
  expires_at TEXT,
  last_verified_at TEXT NOT NULL,
  environment TEXT,
  raw_payload_hash TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS quota_periods (
  original_transaction_id TEXT NOT NULL,
  period TEXT NOT NULL,
  allowance INTEGER NOT NULL,
  used INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (original_transaction_id, period)
);

CREATE TABLE IF NOT EXISTS idempotency_keys (
  original_transaction_id TEXT NOT NULL,
  idempotency_key TEXT NOT NULL,
  endpoint TEXT NOT NULL,
  response_json TEXT,
  credit_cost INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  PRIMARY KEY (original_transaction_id, idempotency_key)
);

CREATE TABLE IF NOT EXISTS usage_events (
  id TEXT PRIMARY KEY,
  original_transaction_id TEXT NOT NULL,
  endpoint TEXT NOT NULL,
  credit_cost INTEGER NOT NULL,
  status INTEGER NOT NULL,
  latency_ms INTEGER NOT NULL,
  model_error_code TEXT,
  estimated_cost_usd REAL,
  created_at TEXT NOT NULL
);

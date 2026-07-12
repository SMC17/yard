PRAGMA foreign_keys = ON;

CREATE TABLE seasons (
  season_id TEXT PRIMARY KEY,
  mission_id TEXT NOT NULL,
  mission_version TEXT NOT NULL,
  ruleset_id TEXT NOT NULL,
  state TEXT NOT NULL CHECK (state IN ('draft', 'open', 'closed', 'revealed')),
  manifest_json TEXT NOT NULL,
  manifest_sha256 TEXT NOT NULL CHECK (length(manifest_sha256) = 64),
  signature_json TEXT NOT NULL,
  mission_artifact_sha256 TEXT NOT NULL CHECK (length(mission_artifact_sha256) = 64),
  evaluator_artifact_sha256 TEXT NOT NULL CHECK (length(evaluator_artifact_sha256) = 64),
  hidden_manifest_sha256 TEXT NOT NULL CHECK (length(hidden_manifest_sha256) = 64),
  evaluator_version TEXT NOT NULL,
  resource_policy_json TEXT NOT NULL,
  created_at TEXT NOT NULL,
  revealed_at TEXT,
  reveal_artifact_sha256 TEXT
);

CREATE TABLE artifacts (
  sha256 TEXT PRIMARY KEY CHECK (length(sha256) = 64),
  kind TEXT NOT NULL CHECK (kind IN ('agent-binary', 'evaluator-binary', 'mission', 'hidden-season', 'season-manifest')),
  size_bytes INTEGER NOT NULL CHECK (size_bytes >= 0),
  r2_key TEXT NOT NULL UNIQUE,
  uploaded_at TEXT NOT NULL
);

CREATE TABLE submissions (
  submission_id TEXT PRIMARY KEY,
  season_id TEXT NOT NULL REFERENCES seasons(season_id),
  idempotency_key TEXT NOT NULL,
  source_kind TEXT NOT NULL CHECK (source_kind IN ('declarative', 'agent_binary')),
  track TEXT NOT NULL CHECK (track IN ('declared_human', 'human_ai', 'autonomous_agent', 'exhibition')),
  entrant TEXT NOT NULL,
  request_json TEXT NOT NULL,
  request_sha256 TEXT NOT NULL CHECK (length(request_sha256) = 64),
  agent_artifact_sha256 TEXT,
  created_at TEXT NOT NULL,
  UNIQUE (season_id, idempotency_key)
);

CREATE TABLE runs (
  run_id TEXT PRIMARY KEY,
  season_id TEXT NOT NULL REFERENCES seasons(season_id),
  submission_id TEXT NOT NULL REFERENCES submissions(submission_id),
  idempotency_key TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('queued', 'running_agent', 'running_evaluator', 'completed', 'failed')),
  attempts INTEGER NOT NULL DEFAULT 0,
  submission_sha256 TEXT,
  submission_r2_key TEXT,
  result_r2_key TEXT,
  replay_r2_key TEXT,
  scorecard_r2_key TEXT,
  envelope_r2_key TEXT,
  envelope_sha256 TEXT,
  error_code TEXT,
  error_detail TEXT,
  created_at TEXT NOT NULL,
  started_at TEXT,
  finished_at TEXT,
  UNIQUE (season_id, idempotency_key)
);

CREATE TABLE objectives (
  run_id TEXT NOT NULL REFERENCES runs(run_id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  direction TEXT NOT NULL CHECK (direction IN ('minimize', 'maximize')),
  epsilon REAL NOT NULL CHECK (epsilon >= 0),
  value REAL NOT NULL,
  PRIMARY KEY (run_id, name)
);

CREATE TABLE audit_events (
  sequence INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id TEXT,
  event_type TEXT NOT NULL,
  detail_json TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE INDEX idx_runs_board ON runs(season_id, status, finished_at);
CREATE INDEX idx_submissions_season ON submissions(season_id, track);
CREATE INDEX idx_audit_run ON audit_events(run_id, sequence);

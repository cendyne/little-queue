CREATE TABLE schema_migrations (version text primary key)
CREATE TABLE queue (
  id integer primary key,
  created_at integer not null default(strftime('%s', 'now')),
  name text unique not null,
  dead_queue_id integer,
  max_pulls integer not null default 5
, timeout integer not null default 60)
CREATE TABLE job (
  id text primary key,
  queue_id integer not null,
  insert_date integer not null default(strftime('%s', 'now')),
  priority_date integer not null default(strftime('%s', 'now')),
  invisible_until_date integer not null default(strftime('%s', 'now') - 1),
  content blob not null default '',
  content_type text not null default 'application/octet-stream',
  content_length integer not null default 0,
  pulls integer not null default 0
)
CREATE INDEX job_priority on job(queue_id, priority_date)

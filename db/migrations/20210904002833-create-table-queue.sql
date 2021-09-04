-- up
create table queue (
  id integer primary key,
  created_at integer not null default(strftime('%s', 'now')),
  name text unique not null,
  dead_queue_id integer,
  max_pulls integer not null default 5
)

-- down
drop table queue
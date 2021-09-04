-- up
create table job (
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

-- down
drop table job
-- up
alter table queue add column timeout integer not null default 60

-- down
alter table queue drop column timeout
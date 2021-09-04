-- up
create index job_priority on job(queue_id, priority_date)

-- down
drop index job_priority
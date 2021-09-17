# Little Queue

This is a very basic queue service intended for one owner to use, it is single tenant.

## GET /queues

Results look like
```json
{
  "queues": [
    {
      "max-pulls": 5,
      "name": "image-resizing-dead"
    },
    {
      "max-pulls": 3,
      "dead-name": "image-resizing-dead",
      "name": "image-resizing"
    },
    {
      "max-pulls": 3,
      "name": "processed"
    }
  ]
}
```

## PUT /queues/{queue}

Upsert a queue by name in the path. The request can be a partial version.
So if `max-pulls` is not set, it won't be changed.

Request looks like for `PUT /queues/image-processed`
```json
{
	"max-pulls": 3,
	"dead-queue-name": "image-processed-dead"
}
```

With a response like

```json
{
  "dead-queue-name": "image-processed-dead",
  "name": "image-processed",
  "max-pulls": 3,
  "timeout": 60
}
```

All details will be resturned.

## PUT /queues/{queue}/job

Request can be anything, make sure content type is also set.

Response looks like
```json
{
  "content-type": "application/json",
  "priority-date": 1631498198,
  "id": "K7dLj9QrWAuiAM8JoF19TQ",
  "insert-date": 1631498198,
  "invisible-until-date": 1631498197,
  "content-length": 811564
}
```

## GET /queues/{queue}/job

Will return 1 job by default, add query parameter `?limit=10` to pull
10 jobs at a time.

The response will look like
```json
{
  "jobs": [
    "Mh9MQiR6eNRIW4gvLcAm-Q"
  ]
}
```

The list of strings contains IDs used to get a job.

This endpoint WILL affect the visibility of all jobs returned.

If it has been pulled too many times, it will be put into the dead
queue. If there is no dead queue, it will be dropped.

## GET /job/{job}

The response will be the same content as what was PUT in earlier.
You could even send word documents this way.

Reading this endpoint does NOT affect the visibility of the job.

## DELETE /job/{job}

This will mark the job as completed and it will be deleted.

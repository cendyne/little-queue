(use janetls)
(use joy)
(import ./secrets)
(import ./middleware)
(import json)

(defn load-secrets [] (and
  (secrets/admin-token)
  true))

(defn index [request] (application/json {}))

(defn queues-handler [request]
  (def queues (db/query "select q.name, q.max_pulls, dq.name as dead_name from queue q left join queue dq on q.dead_queue_id = dq.id"))
  (application/json {
    :queues queues
  }))
(def queues (middleware/with-authentication queues-handler))


(def- lookup-queue-sql-by-name (string
    "select * "
    "from queue "
    "where name = :name"))
(defn- find-queue-by-name [name]
  (when (and name (not (empty? name)))
    (as-> lookup-queue-sql-by-name ?
      (db/query ? {:name name})
      (get ? 0))))

(defn- find-queue-by-id [id]
  (when id
    (as-> "select * from queue where id = :id" ?
      (db/query ? {:id id})
      (get ? 0))))

(defn- create-queue [name &opt dead-queue-id max-pulls]
  (default max-pulls 5)
  (db/insert :queue {
    :name name
    :dead-queue-id :dead-queue-id
    :max-pulls max-pulls
  }))
(defn- update-queue [queue props]
  (if (not (empty? props))
    (db/update :queue queue props)
    queue
    ))

(defn put-queue-handler [request]
  (def route-name (get-in request [:params :name]))
  (when (or (nil? route-name) (= "" route-name)) (error "Name cannot be empty"))
  (def max-pulls (get-in request [:body :max-pulls]))
  (def dead-queue-name (get-in request [:body :dead-queue-name]))
  (var timeout nil)
  (if-let [
    user-timeout (get-in request [:body :timeout])
    user-timeout (scan-number user-timeout)
    ] (set timeout (max 1 timeout)))
  (var queue (find-queue-by-name route-name))
  (var dead-queue (if dead-queue-name (find-queue-by-name dead-queue-name)))

  (when (and (nil? dead-queue) dead-queue-name (not= :null dead-queue-name))
    (set dead-queue (create-queue dead-queue-name)))

  (unless queue
    (set queue (create-queue route-name)))
  (var dead-queue-id (or
    (get dead-queue :id)
    (get queue :dead-queue-id)))
  (set queue (update-queue queue {
    :max-pulls max-pulls
    :dead-queue-id dead-queue-id
    :timeout timeout
    }))

  (application/json {
    :name route-name
    :max-pulls (get queue :max-pulls)
    :dead-queue-name (get dead-queue :name)
    :timeout (get queue :timeout)
  }))
(def put-queue (middleware/json (middleware/with-authentication put-queue-handler)))

(defn get-queue-handler [request]
  (def route-name (get-in request [:params :name]))
  (when (or (nil? route-name) (= "" route-name)) (error "Name cannot be empty"))
  (def queue (find-queue-by-name route-name))
  (def dead-queue (find-queue-by-id (get queue :dead-queue-id)))

  (application/json {
    :name route-name
    :max-pulls (get queue :max-pulls)
    :dead-queue-name (get dead-queue :name)
  }))
(def get-queue (middleware/with-authentication get-queue-handler))

(defn generate-id [&opt len count]
  (default len 16)
  (default count 0)
  (when (< 128 count) (error "Could not make a random ID"))
  (def value (encoding/encode (util/random len) :base64 :url-unpadded))
  (cond
    (or (string/has-prefix? "-" value) (string/has-prefix? "_" value))
    (generate-id len (+ 1 count))
    (or (string/has-prefix? "-" value) (string/has-prefix? "_" value))
    (generate-id len (+ 1 count))
    value
  ))

(defn put-job-handler [request]
  (def route-name (get-in request [:params :name]))
  (when (or (nil? route-name) (= "" route-name)) (error "Name cannot be empty"))
  (def queue (find-queue-by-name route-name))
  (def content-type (or
    (get-in request [:headers "Content-Type"])
    (get-in request [:headers "content-type"])
    ))
  (def content (get request :body ""))
  (def content-length (length content))
  (when (= 0 content-length) (error "Content length cannot be 0"))
  (def id (generate-id))
  (def now (os/time))
  (var delay -1)
  (if-let [
    user-delay (get-in request [:query-string :delay])
    user-delay (scan-number user-delay)
    ] (set delay (max -1 delay)))
  (var priority 0)
  (if-let [
    user-priority (get-in request [:query-string :priority])
    user-priority (scan-number user-priority)
    ] (set priority (max -10000 priority)))
  (def priority-date (+ now priority))
  (def invisible-until-date (+ now delay))
  (def queue-id (get queue :id))

  (def job (db/insert :job {
    :id id
    :queue-id queue-id
    :insert-date now
    :priority-date priority-date
    :invisible-until-date invisible-until-date
    :content content
    :content-type content-type
    :content-length content-length
  }))
  (when (nil? job) (error "Could not save job"))

  (application/json {
    :content-type content-type
    :content-length content-length
    :id id
    # TODO render dates in ISO8601
    :priority-date priority-date
    :invisible-until-date invisible-until-date
    :insert-date now
  }))
(def put-job (middleware/with-authentication put-job-handler))

(defn get-job-handler [request]
  (def id (get-in request [:params :id]))
  (when (or (nil? id) (= "" id)) (error "id cannot be empty"))
  (def job (as-> "select * from job where id = :id" ?
    (db/query ? {:id id})
    (get ? 0)))
  (if job
    @{
      :status 200
      :headers @{"Content-Type" (get job :content-type)}
      :body (get job :content)
      }
    @{:status 404 :body "not found"}))
(def get-job (middleware/with-authentication get-job-handler))

(defn delete-job-handler [request]
  (def id (get-in request [:params :id]))
  (when (or (nil? id) (= "" id)) (error "id cannot be empty"))
  (def job (as-> "select * from job where id = :id" ?
    (db/query ? {:id id})
    (get ? 0)))
  (when job
    (db/delete :job id))
  (if job
    @{:status 200 :body "OK"}
    @{:status 404 :body "not found"}))
(def delete-job (middleware/with-authentication delete-job-handler))

(def- prioritized-search-sql (string
  "select j.id "
  "from job j "
  "join queue q on j.queue_id = q.id "
  "where j.pulls < q.max_pulls and j.invisible_until_date <= :now "
  "order by priority_date "
  "limit :limit"
))
(def- pull-sql (string
  "update job "
  "set pulls = pulls + 1, "
  "invisible_until_date = :invis "
  "where id = :id"
))
(defn get-queue-job-handler [request]
  (def route-name (get-in request [:params :name]))
  (when (or (nil? route-name) (= "" route-name)) (error "Name cannot be empty"))
  (def queue (find-queue-by-name route-name))
  (def dead-queue (find-queue-by-id (get queue :dead-queue-id)))
  (def now (os/time))
  (def invis (+ now (get queue :timeout)))
  (var limit 1)
  (if-let [
    user-limit (get-in request [:query-string :limit])
    user-limit (scan-number user-limit)
    ] (set limit (min 100 user-limit)))
  (def ids @[])
  (db/with-transaction
    (array/clear ids)
    (def jobs (db/query prioritized-search-sql {:limit limit :now now}))
    (each job jobs
      (def id (get job :id))
      (printf "%s %p" pull-sql {:id id :invis invis})
      (db/query pull-sql {:id id :invis invis})
      (array/push ids id)))

  (application/json {
    :jobs ids
  }))
(def get-queue-job (middleware/with-authentication get-queue-job-handler))

(route :get "/" index :index)
(route :get "/queues" queues :queues)
(route :get "/queues/:name" get-queue :get-queue)
(route :put "/queues/:name" put-queue :put-queue)
(route :put "/queues/:name/job" put-job :put-job)
(route :get "/queues/:name/job" get-queue-job :get-queue-job)
(route :get "/job/:id" get-job :get-job)
(route :delete "/job/:id" delete-job :delete-job)

(def app (-> (handler)
             (middleware/authorization)
             (extra-methods)
             (query-string)
             (server-error)
             (not-found)
             (logger)
             ))

(defn main [& args]
  # Stuff must be available for the runtime within main
  (unless (load-secrets) (error "Could not load secrets"))
  (db/migrate (env :database-url))
  (db/connect (env :database-url))

  (let [port (get args 1 (or (env :port) "9000"))
        host (get args 2 (or (env :host) "localhost"))
        ]
    (server app port host 100000000)))

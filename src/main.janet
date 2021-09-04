(use janetls)
(use joy)
(import ./secrets)
(import ./middleware)

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
    }))

  (application/json {
    :name route-name
    :max-pulls (get queue :max-pulls)
    :dead-queue-name (get dead-queue :name)
  }))
(def put-queue (middleware/with-authentication put-queue-handler))

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

(route :get "/" index :index)
(route :get "/queues" queues :queues)
(route :get "/queues/:name" get-queue :get-queue)
(route :put "/queues/:name" put-queue :put-queue)

(def app (-> (handler)
             (middleware/authorization)
             (extra-methods)
             (query-string)
             (middleware/json)
             (server-error)
             (middleware/static-files)
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

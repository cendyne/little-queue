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

(route :get "/" index :index)
(route :get "/queues" queues :queues)

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
  (db/connect (env :database-url))
  (let [port (get args 1 (or (env :port) "9000"))
        host (get args 2 (or (env :host) "localhost"))
        ]
    (server app port host 100000000)))

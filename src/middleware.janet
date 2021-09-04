(use joy)
(use janetls)
(import json)
(import ./secrets)
(import path)

(def- authorization-parser (peg/compile '{
  :S+ (some :S)
  :basic (sequence '"Basic" :s+ (constant :token) (capture :S+) :s*)
  :bearer (sequence '"Bearer" :s+ (constant :token) (capture :S+) :s*)
  :keyword (<- (some (choice :w "-" "_" "/" "%")))
  :value (* (+
    (* "\"" (<- (some (if-not (+ "," "\"") :S))) "\"")
    (<- (some (if-not "," :S)))
  ))
  :parameter (* :keyword "=" :value)
  :keyword-pair (* :keyword (+ (* "=" :value) (constant "")))
  :keyword-pairs (*
    :keyword-pair
    (any (* "," :s* :keyword-pair))
    )
  :other (* :keyword (? (* :s+ (+
    (* (constant :pairs) :keyword-pairs)
    (* (constant :token) (capture :S+))
    ))))
  :main (choice :basic :bearer :other)
}))

(defn- build-data-table [parts]
  (def data @{})
  (while (not (empty? parts))
    (def value (array/pop parts))
    (def key (keyword (array/pop parts)))
    (put data key value)
    )
  data)

(defn- parse-authorization-header [header]
  (if-let [parts (peg/match authorization-parser header)]
    (do
      (def first (get parts 0))
      (case first
        "Bearer" {:type :bearer :data (get parts 2)}
        "Basic" (do
          (def decoded (base64/decode (get parts 2)))
          (def credential (string/split ":" decoded 0 2))
          {:type :digest :data {
            :username (get credential 0)
            :password (get credential 1)
          }})
        (case (get parts 1)
          :token {:type first :data (get parts 2)}
          :pairs {:type first :data (build-data-table (array/slice parts 2))}
          )))))

(defn authorization [handler]
  (fn [request]
    (let [
      {:headers headers} request
      authorization (or (get headers :authorization) (get headers "Authorization") (get headers "authorization"))
      data (if authorization (parse-authorization-header authorization))
      ]
      (if data
        (handler (merge request {:authorization data}))
        (handler request)))))

(defn file-uploads
  `This middleware attempts parse multipart form bodies
   and saves temp files for each part with a filename
   content disposition

   The tempfiles are deleted after your handler is called

   It then returns the body as an array of dictionaries like this:

   @[{:filename "name of file" :content-type "content-type" :size 123 :tempfile "<file descriptor>"}]`
  [handler]
  (fn [request]
    (if (and (get request :body)
             (or (post? request) (put? request))
             (http/multipart? request))
      (let [multipart-body (http/parse-multipart-body request)
            body @{}
            form-parts (filter (fn [part] (nil? (get part :temp-file))) multipart-body)
            _ (each part form-parts (put body (keyword (get part :name)) (get part :content)))
            multipart-body (filter (fn [part] (truthy? (get part :temp-file))) multipart-body)

            request (put request :multipart-body multipart-body)
            request (put request :body body)

            response (handler request)
            files (as-> body ?
                        (map |(get $ :temp-file) ?)
                        (filter truthy? ?))]
        (loop [f :in files] # delete temp files
          (file/close f))
        response)
      (handler request))))

(defn with-authentication [handler]
  (fn [request]
    (def token (get-in request [:authorization :data]))
    (if (constant= (secrets/admin-token) token)
      (handler request)
      @{
        :status 401
        :body "Unauthorized"
      })))

(defn check-authentication [handler]
  (fn [request]
    (def token (get-in request [:authorization :data]))
    (def user (get-in request [:session :user]))
    (if (or (= :admin user) (constant= (secrets/admin-token) token))
      (handler (merge request {:authenticated (or user :admin)}))
      (handler request)
    )))

(defn conditional-authentication [unauthenticated-handler authenticated-handler]
  (fn [request]
    (def token (get-in request [:authorization :data]))
    (def user (get-in request [:session :user]))
    (if (or (= :admin user) (constant= (secrets/admin-token) token))
      (authenticated-handler (merge request {:authenticated (or user :admin)}))
      (unauthenticated-handler request)
    )))

(defn www-url-form [handler]
  (fn [request]
    (let [{:body body} request]
      (if (and body (form? request))
        (handler (merge request {
          :body (http/parse-body body)
          :original-body body
          }))
        (handler request)))))

(defn json [handler]
  (fn [request]
    (let [{:body body} request]
      (if (and body
               (json? request))
        (handler (merge request {
          :body (json/decode body true)
          :original-body body
          }))
        (handler request)))))

(def- default-json @{
  :status 200
  :headers @{
    "Content-Type" "application/json"
  }
  :body "{}"
  })

(def- mime-types {"txt" "text/plain"
                  "css" "text/css"
                  "js" "application/javascript"
                  "json" "application/json"
                  "xml" "text/xml"
                  "html" "text/html"
                  "svg" "image/svg+xml"
                  "pg" "image/jpeg"
                  "jpeg" "image/jpeg"
                  "gif" "image/gif"
                  "png" "image/png"
                  "wasm" "application/wasm"
                  "gz" "application/gzip"
                  "jxl" "image/jxl"
                  "webp" "image/webp"
                  "avif" "image/avif"
                  "webm" "video/webm"
                  "mp4" "video/mp4"
                  })

(defn- content-type [s]
  (as-> (string/split "." s) _
        (last _)
        (get mime-types _ "text/plain")))

(def- etags @{})

(defn get-etag [filename]
  (var content nil)
  (def etag (if-let [etag (get etags filename)] etag (do
    (set content (slurp filename))
    (def etag (string "\"" (md/digest :md5 content :hex) "\""))
    (put etags filename etag)
    etag)))
  {:content content :etag etag})

(defn- get-if-none-match [request]
  (or (get-in request [:headers "If-None-Match"]) (get-in request [:headers "if-none-match"])))

(defn find-no-match [etag request]
  (def if-none-match (get-if-none-match request))
  (var no-match true)
  (if if-none-match
    (each matching (string/split "," if-none-match)
      (if (= matching etag) (set no-match false))))
  no-match)

# Add my own static files middleware because joy/halo2 does not
# have some newer file types
(defn static-files
  [handler &opt root]
  (default root "./public")
  (fn [request]
    (let [{:uri uri} request
          filename (path/join root uri)]
      (if (and (or (get? request) (head? request))
               (path/ext filename)
               (file-exists? filename))
        (do
          (var content nil)
          (def etag-content (get-etag filename))
          (set content (get etag-content :content))
          (def etag (get etag-content :etag))
          (def no-match (find-no-match etag request))
          (when (and no-match (nil? content)) (set content (slurp filename)))
          (if no-match @{:body content :headers
            @{
              "Content-Type" (content-type filename)
              "ETag" etag
              "Cache-Control" "public, max-age=315360000"
            } :level "verbose"}
            @{:status 304 :headers @{
              "Content-Type" (content-type filename)
              "ETag" etag
              "Cache-Control" "public, max-age=315360000"
            } :level "verbose"}
            ))
        (handler request)))))

(defn simple-passthrough
  [handler stage]
  (fn [request]
    (printf "%s Request passthrough %p" stage request)
    (let [response (handler request)]
      (printf "%s Response passthrough %p" stage response)
      response)))

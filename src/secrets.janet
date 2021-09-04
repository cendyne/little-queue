(use joy)
(use janetls)

(defn- env-secret [secret &opt encoding]
  (let [value (dyn secret)] (if value value (let
    [value (env secret)
    ] (if value
    (do
      (def value (if encoding (encoding/decode value encoding) value))
      (setdyn secret value)
      value)
    (errorf
      "The secret %s was not set as an environment variable or .env value"
      (string/replace-all "-" "_" (string/ascii-upper (string secret)))
      ))
  ))))

(defn admin-token [] (env-secret :admin-token))

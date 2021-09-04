(declare-project
  :name "little-queue"
  :description "A simple queue for arbitrary content"
  :author "Cendyne"
  :url "https://github.com/cendyne/little-queue"
  :repo "git+https://github.com/cendyne/little-queue"
  :dependencies [
    "https://github.com/joy-framework/joy"
    "https://github.com/janet-lang/sqlite3"
    "https://github.com/levischuck/janetls"
    {:repo "https://github.com/cendyne/simple-janet-crypto" :tag "main"}
    ]
  )

# (phony "server" []
#   (if (= "development" (os/getenv "JOY_ENV"))
#       # TODO check if entr exists
#     (os/shell "find . -name '*.janet' | entr janet main.janet")
#     (os/shell "janet src/main.janet")))
#
# (declare-executable
#   :name "art"
#   :entry "src/main.janet"
#   )


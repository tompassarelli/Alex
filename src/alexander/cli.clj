(ns alexander.cli
  (:require [clojure.string :as str]
            [dgm.core :as dgm]))

(def data-dir (str (System/getProperty "user.home") "/.alexander/datahike"))

(def boot-concepts
  ["name" "person" "place" "project" "theme"
   "task" "title" "status" "description"])

(defn get-conn []
  (dgm/init-db data-dir boot-concepts))

;; -- task sugar --

(defn cmd-add [title]
  (let [conn (get-conn)
        task-name (dgm/next-seq conn "t")]
    (dgm/ensure-entity conn task-name)
    (dgm/create-claim conn task-name :is "task" :observation)
    (dgm/attach-descriptor conn task-name "title" title)
    (dgm/attach-descriptor conn task-name "status" "todo")
    (println (str "added #" (subs task-name 1) ": " title))))

(defn query-tasks [conn]
  (dgm/q '[:find ?task-name ?title-val ?status-val
              :where
              [?kc :subject ?task]
              [?kc :predicate :is]
              [?kc :object ?task-concept]
              [?task-concept :name "task"]
              [?task :name ?task-name]
              [?tc :subject ?task]
              [?tc :predicate :is]
              [?tc :object ?title-desc]
              [?tkc :subject ?title-desc]
              [?tkc :predicate :is]
              [?tkc :object ?title-concept]
              [?title-concept :name "title"]
              [?title-desc :value ?title-val]
              [?sc :subject ?task]
              [?sc :predicate :is]
              [?sc :object ?status-desc]
              [?skc :subject ?status-desc]
              [?skc :predicate :is]
              [?skc :object ?status-concept]
              [?status-concept :name "status"]
              [?status-desc :value ?status-val]]
            (dgm/db conn)))

(defn cmd-list []
  (let [conn (get-conn)
        results (query-tasks conn)]
    (if (empty? results)
      (println "no tasks.")
      (let [sorted (sort-by first (mapv vec results))]
        (doseq [row sorted]
          (let [task-name (first row)
                title (second row)
                stat (nth row 2)
                num (subs task-name 1)]
            (println (str (if (= stat "done") "  [x] #" "  [ ] #") num " " title))))))))

(defn cmd-done [id]
  (let [conn (get-conn)
        task-name (str "t" id)
        desc-name (dgm/find-descriptor conn task-name "status")]
    (if (nil? desc-name)
      (println (str "no task #" id))
      (do
        (dgm/transact conn [{:name desc-name :value "done"}])
        (println (str "done #" id))))))

(defn cmd-rm [id]
  (let [conn (get-conn)
        task-name (str "t" id)]
    (if (not (dgm/entity-exists? conn task-name))
      (println (str "no task #" id))
      (do
        (dgm/retract-entity conn task-name)
        (println (str "removed #" id))))))

;; -- graph commands --

(defn cmd-mint [entity-name kind-arg]
  (let [conn (get-conn)
        n (str/lower-case entity-name)]
    (dgm/ensure-entity conn n)
    (when kind-arg
      (dgm/create-claim conn n :is (str/lower-case kind-arg) :observation))
    (if kind-arg
      (println (str "minted: " n " (" kind-arg ")"))
      (println (str "minted: " n)))))

(defn cmd-attr [entity-name kind-name val]
  (let [conn (get-conn)
        n (str/lower-case entity-name)
        k (str/lower-case kind-name)
        desc-name (dgm/attach-descriptor conn n k val)]
    (println (str "  " n " is " desc-name " (" k ": \"" val "\")"))))

(defn cmd-claim-rel [subj pred obj layer]
  (let [conn (get-conn)
        s (str/lower-case subj)
        o (str/lower-case obj)]
    (dgm/create-claim conn s (keyword pred) o (keyword layer))
    (println (str "  " s " " pred " " o " [" layer "]"))))

(defn cmd-about [entity-name]
  (let [conn (get-conn)
        n (str/lower-case entity-name)]
    (if (not (dgm/entity-exists? conn n))
      (println (str "unknown: " n))
      (do
        (println n)
        (doseq [row (sort-by first (mapv vec (dgm/query-classifications conn n)))]
          (println (str "  is: " (first row))))
        (doseq [row (sort-by first (mapv vec (dgm/query-descriptors conn n)))]
          (println (str "  " (first row) ": \"" (second row) "\"")))
        (doseq [row (sort-by (fn [r] (name (first r))) (mapv vec (dgm/query-relations conn n)))]
          (println (str "  " (name (first row)) ": " (second row))))))))

(defn cmd-entities []
  (let [conn (get-conn)
        results (dgm/query-all-entities conn)]
    (if (empty? results)
      (println "no entities.")
      (doseq [n (sort (mapv first results))]
        (println (str "  " n))))))

;; -- source commands --

(defn cmd-ingest []
  (let [conn (get-conn)
        raw (slurp *in*)]
    (if (empty? raw)
      (println "nothing to ingest (empty input).")
      (let [source-name (dgm/ingest-source conn raw)]
        (println (str "ingested " source-name " (" (count raw) " chars)"))))))

(defn cmd-sources []
  (let [conn (get-conn)
        results (dgm/query-sources conn)]
    (if (empty? results)
      (println "no sources.")
      (doseq [row (sort-by first (mapv vec results))]
        (println (str "  " (first row) " " (second row)))))))

(defn cmd-source [source-name]
  (let [conn (get-conn)
        raw (dgm/query-source-text conn source-name)]
    (if (nil? raw)
      (println (str "unknown: " source-name))
      (println raw))))

;; -- admin --

(defn cmd-nuke []
  (dgm/nuke-db data-dir)
  (println "database cleared."))

(defn cmd-help []
  (println "alexander — knowledge graph (datahike)")
  (println "")
  (println "  graph:")
  (println "    alex mint <name> [kind]           create entity")
  (println "    alex attr <e> <kind> <value>      attach descriptor")
  (println "    alex claim <s> <p> <o> [layer]    relate entities")
  (println "    alex about <entity>               show entity")
  (println "    alex entities                     list all")
  (println "")
  (println "  tasks:")
  (println "    alex add <title>                  add task")
  (println "    alex list                         list tasks")
  (println "    alex done <id>                    mark done")
  (println "    alex rm <id>                      remove task")
  (println "")
  (println "  sources:")
  (println "    alex ingest                       read stdin")
  (println "    alex sources                      list sources")
  (println "    alex source <name>                show source")
  (println "")
  (println "  admin:")
  (println "    alex nuke                         wipe database"))

;; -- dispatch --

(defn -main [& args]
  (let [args (vec args)
        cmd (first args)]
    (case cmd
      "mint"     (if (nil? (get args 1))
                   (println "usage: alex mint <name> [kind]")
                   (cmd-mint (get args 1) (get args 2)))
      "attr"     (if (or (nil? (get args 1)) (nil? (get args 2)) (nil? (get args 3)))
                   (println "usage: alex attr <entity> <kind> <value>")
                   (cmd-attr (get args 1) (get args 2) (get args 3)))
      "claim"    (if (or (nil? (get args 1)) (nil? (get args 2)) (nil? (get args 3)))
                   (println "usage: alex claim <subject> <predicate> <object> [layer]")
                   (cmd-claim-rel (get args 1) (get args 2) (get args 3)
                                  (or (get args 4) "observation")))
      "about"    (if (nil? (get args 1))
                   (println "usage: alex about <entity>")
                   (cmd-about (get args 1)))
      "entities" (cmd-entities)
      "add"      (if (empty? (rest args))
                   (println "usage: alex add <title>")
                   (cmd-add (str/join " " (rest args))))
      "list"     (cmd-list)
      "done"     (if (nil? (get args 1))
                   (println "usage: alex done <id>")
                   (cmd-done (get args 1)))
      "rm"       (if (nil? (get args 1))
                   (println "usage: alex rm <id>")
                   (cmd-rm (get args 1)))
      "ingest"   (cmd-ingest)
      "sources"  (cmd-sources)
      "source"   (if (nil? (get args 1))
                   (println "usage: alex source <name>")
                   (cmd-source (get args 1)))
      "nuke"     (cmd-nuke)
      (cmd-help))))

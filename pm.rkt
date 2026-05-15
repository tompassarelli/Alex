#lang beagle

(ns pm.cli)

(require clojure.string :as str)

;; -- pod bootstrap --
(unsafe "(require '[babashka.pods :as pods])")
(unsafe "(pods/load-pod 'replikativ/datahike \"0.6.1613\")")
(unsafe "(require '[datahike.pod :as d])")

;; -- externs --
(declare-extern d/create-database [Any -> Any])
(declare-extern d/delete-database [Any -> Any])
(declare-extern d/database-exists? [Any -> Boolean])
(declare-extern d/connect [Any -> Any])
(declare-extern d/transact [Any Any -> Any])
(declare-extern d/db [Any -> Any])
(declare-extern parse-long [String -> Long])
(declare-extern slurp [Any -> String])
(declare-extern *in* Any)

;; -- config --
(defn db-cfg []
  (hash-map :store (hash-map :backend :file
                              :path (str (System/getProperty "user.home") "/.pm/datahike"))))

;; -- schema (flat — everything is an entity) --
(def schema
  [(hash-map :db/ident :name
             :db/valueType :db.type/string
             :db/cardinality :db.cardinality/one
             :db/unique :db.unique/identity)
   (hash-map :db/ident :value
             :db/valueType :db.type/string
             :db/cardinality :db.cardinality/one)
   (hash-map :db/ident :text
             :db/valueType :db.type/string
             :db/cardinality :db.cardinality/one)
   (hash-map :db/ident :subject
             :db/valueType :db.type/ref
             :db/cardinality :db.cardinality/one)
   (hash-map :db/ident :predicate
             :db/valueType :db.type/keyword
             :db/cardinality :db.cardinality/one)
   (hash-map :db/ident :object
             :db/valueType :db.type/ref
             :db/cardinality :db.cardinality/one)
   (hash-map :db/ident :layer
             :db/valueType :db.type/keyword
             :db/cardinality :db.cardinality/one)
   (hash-map :db/ident :created-at
             :db/valueType :db.type/string
             :db/cardinality :db.cardinality/one)])

;; -- bootstrap concepts --
(def concepts
  [(hash-map :name "name")
   (hash-map :name "person")
   (hash-map :name "place")
   (hash-map :name "project")
   (hash-map :name "theme")
   (hash-map :name "task")
   (hash-map :name "title")
   (hash-map :name "status")
   (hash-map :name "description")])

(defn ensure-db []
  (when (not (d/database-exists? (db-cfg)))
    (d/create-database (db-cfg)))
  (let [conn (d/connect (db-cfg))]
    (d/transact conn schema)
    (d/transact conn concepts)))

(defn get-conn []
  (ensure-db)
  (d/connect (db-cfg)))

(defn now [] : String
  (unsafe "(str (java.time.Instant/now))"))

;; -- seq counter --
(defn next-seq [(conn : Any) (prefix : String)] : String
  (unsafe "(let [seq-name (str \"_seq.\" prefix)
                 r (d/q [:find '?v :where ['?e :name seq-name] ['?e :value '?v]] (d/db conn))
                 current (if (seq r) (parse-long (ffirst r)) 0)
                 next-val (inc current)]
             (d/transact conn [{:name seq-name :value (str next-val)}])
             (str prefix next-val))"))

;; -- entity helpers --
(defn entity-exists? [(conn : Any) (entity-name : String)] : Boolean
  (unsafe "(boolean (seq (d/q [:find '?e :where ['?e :name entity-name]] (d/db conn))))"))

(defn ensure-entity [(conn : Any) (entity-name : String)]
  (when (not (entity-exists? conn entity-name))
    (d/transact conn [(hash-map :name entity-name)])))

;; -- queries --
(defn find-descriptor [(conn : Any) (entity-name : String) (concept-name : String)]
  (unsafe "(let [r (d/q [:find '?desc-name
                         :where ['?e :name entity-name]
                                ['?c :subject '?e]
                                ['?c :predicate :is]
                                ['?c :object '?desc]
                                ['?desc :value '?_v]
                                ['?ic :subject '?desc]
                                ['?ic :predicate :is]
                                ['?ic :object '?concept]
                                ['?concept :name concept-name]
                                ['?desc :name '?desc-name]]
                        (d/db conn))]
             (if (seq r) (ffirst r) nil))"))

(defn query-descriptors [(conn : Any) (entity-name : String)]
  (unsafe "(d/q [:find '?concept-name '?val
                 :where ['?e :name entity-name]
                        ['?c :subject '?e]
                        ['?c :predicate :is]
                        ['?c :object '?desc]
                        ['?desc :value '?val]
                        ['?ic :subject '?desc]
                        ['?ic :predicate :is]
                        ['?ic :object '?concept]
                        ['?concept :name '?concept-name]]
                (d/db conn))"))

(defn query-classifications [(conn : Any) (entity-name : String)]
  (unsafe "(let [all-is (d/q [:find '?obj-name
                              :where ['?e :name entity-name]
                                     ['?c :subject '?e]
                                     ['?c :predicate :is]
                                     ['?c :object '?obj]
                                     ['?obj :name '?obj-name]]
                             (d/db conn))
                 descs (d/q [:find '?obj-name
                             :where ['?e :name entity-name]
                                    ['?c :subject '?e]
                                    ['?c :predicate :is]
                                    ['?c :object '?obj]
                                    ['?obj :value '?_v]
                                    ['?obj :name '?obj-name]]
                            (d/db conn))
                 desc-names (set (map first descs))]
             (remove (fn [row] (desc-names (first row))) all-is))"))

(defn query-relations [(conn : Any) (entity-name : String)]
  (unsafe "(let [all (d/q [:find '?pred '?obj-name
                           :where ['?e :name entity-name]
                                  ['?c :subject '?e]
                                  ['?c :predicate '?pred]
                                  ['?c :object '?obj]
                                  ['?obj :name '?obj-name]]
                          (d/db conn))]
             (remove (fn [row] (= (first row) :is)) all))"))

(defn query-all-entities [(conn : Any)]
  (unsafe "(remove (fn [row] (clojure.string/starts-with? (first row) \"_seq.\"))
                   (d/q '[:find ?name :where [?e :name ?name]] (d/db conn)))"))

(defn query-sources [(conn : Any)]
  (unsafe "(d/q '[:find ?name ?created-at
                  :where [?e :text _]
                         [?e :name ?name]
                         [?e :created-at ?created-at]]
                (d/db conn))"))

(defn query-source-text [(conn : Any) (source-name : String)]
  (unsafe "(let [r (d/q [:find '?t :where ['?e :name source-name] ['?e :text '?t]] (d/db conn))]
             (if (seq r) (ffirst r) nil))"))

;; -- core operations --
(defn create-claim [(conn : Any) (subj-name : String) (pred : Any) (obj-name : String) (layer : Any)]
  (ensure-entity conn subj-name)
  (ensure-entity conn obj-name)
  (unsafe "(d/transact conn [{:subject [:name subj-name]
                              :predicate pred
                              :object [:name obj-name]
                              :layer layer}])"))

(defn attach-attr [(conn : Any) (entity-name : String) (kind-name : String) (val : String)]
  (ensure-entity conn entity-name)
  (ensure-entity conn kind-name)
  (let [existing (find-descriptor conn entity-name kind-name)]
    (if (nil? existing)
      (let [desc-name (next-seq conn "d")]
        (d/transact conn [(hash-map :name desc-name :value val)])
        (unsafe "(d/transact conn [{:subject [:name entity-name]
                                    :predicate :is
                                    :object [:name desc-name]
                                    :layer :observation}
                                   {:subject [:name desc-name]
                                    :predicate :is
                                    :object [:name kind-name]
                                    :layer :observation}])")
        desc-name)
      (do
        (d/transact conn [(hash-map :name existing :value val)])
        existing))))

;; -- task sugar --
(defn cmd-add [(title : String)]
  (let [conn (get-conn)
        task-name (next-seq conn "t")]
    (ensure-entity conn task-name)
    (create-claim conn task-name :is "task" :observation)
    (attach-attr conn task-name "title" title)
    (attach-attr conn task-name "status" "todo")
    (let [num (subs task-name 1)]
      (println (str "added #" num ": " title)))))

(defn query-tasks [(conn : Any)]
  (unsafe "(d/q '[:find ?task-name ?title-val ?status-val
                  :where
                  [?kc :subject ?task]
                  [?kc :predicate :is]
                  [?kc :object ?task-concept]
                  [?task-concept :name \"task\"]
                  [?task :name ?task-name]
                  [?tc :subject ?task]
                  [?tc :predicate :is]
                  [?tc :object ?title-desc]
                  [?tkc :subject ?title-desc]
                  [?tkc :predicate :is]
                  [?tkc :object ?title-concept]
                  [?title-concept :name \"title\"]
                  [?title-desc :value ?title-val]
                  [?sc :subject ?task]
                  [?sc :predicate :is]
                  [?sc :object ?status-desc]
                  [?skc :subject ?status-desc]
                  [?skc :predicate :is]
                  [?skc :object ?status-concept]
                  [?status-concept :name \"status\"]
                  [?status-desc :value ?status-val]]
                (d/db conn))"))

(defn cmd-list []
  (let [conn (get-conn)
        results (query-tasks conn)]
    (if (empty? results)
      (println "no tasks.")
      (let [sorted (sort-by first (mapv vec results))]
        (mapv (fn [row]
                (let [task-name (first row)
                      title (second row)
                      stat (nth row 2)
                      num (subs task-name 1)]
                  (println (str (if (= stat "done") "  [x] #" "  [ ] #")
                                num " " title))))
              sorted)))))

(defn cmd-done [(id : String)]
  (let [conn (get-conn)
        task-name (str "t" id)
        desc-name (find-descriptor conn task-name "status")]
    (if (nil? desc-name)
      (println (str "no task #" id))
      (do
        (d/transact conn [(hash-map :name desc-name :value "done")])
        (println (str "done #" id))))))

(defn cmd-rm [(id : String)]
  (let [conn (get-conn)
        task-name (str "t" id)]
    (if (not (entity-exists? conn task-name))
      (println (str "no task #" id))
      (do
        (unsafe "(let [task-eid (ffirst (d/q [:find '?e :where ['?e :name task-name]] (d/db conn)))
                       claim-eids (map first (d/q [:find '?c :where ['?c :subject task-eid]] (d/db conn)))
                       desc-eids (map first (d/q [:find '?desc :where ['?c :subject task-eid]
                                                                      ['?c :predicate :is]
                                                                      ['?c :object '?desc]
                                                                      ['?desc :value '?_v]] (d/db conn)))
                       desc-claim-eids (mapcat (fn [d] (map first (d/q [:find '?kc :where ['?kc :subject d]] (d/db conn)))) desc-eids)
                       all-eids (distinct (concat [task-eid] claim-eids desc-eids desc-claim-eids))]
                   (doseq [eid all-eids]
                     (d/transact conn [[:db/retractEntity eid]])))")
        (println (str "removed #" id))))))

;; -- graph commands --
(defn cmd-mint [(entity-name : String) (kind-arg : (U String Nil))]
  (let [conn (get-conn)
        n (str/lower-case entity-name)]
    (ensure-entity conn n)
    (when (not (nil? kind-arg))
      (create-claim conn n :is (str/lower-case kind-arg) :observation))
    (if (nil? kind-arg)
      (println (str "minted: " n))
      (println (str "minted: " n " (" kind-arg ")")))))

(defn cmd-attr [(entity-name : String) (kind-name : String) (val : String)]
  (let [conn (get-conn)
        n (str/lower-case entity-name)
        k (str/lower-case kind-name)
        desc-name (attach-attr conn n k val)]
    (println (str "  " n " is " desc-name " (" k ": \"" val "\")"))))

(defn cmd-claim-rel [(subj : String) (pred : String) (obj : String) (layer : String)]
  (let [conn (get-conn)
        s (str/lower-case subj)
        o (str/lower-case obj)
        pred-kw (keyword pred)
        layer-kw (keyword layer)]
    (create-claim conn s pred-kw o layer-kw)
    (println (str "  " s " " pred " " o " [" layer "]"))))

(defn cmd-about [(entity-name : String)]
  (let [conn (get-conn)
        n (str/lower-case entity-name)]
    (if (not (entity-exists? conn n))
      (println (str "unknown: " n))
      (do
        (println n)
        (let [kinds (query-classifications conn n)]
          (mapv (fn [row]
                  (println (str "  is: " (first row))))
                (sort-by first (mapv vec kinds))))
        (let [descs (query-descriptors conn n)]
          (mapv (fn [row]
                  (let [k (first row)
                        v (second row)]
                    (println (str "  " k ": \"" v "\""))))
                (sort-by first (mapv vec descs))))
        (let [rels (query-relations conn n)]
          (mapv (fn [row]
                  (let [p (first row)
                        o (second row)]
                    (println (str "  " (name p) ": " o))))
                (sort-by (fn [r] (name (first r))) (mapv vec rels))))))))

(defn cmd-entities []
  (let [conn (get-conn)
        results (query-all-entities conn)]
    (if (empty? results)
      (println "no entities.")
      (let [sorted (sort (mapv first results))]
        (mapv (fn [n] (println (str "  " n))) sorted)))))

;; -- source commands --
(defn cmd-ingest []
  (let [conn (get-conn)
        raw (slurp *in*)
        source-name (next-seq conn "s")
        ts (now)]
    (if (empty? raw)
      (println "nothing to ingest (empty input).")
      (do
        (d/transact conn [(hash-map :name source-name
                                    :text raw
                                    :created-at ts)])
        (println (str "ingested " source-name " (" (count raw) " chars)"))))))

(defn cmd-sources []
  (let [conn (get-conn)
        results (query-sources conn)]
    (if (empty? results)
      (println "no sources.")
      (let [sorted (sort-by first (mapv vec results))]
        (mapv (fn [row]
                (let [n (first row)
                      ts (second row)]
                  (println (str "  " n " " ts))))
              sorted)))))

(defn cmd-source [(source-name : String)]
  (let [conn (get-conn)
        raw (query-source-text conn source-name)]
    (if (nil? raw)
      (println (str "unknown: " source-name))
      (println raw))))

;; -- admin --
(defn cmd-nuke []
  (when (d/database-exists? (db-cfg))
    (d/delete-database (db-cfg)))
  (println "database cleared."))

(defn cmd-help []
  (println "pm — knowledge graph (datahike)")
  (println "")
  (println "  graph:")
  (println "    pm mint <name> [kind]           create entity")
  (println "    pm attr <e> <kind> <value>      attach descriptor")
  (println "    pm claim <s> <p> <o> [layer]    relate entities")
  (println "    pm about <entity>               show entity")
  (println "    pm entities                     list all")
  (println "")
  (println "  tasks:")
  (println "    pm add <title>                  add task")
  (println "    pm list                         list tasks")
  (println "    pm done <id>                    mark done")
  (println "    pm rm <id>                      remove task")
  (println "")
  (println "  sources:")
  (println "    pm ingest                       read stdin")
  (println "    pm sources                      list sources")
  (println "    pm source <name>                show source")
  (println "")
  (println "  admin:")
  (println "    pm nuke                         wipe database"))

;; -- dispatch --
(defn main []
  (let [args (vec *command-line-args*)
        cmd (first args)]
    (cond
      (= cmd "mint") (if (nil? (get args 1))
                       (println "usage: pm mint <name> [kind]")
                       (cmd-mint (get args 1) (get args 2)))
      (= cmd "attr") (if (or (nil? (get args 1)) (nil? (get args 2)) (nil? (get args 3)))
                       (println "usage: pm attr <entity> <kind> <value>")
                       (cmd-attr (get args 1) (get args 2) (get args 3)))
      (= cmd "claim") (if (or (nil? (get args 1)) (nil? (get args 2)) (nil? (get args 3)))
                         (println "usage: pm claim <subject> <predicate> <object> [layer]")
                         (cmd-claim-rel (get args 1) (get args 2) (get args 3)
                                        (if (nil? (get args 4)) "observation" (get args 4))))
      (= cmd "about") (if (nil? (get args 1))
                         (println "usage: pm about <entity>")
                         (cmd-about (get args 1)))
      (= cmd "entities") (cmd-entities)
      (= cmd "add") (if (empty? (rest args))
                      (println "usage: pm add <title>")
                      (cmd-add (str/join " " (rest args))))
      (= cmd "list") (cmd-list)
      (= cmd "done") (if (nil? (get args 1))
                       (println "usage: pm done <id>")
                       (cmd-done (get args 1)))
      (= cmd "rm") (if (nil? (get args 1))
                     (println "usage: pm rm <id>")
                     (cmd-rm (get args 1)))
      (= cmd "ingest") (cmd-ingest)
      (= cmd "sources") (cmd-sources)
      (= cmd "source") (if (nil? (get args 1))
                          (println "usage: pm source <name>")
                          (cmd-source (get args 1)))
      (= cmd "nuke") (cmd-nuke)
      :else (cmd-help))))

(main)

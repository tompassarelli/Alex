# alexander — session anchor

A personal knowledge graph CLI backed by Datahike. CLI command is `alex`.
Implements [Descriptor Graph Normal Form](https://github.com/tompassarelli/descriptor-graph-normal-form)
via the [dgm-datahike](https://github.com/tompassarelli/dgm-datahike) library.

## Ontological model

One structural pattern: **claims** (subject → predicate → object). Both
subject and object are entities. Every entity has a `:name`.

`:is` is the universal predicate. The **object** determines semantics:

- **Classification**: object has no `:value` → "tom IS person"
- **Descriptor**: object has `:value` → "tom IS d5" where d5 IS name,
  d5 has `:value "Tom Passarelli"`

`:value` is the only escape to literals. Everything else is
entity-to-entity.

Every claim carries a `:layer` (observation, interpretation, orientation).

Custom predicates beyond `:is` are free-form keywords for domain relations
(works-on, reports-to, etc).

## Architecture

Plain Clojure (`src/alexander/cli.clj`) on babashka. Core DGNF operations
come from `dgm-datahike` (sibling dir or `$DGM_PATH`). Data at
`~/.alexander/datahike/`.

Auto-generated entity names: `d1, d2, ...` (descriptors), `t1, t2, ...`
(tasks), `s1, s2, ...` (sources). Seq counters stored as `_seq.d`,
`_seq.t`, `_seq.s` entities.

## CLI

```
alex mint <name> [kind]           create entity (optionally classify)
alex attr <entity> <kind> <value> attach descriptor
alex claim <s> <p> <o> [layer]   create relationship claim
alex about <entity>               show entity
alex entities                     list all entities

alex add <title>                  add task
alex list                         list tasks
alex done <id>                    mark done
alex rm <id>                      remove task

echo "text" | alex ingest         store raw text
alex sources                      list sources
alex source <name>                show source

alex nuke                         wipe database
```

## Key implementation details

- `attach-descriptor` is idempotent: updates existing descriptor value or
  creates new descriptor + claims
- `retract-entity` only retracts descriptor entities (those with `:value`),
  not shared concept entities — the `:value` guard prevents deleting
  bootstrap concepts
- `find-descriptor` joins through two `:is` hops: entity → descriptor
  (has `:value`) → concept
- Task sugar is built on top of the graph: tasks are entities classified
  as "task" with title and status descriptors
- Domain-specific queries (e.g. `query-tasks`) use `dgm/q` and `dgm/db`
  passthroughs for raw Datalog

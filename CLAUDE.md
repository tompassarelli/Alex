# alexander — session anchor

A personal knowledge graph CLI backed by Datahike. CLI command is `alex`.

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

## Schema

Eight flat attributes — no namespace prefixes:

- `:name` (string, unique identity) — entity identifier, lookup ref target
- `:value` (string) — literal value on descriptor entities
- `:text` (string) — raw text on source entities
- `:subject` (ref) — claim subject
- `:predicate` (keyword) — claim predicate
- `:object` (ref) — claim object
- `:layer` (keyword) — epistemic layer
- `:created-at` (string) — timestamp on sources

Bootstrap concepts: name, person, place, project, theme, task, title,
status, description.

## Architecture

Authored in beagle (`alex.rkt` → `alex.clj`). Runs on babashka with the
datahike pod. Data at `~/.alexander/datahike/`.

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

## Building

```
beagle-build alex.rkt alex.clj
```

Only needed when editing `alex.rkt`. The compiled `alex.clj` is committed.

## Key implementation details

- `attach-attr` is idempotent: updates existing descriptor value or creates
  new descriptor + claims
- `cmd-rm` only retracts descriptor entities (those with `:value`), not
  shared concept entities — the `:value` guard in the retraction query
  prevents deleting bootstrap concepts
- `find-descriptor` joins through two `:is` hops: entity → descriptor
  (has `:value`) → concept
- Task sugar is built on top of the graph: tasks are entities classified
  as "task" with title and status descriptors

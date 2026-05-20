# Alex — knowledge graph CLI

A personal knowledge graph backed by Datahike. Models everything as
entities and claims (subject-predicate-object triples). Task management
is sugar on top of the graph.

Implements [Descriptor Graph Normal Form](https://github.com/tompassarelli/descriptor-graph-normal-form)
via [dgm-datahike](https://github.com/tompassarelli/dgm-datahike).
Runs on [babashka](https://babashka.org/).

## The ontological model

Five rules:

1. **Everything meaningful is an entity.** People, projects, concepts
   like "name" or "status", even descriptor leaves — all entities with a
   `:name`.

2. **A claim is a relationship assertion: subject -> predicate -> object.**
   Claims are themselves entities (datoms with `:subject`, `:predicate`,
   `:object`, `:layer`). Both subject and object are entity refs.

3. **`:is` is the universal predicate** for both classification and
   descriptor attachment. The object determines which one it is — not the
   predicate.

4. **Classification vs descriptor — the object decides:**
   - Object has **no `:value`** -> classification. "tom IS person" means
     tom is classified as a person.
   - Object **has `:value`** -> descriptor. "tom IS d5" where d5 has
     `:value "Tom Passarelli"` and d5 IS name — means tom has a name
     whose value is "Tom Passarelli".

5. **`:value` is the only escape to literals.** Everything else is
   entity-to-entity. Literal strings only appear as the `:value` attribute
   on descriptor entities.

### Example: what "tom has a name" looks like

```
entity: tom          {:name "tom"}
entity: d5           {:name "d5", :value "Tom Passarelli"}
entity: name         {:name "name"}            (bootstrap concept)

claim:  tom IS d5    {:subject tom, :predicate :is, :object d5, :layer :observation}
claim:  d5 IS name   {:subject d5, :predicate :is, :object name, :layer :observation}
```

Reading it: tom IS d5, and d5 IS name with value "Tom Passarelli".
The descriptor (d5) is a reified leaf that bridges the entity to its
literal value, classified by the concept it represents.

### Example: what "tom is a candidate" looks like

```
entity: tom          {:name "tom"}
entity: candidate    {:name "candidate"}

claim:  tom IS candidate  {:subject tom, :predicate :is, :object candidate, :layer :observation}
```

No `:value` on candidate — it's a classification, not a descriptor.

### Custom predicates

Beyond `:is`, any keyword works as a predicate for domain-specific
relations:

```
claim:  tom works-on beagle  {:subject tom, :predicate :works-on, :object beagle, :layer :observation}
```

### Layers

Every claim carries a `:layer` — metadata about the claim's epistemic
status:

- `:observation` — directly stated or observed
- `:interpretation` — inferred or synthesized
- `:orientation` — strategic, action-guiding

## Schema

Flat — no namespace prefixes. Eight attributes total:

| attribute    | type      | purpose |
|---|---|---|
| `:name`      | string, unique identity | entity identifier (lookup ref target) |
| `:value`     | string    | literal value on descriptor entities |
| `:text`      | string    | raw text on source entities |
| `:subject`   | ref       | claim subject |
| `:predicate` | keyword   | claim predicate |
| `:object`    | ref       | claim object |
| `:layer`     | keyword   | claim epistemic layer |
| `:created-at`| string    | timestamp on source entities |

Bootstrap concepts (created on first run): name, person, place, project,
theme, task, title, status, description.

## CLI

### Graph commands

```
alex mint <name> [kind]           create entity (optionally classify it)
alex attr <entity> <kind> <value> attach a descriptor
alex claim <s> <p> <o> [layer]   create a relationship claim
alex about <entity>               show entity: classifications, descriptors, relations
alex entities                     list all entities
```

### Task sugar

Tasks are entities classified as "task" with title and status descriptors.

```
alex add <title>                  create task (auto-numbered t1, t2, ...)
alex list                         list tasks with checkboxes
alex done <id>                    mark task done
alex rm <id>                      remove task and its descriptors
```

### Source ingestion

```
echo "some text" | alex ingest    store raw text as a source entity
alex sources                      list ingested sources
alex source <name>                show source text
```

### Admin

```
alex nuke                         wipe the database
```

## Dependencies

- **Runtime:** [babashka](https://babashka.org/) (`bb`) with the
  `replikativ/datahike` pod (auto-fetched on first run)
- **Library:** [dgm-datahike](https://github.com/tompassarelli/dgm-datahike)
  — cloned as a sibling directory, or set `$DGM_PATH`

Data lives at `~/.alexander/datahike/`.

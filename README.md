# Common Knowledge KB — v0.7

A probabilistic, temporal, and provenance-aware knowledge base built on PostgreSQL. Knowledge is represented as **statements with degrees of belief** rather than binary facts. Every claim is uncertain, every claim has a time, and every claim has a source.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Architecture Overview](#architecture-overview)
- [Installation](#installation)
- [Schema](#schema)
  - [Core Tables](#core-tables)
  - [Belief Model](#belief-model)
  - [Temporal Model](#temporal-model)
  - [Statement Kinds](#statement-kinds)
  - [Key Views](#key-views)
  - [Key Functions](#key-functions)
  - [Triggers](#triggers)
- [Predicates](#predicates)
- [Objects & Statements Kernel](#objects--statements-kernel)
- [Examples](#examples)
- [What's New in v0.7](#whats-new-in-v07)
- [Known Limitations & Roadmap](#known-limitations--roadmap)

---

## Design Principles

Five invariants are load-bearing across the entire system.

**1. Open-world assumption.** Absence of a statement does not imply falsity. `holds_at()` in its default `open_world` mode returns only positively supported statements above a threshold. Absence of evidence is not evidence of absence.

**2. `is_a` / `instance_of` is the canonical type mechanism.** Type membership is a derived materialized cache (`type_membership`) populated automatically by trigger whenever an `is_a` or `instance_of` statement is inserted. Never assert `type_membership` rows directly. Transitive closure over `subtype_of` is resolved at enforcement time via recursive CTE — do not manually materialise every transitive `is_a` pair.

**3. `fuzzy_time` is the canonical time representation.** All temporal bounds live in the statement's `t_start` / `t_end` fuzzy_time fields. For ternary predicates like `located_in(entity, place, time_period)`, the third arg is reserved for **named semantic periods** (e.g. `victorian_era`). When no named period is the semantic argument, use the `no_period` sentinel. Bare year-objects as args are a category error.

**4. Conflicts represent evidential opposition, not logical negation.** `direct_negation` in the conflicts table identifies statements that are evidentially opposed — it does not mean one statement is the logical complement of the other. Open conflicts penalise a statement's `effective_mean` via `statement_effective_belief`. Two competing positive statements coexist; the reasoner weighs them by belief.

**5. Kernel statements are correctable but protected from passive drift.** The `system_kernel` source has `is_protected = true`. `update_trust()` requires `p_override = true` to modify kernel credibility. Kernel facts can be corrected by deliberate human action but will not drift from passive evidence accumulation.

---

## Architecture Overview

```
common_knowledge_schema.sql      ← Tables, types, triggers, views, functions
        ↓
common_predicates_kernel.sql     ← 57 basis predicates across 13 groups
        ↓
common_objects_kernel.sql        ← Entity objects, type hierarchy, disjointness axioms
        ↓
examples.sql                     ← Named individuals, facts, queries, conflict examples
```

The four files must be applied in this order. Each is idempotent (`ON CONFLICT DO NOTHING` / `DO UPDATE` throughout).

---

## Installation

**Prerequisites:** PostgreSQL 15+ with `pgcrypto`, `vector`, and `btree_gist` extensions.

```sql
-- Apply in order:
\i common_knowledge_schema.sql
\i common_predicates_kernel.sql
\i common_objects_kernel.sql
\i examples.sql   -- optional; inserts named individuals and demonstration facts
```

After applying the objects kernel, remove the transitional `process ⊂ entity` backbone stub (now superseded by `process ⊂ event_type ⊂ abstract ⊂ entity`):

```sql
DELETE FROM statements
WHERE predicate_id  = stable_uuid('subtype_of', 'predicate')
  AND object_args   = ARRAY[stable_uuid('process', 'entity'),
                             stable_uuid('entity',  'entity')]
  AND derivation_type = 'axiomatic';
```

---

## Schema

### Core Tables

| Table | Purpose |
|-------|---------|
| `objects` | Unified namespace for every named entity, predicate, context, and source. Fine-grained typing via `type_membership` and `subtype_of`, not the `kind` column. |
| `predicates` | Metadata for each predicate: arity, arg labels, type constraints, domain strictness, inverse predicate link. |
| `statements` | Ground atoms with Beta belief distribution, fuzzy temporal scope, context, derivation metadata, and statement kind. |
| `statement_args` | Normalised per-position argument store (authoritative; `object_args` / `literal_args` on `statements` are denormalised caches). |
| `attestations` | Links statements to sources with confidence weight. `evidence_group_id` prevents double-counting correlated sources. |
| `source_credibility` | Beta(α, β) credibility distribution per `(source, context)` pair. |
| `statement_dependencies` | Authoritative provenance graph: `(parent_id → child_id)` edges with rule name and weight. Used by `why()` and `compute_derived_belief()`. |
| `type_membership` | **Derived cache only.** Populated exclusively by `trg_sync_type_membership`. Never write to it directly. |
| `conflicts` | Pairs of evidentially opposed statements with kind, severity, and resolution state. |
| `contexts` | Tree of reasoning contexts (reality, domain, theory, fiction, hypothetical, game). |
| `object_equivalence` | Probabilistic same-as links for entity resolution. |

### Belief Model

Every statement carries a Beta distribution over its truth:

```
belief_mean = belief_alpha / (belief_alpha + belief_beta)
```

The Beta distribution provides natural uncertainty quantification: a statement with `α=1000, β=0.001` is near-certain; `α=3, β=2` is weak evidence; `α=2, β=5` is a low-credibility counter-claim.

The **effective belief** accounts for source credibility and open conflict severity:

```
effective_mean = raw_mean × (1 − max_open_conflict_severity)
```

All query functions (`holds_at()`, `tell_about()`) filter on `effective_mean`, not raw `belief_mean`. This means an open conflict actively reduces a statement's apparent confidence.

95% confidence intervals use the normal approximation to the Beta:

```
ci = belief_mean ± 1.96 × sqrt(α·β / ((α+β)² · (α+β+1)))
```

### Temporal Model

Each statement has a `t_kind` and optional `t_start` / `t_end` fuzzy timestamps:

| `t_kind` | Meaning |
|----------|---------|
| `eternal` | True outside of time (mathematical facts, definitions) |
| `always` | True for all of modelled time (strong but revisable) |
| `interval` | True during `[t_start, t_end)` |
| `point` | True at a single instant |
| `default` | True until explicitly contradicted |

Fuzzy timestamps are a composite type `(best, lo, hi, granularity)` in Julian Day Numbers, supporting uncertainty bounds at year, decade, century, or exact precision.

```sql
-- Encoding "circa 1828, ±1 year":
ROW(year_to_jd(1828), year_to_jd(1827), year_to_jd(1829), 'year')::fuzzy_time
```

### Statement Kinds

Every statement carries a `statement_kind` that governs inference chain participation:

| Kind | Used for | Inference chain |
|------|----------|----------------|
| `ontological` | `subtype_of`, `disjoint_with`, `is_a` (structural), `equivalent_to` | May participate in logical chains |
| `empirical` | `is_a` (individual), `has_role`, `located_in`, etc. | May participate in logical chains |
| `statistical` | `typical_of`, `correlated_with` | **Excluded** from logical inference; for probabilistic reasoning only |
| `rule` | `implies` with literal args; FOL inference schemas | **Opaque** to `holds_at()` and `tell_about()`; consumed by reasoner |

### Key Views

**`statement_effective_belief`** — canonical belief view. Synthesises raw Beta belief, source-credibility weighting, and open conflict severity into `effective_mean`. This is the primary input for all query functions.

```sql
SELECT id, raw_mean, credibility_adjusted, effective_mean,
       open_conflict_count, conflict_severity
FROM statement_effective_belief
WHERE id = $1;
```

**`statement_belief`** — raw Beta statistics: `belief_mean`, `ci_low`, `ci_high`, `variance`, `evidence_strength`.

**`statement_credibility`** — source-credibility-weighted attestation quality. Enforces the evidence grouping rule: each `evidence_group_id` contributes at most its single highest-weight attestation to prevent confidence inflation from correlated sources.

**`statement_view`** — human-readable join of statements with resolved predicate and arg names.

**`source_credibility_score`** — Beta statistics for each `(source, context)` pair.

### Key Functions

**`holds_at(predicate_id, object_args, time, context_id, mode, p_threshold, p_min_evidence)`**

Temporal query. Returns statements that hold at a given time point.

```sql
-- Was Babbage at Cambridge in 1835?
SELECT * FROM holds_at(
    stable_uuid('affiliated_with', 'predicate'),
    ARRAY[stable_uuid('charles_babbage',         'entity'),
          stable_uuid('university_of_cambridge',  'entity'),
          stable_uuid('lucasian_professor',       'entity')],
    '1835-06-01'::timestamptz,
    stable_uuid('reality', 'context'),
    'open_world',   -- mode
    0.5,            -- p_threshold (filters on effective_mean)
    2.0             -- p_min_evidence (requires real evidence, not just prior)
);
```

Modes: `open_world` (default), `default_true`, `evidence_weighted`. Rule statements (`statement_kind = 'rule'`) are excluded from all modes.

**`tell_about(entity_id, context_id, p_threshold, p_time)`**

Primary "what do we know about X?" interface. Returns all statements where the entity appears in any arg position, resolved to canonical names, ordered by `effective_mean`.

```sql
-- What do we know about Ada Lovelace right now?
SELECT predicate, arg_names, effective_mean, raw_mean,
       open_conflict_count, statement_kind, t_kind
FROM tell_about(
    stable_uuid('ada_lovelace', 'entity'),
    stable_uuid('reality', 'context'),
    0.0,        -- p_threshold
    now()       -- p_time: filter to statements valid at this moment
)
ORDER BY effective_mean DESC;
```

**`why(statement_id)`**

Returns the full provenance DAG for a derived statement, showing depth, rule applied, belief at each node, and effective belief.

```sql
SELECT depth, predicate, arg_names, belief_mean, effective_mean,
       rule_name, edge_weight, derivation_type
FROM why($derived_statement_id)
ORDER BY depth, statement_id;
```

**`compute_derived_belief(parent_ids, chain_length, combination)`**

Computes `(α, β)` for a forward-chained statement from parent belief distributions. Two modes:

- `'min'` (default) — conservative; result mean = `min(parent_means) × 0.9^depth`
- `'log_odds'` — accumulates log-odds increments from a shared uniform prior; two independent 90%-belief parents correctly yield a result meaningfully above 90%

```sql
SELECT out_alpha, out_beta
FROM compute_derived_belief(
    ARRAY[$parent_1, $parent_2],
    1,          -- chain length (1 inference step)
    'log_odds'  -- combination strategy
);
```

**`detect_conflicts(context_id)`**

Scans statements for pairs with the same predicate and args whose 95% Beta confidence intervals do not overlap, and inserts them into `conflicts` as `direct_negation`. Includes a **temporal overlap guard**: two statements in completely non-overlapping time windows are not flagged as conflicting. Populates `severity` (normalised CI gap, range [0, 1]) on each inserted row. Safe to call repeatedly after bulk ingestion.

```sql
SELECT detect_conflicts(stable_uuid('reality', 'context')) AS new_conflicts;
```

**`update_belief(statement_id, weight, supports)`** — Bayesian conjugate update on a statement's `(α, β)`.

**`update_trust(source_id, context_id, correct, weight, p_override)`** — Bayesian conjugate update on source credibility. Requires `p_override = true` for protected sources.

### Triggers

| Trigger | Fires | Effect |
|---------|-------|--------|
| `trg_validate_statement_args` | BEFORE INSERT OR UPDATE on statements | Enforces arity and duplicate literal position rules |
| `trg_sync_statement_args` | AFTER INSERT OR UPDATE on statements | Keeps the normalised `statement_args` table in sync |
| `trg_sync_type_membership` | AFTER INSERT OR UPDATE on statements | Populates `type_membership` cache from `is_a` / `instance_of` statements |
| `trg_z_soft_domain_check` | AFTER INSERT OR UPDATE on statements | Checks object args against `arg_type_ids` via recursive CTE over `subtype_of`; hard violations raise exception, soft violations insert `type_mismatch` conflict |
| `trg_enforce_provenance` | AFTER INSERT on statements (DEFERRABLE) | Requires `statement_dependencies` row for every `forward_chained` or `abduced` statement by commit time |
| `trg_zz_auto_inverse_statement` | AFTER INSERT on statements | For binary predicates with `inverse_predicate_id` set, automatically inserts the inverse statement as `forward_chained` with provenance |

Trigger alphabetical ordering is intentional: `trg_sync_type_membership` fires before `trg_z_soft_domain_check` so the cache is populated before domain checks read from it. `trg_zz_auto_inverse_statement` fires last.

---

## Predicates

57 basis predicates across 13 groups. All are idempotent (`ON CONFLICT DO UPDATE`).

| Group | Predicates |
|-------|-----------|
| **Taxonomic / type** | `is_a`, `subtype_of`, `has_property`, `same_as`, `different_from` |
| **Mereology** | `part_of`, `has_part`, `member_of`, `contains` |
| **Spatial** | `located_in`, `adjacent_to`, `origin_of`, `transferred_to` |
| **Temporal** | `before`, `after`, `during`, `simultaneous_with`, `has_duration` |
| **Causal / functional** | `causes`, `enables`, `prevents`, `used_for`, `capable_of`, `motivated_by` |
| **Agentive / social** | `agent_of`, `created_by`, `has_role`, `affiliated_with`, `related_to`, `opposite_of` |
| **Quantitative** | `has_quantity`, `greater_than`, `approximately_equal` |
| **Epistemic / modal** | `knows`, `believes`, `desires`, `possible`, `necessary` |
| **Linguistic** | `named`, `symbol_for`, `language_of` |
| **Event calculus** | `initiates`, `terminates`, `happens_at`, `holds_at_ec` |
| **Physical / lifecycle** | `made_of`, `has_state`, `precondition_of`, `affects` |
| **Inferential / correlational** | `implies`, `correlated_with`, `typical_of`, `occurs_in` |
| **Structural / logical** | `equivalent_to`, `disjoint_with`, `has_value` |

**Key design notes:**

`has_role(entity, role, scope)` — ternary. Use `no_scope` as the scope arg when a role is genuinely unscoped. Do not use `NULL` or `unknown`.

`located_in(entity, place, time_period)` — ternary. Use `no_period` when no named period is the semantic argument. All temporal scope goes in `t_start` / `t_end`.

`before` ↔ `after` and `part_of` ↔ `has_part` have `inverse_predicate_id` wired. Inserting `before(A, B)` automatically inserts `after(B, A)` via `trg_zz_auto_inverse_statement`.

`correlated_with` and `typical_of` — insert all statements using these predicates with `statement_kind = 'statistical'`. They encode population-level patterns, not individual-level logical claims.

`disjoint_with` — `domain_strictness = 'hard'`. Violations produce `type_violation` conflicts, not `direct_negation`.

---

## Objects & Statements Kernel

The objects kernel seeds the full entity vocabulary, type hierarchy, disjointness lattice, FOL rules, and typicality prototypes.

### Type Hierarchy (selected)

```
entity
├── concrete
│   ├── living
│   │   └── animate
│   │       └── sapient
│   │           └── person ──────┬── mammal ── animal ── organism
│   ├── artifact ── physical_object    └── agent ── institution ── government
│   └── place ── region / location
└── abstract
    ├── concept_type ── biological_taxon
    ├── proposition / information / knowledge_state
    ├── norm ── rule
    ├── role ── mathematician / programmer / inventor / scientist / …
    ├── symbol ── language / word / sentence
    ├── quantity ── number ── real_number ── integer ── natural_number
    ├── time ── time_interval / time_point
    └── event_type ── process / action / change_event / state
```

### Disjointness Lattice

The foundational `abstract ⊥ concrete` split is seeded explicitly at two levels so the domain trigger fires without requiring a running reasoner. Key graded disjointness pairs:

- `person ⊥ institution` (belief ≈ 0.90 — sole-trader edge case)
- `organism ⊥ artifact` (belief ≈ 0.90 — GMO / synthetic biology edge case)
- `truth_value ⊥ number` (belief ≈ 0.70 — Boolean arithmetic overlap)

### Sentinels

| Sentinel | Use |
|----------|-----|
| `no_scope` | Third arg of `has_role` and `affiliated_with` when the role is genuinely unscoped |
| `no_period` | Third arg of `located_in` (and similar ternary predicates) when no named time period is the semantic argument |
| `unknown` | Epistemic state: identity or value is not known. **Not** a scope or period placeholder |

### Statement Kinds in the Kernel

- `subtype_of`, `disjoint_with`, `is_a` (structural), `opposite_of`, `different_from` → `statement_kind = 'ontological'`
- `typical_of` → `statement_kind = 'statistical'`
- `implies` with literal args (FOL inference rules) → `statement_kind = 'rule'`

Rule statements are opaque to `holds_at()` and `tell_about()`. They are queryable by kind and consumed by an external reasoning layer.

---

## Examples

The examples file demonstrates the full workflow against named individuals (Ada Lovelace, Charles Babbage, the Difference Engine).

### Inserting an individual and asserting type

```sql
-- Insert individual
INSERT INTO objects (id, kind, canonical_name, display_name, external_ids)
VALUES (
    stable_uuid('ada_lovelace', 'entity'),
    'entity', 'ada_lovelace', 'Ada Lovelace',
    '{"wikidata":"Q7259"}'::jsonb
) ON CONFLICT (canonical_name, kind) DO NOTHING;

-- Assert type via is_a (fires trg_sync_type_membership automatically)
INSERT INTO statements (
    predicate_id, object_args, belief_alpha, belief_beta,
    statement_kind, t_kind, context_id, derivation_type
) VALUES (
    stable_uuid('is_a', 'predicate'),
    ARRAY[stable_uuid('ada_lovelace', 'entity'),
          stable_uuid('person',       'entity')],
    1000.0, 0.001,
    'empirical', 'eternal',
    stable_uuid('reality', 'context'),
    'user_asserted'
) ON CONFLICT DO NOTHING;
-- type_membership now has (ada_lovelace, person) automatically.
```

### Asserting a temporal role with the no_scope sentinel

```sql
-- has_role(ada_lovelace, mathematician, no_scope) — genuinely unscoped
INSERT INTO statements (
    predicate_id, object_args, belief_alpha, belief_beta,
    statement_kind, t_kind, context_id, derivation_type
) VALUES (
    stable_uuid('has_role', 'predicate'),
    ARRAY[stable_uuid('ada_lovelace',  'entity'),
          stable_uuid('mathematician', 'entity'),
          stable_uuid('no_scope',      'entity')],  -- unscoped, not unknown
    13.0, 2.0,
    'empirical', 'always',
    stable_uuid('reality', 'context'),
    'source_ingested'
);
```

### Asserting a birth location with fuzzy time and no_period

```sql
-- located_in(ada_lovelace, london, no_period), t_kind='point', t_start≈1815
INSERT INTO statements (
    predicate_id, object_args, belief_alpha, belief_beta,
    statement_kind, t_kind, t_start, context_id, derivation_type
) VALUES (
    stable_uuid('located_in', 'predicate'),
    ARRAY[stable_uuid('ada_lovelace', 'entity'),
          stable_uuid('london',       'entity'),
          stable_uuid('no_period',    'entity')],   -- no named period
    13.0, 2.0,
    'empirical', 'point',
    ROW(year_to_jd(1815), year_to_jd(1815), year_to_jd(1816), 'year')::fuzzy_time,
    stable_uuid('reality', 'context'),
    'source_ingested'
);
```

### Forward-chaining a derived statement

```sql
DO $$
DECLARE
    src_1  uuid; src_2 uuid; new_stmt uuid;
    d_alpha double precision; d_beta double precision;
BEGIN
    SELECT id INTO src_1 FROM statements
    WHERE predicate_id = stable_uuid('is_a', 'predicate')
      AND object_args  = ARRAY[stable_uuid('ada_lovelace','entity'),
                                stable_uuid('person','entity')] LIMIT 1;

    SELECT id INTO src_2 FROM statements
    WHERE predicate_id = stable_uuid('subtype_of', 'predicate')
      AND object_args  = ARRAY[stable_uuid('person','entity'),
                                stable_uuid('mammal','entity')] LIMIT 1;

    SELECT out_alpha, out_beta INTO d_alpha, d_beta
    FROM compute_derived_belief(ARRAY[src_1, src_2], 1, 'min');

    INSERT INTO statements (
        predicate_id, object_args, belief_alpha, belief_beta,
        statement_kind, t_kind, context_id,
        derivation_type, derivation_depth, derived_from
    ) VALUES (
        stable_uuid('is_a', 'predicate'),
        ARRAY[stable_uuid('ada_lovelace','entity'),
              stable_uuid('mammal','entity')],
        d_alpha, d_beta,
        'empirical', 'eternal',
        stable_uuid('reality', 'context'),
        'forward_chained', 1, ARRAY[src_1, src_2]
    ) RETURNING id INTO new_stmt;

    -- Provenance required by trg_enforce_provenance
    INSERT INTO statement_dependencies (parent_id, child_id, rule_name, weight)
    VALUES (src_1, new_stmt, 'is_a + subtype_of → is_a', 1.0),
           (src_2, new_stmt, 'is_a + subtype_of → is_a', 1.0);
END $$;
```

### Querying with effective belief

```sql
-- What does the KB know about Ada Lovelace right now?
SELECT predicate, arg_names,
       round(effective_mean::numeric, 4) AS effective_belief,
       round(raw_mean::numeric, 4)       AS raw_belief,
       open_conflict_count,
       statement_kind, t_kind
FROM tell_about(
    stable_uuid('ada_lovelace', 'entity'),
    stable_uuid('reality', 'context'),
    0.0,    -- show everything
    now()   -- filter to currently valid statements
)
ORDER BY effective_mean DESC;
```

### Python reference (psycopg2)

```python
import hashlib, psycopg2

def stable_uuid(name: str, kind: str) -> str:
    h = hashlib.md5(f"{name}:{kind}".encode()).hexdigest()
    return f"{h[:8]}-{h[8:12]}-4{h[13:16]}-{h[16:20]}-{h[20:32]}"

conn = psycopg2.connect("dbname=your_kb")
cur  = conn.cursor()

# Temporal query
cur.execute("""
    SELECT statement_id, belief_mean_val, evidence_str
    FROM holds_at(%s, ARRAY[%s::uuid, %s::uuid, %s::uuid],
                  %s::timestamptz, %s, 'open_world', 0.5, 0.0)
""", (
    stable_uuid('affiliated_with', 'predicate'),
    stable_uuid('charles_babbage', 'entity'),
    stable_uuid('university_of_cambridge', 'entity'),
    stable_uuid('lucasian_professor', 'entity'),
    '1835-06-01',
    stable_uuid('reality', 'context'),
))

# tell_about
cur.execute("""
    SELECT predicate, arg_names, effective_mean, statement_kind
    FROM tell_about(%s, %s, %s, %s::timestamptz)
    ORDER BY effective_mean DESC
""", (
    stable_uuid('ada_lovelace', 'entity'),
    stable_uuid('reality', 'context'),
    0.0,
    '1843-01-01',
))

# Detect conflicts after bulk ingestion
cur.execute("SELECT detect_conflicts(%s)", (stable_uuid('reality','context'),))
print(f"New conflicts: {cur.fetchone()[0]}")
conn.commit()
```

---

## What's New in v0.7

### Fix #17 — `statement_kind` column
A new `statement_kind` enum (`ontological`, `empirical`, `statistical`, `rule`) on every statement governs inference chain participation. Statistical statements (`typical_of`, `correlated_with`) are excluded from `holds_at()` and `compute_derived_belief()`. Rule statements (`implies` with literal args) are opaque to all query functions — they are schemas for an external reasoner, not factual claims.

### Fix #18 — Temporal overlap guard in `detect_conflicts()`
The conflict detection self-join now requires temporal overlap before comparing confidence intervals. Two statements with non-overlapping time windows are not in conflict even if their CIs are disjoint. This eliminates spurious conflicts between e.g. `has_role(Babbage, professor, Cambridge)` in 1828 vs 1890.

### Fix #19 — Conflict severity
The `conflicts` table gains a `severity double precision` column, populated by `detect_conflicts()` as the normalised CI gap (range [0, 1]). Higher severity = stronger statistical incompatibility.

### Fix #20 — `statement_effective_belief` view
A new canonical view synthesises raw Beta belief, source credibility, and open conflict severity into a single `effective_mean`. `holds_at()` (open_world mode) and `tell_about()` now filter and sort on `effective_mean`. Open conflicts actively reduce apparent confidence — the conflict detection feedback loop is now closed.

### Fix #21 — `log_odds` combination fix in `compute_derived_belief()`
The v0.6 log_odds mode averaged log-odds across parents (dividing by n), destroying the independence signal. Fixed to accumulate (sum) log-odds increments from a shared uniform prior. Two independent 90%-belief parents now correctly produce a result meaningfully above 90%.

### Fix #22 — Transitive domain enforcement
The domain check trigger now resolves type membership via recursive CTE over `subtype_of` rather than a flat `type_membership` lookup. Predicates constraining args to abstract types (e.g. `capable_of` → `animate`) now correctly accept subtype instances (e.g. `person → sapient → animate`) without requiring manual `is_a` materialisation. The trigger also fires on `UPDATE` (was `INSERT` only), closing the silent bypass where `object_args` could be swapped post-insertion. As a result, redundant `is_a` rows for role subtypes (e.g. `is_a(mathematician, role)`) have been removed from the objects kernel.

### Fix #23 — `no_period` sentinel
A new `no_period` sentinel entity distinguishes time-period arguments from role-scope arguments. Use `no_period` as the third arg of `located_in` (and similar) when no named period is the semantic argument. `no_scope` is now restricted to role-scope args only. `no_scope` descriptions updated throughout.

### Fix #24 — Inverse predicate automation
`predicates` gains an `inverse_predicate_id` column. The `trg_zz_auto_inverse_statement` trigger automatically inserts the inverse statement and provenance edge on any binary statement insert. Wired pairs: `before ↔ after`, `part_of ↔ has_part`, `contains → part_of`. Prevents `before(A, B)` and `after(A, B)` from diverging in belief.

### Fix #25 — Temporal filter on `tell_about()`
`tell_about()` gains an optional `p_time timestamptz` parameter. When supplied, restricts results to statements whose temporal scope includes that time point. Transforms `tell_about` from a history dump into a genuine "what is true about X right now?" query.

### Fix #26 — Conflict lookup index
A composite index `(context_id, predicate_id, object_args) WHERE t_kind != 'eternal'` makes `detect_conflicts()` viable on large tables after bulk ingestion.

---

## Known Limitations & Roadmap

**Belief mixes epistemic types.** Ontological uncertainty, empirical uncertainty, and statistical uncertainty are all represented as Beta distributions. The `statement_kind` column (v0.7) is the first step toward separating them; formal epistemic typing is planned for v0.8.

**Conflicts do not yet block inference chains.** `compute_derived_belief()` raises a `NOTICE` when statistical parents are used in a logical chain, but does not block it. Full enforcement — statistical statements cannot feed `forward_chained` derivations — is planned for v0.8.

**Source combination formula is implicit.** The relationship between attestation weights, source credibility, and statement `(α, β)` is handled by `update_belief()` and `statement_credibility` in parallel with no formal bridge. A written policy decision formalising how attestation weights map to statement belief is deferred to a future design session.

**Transitive closure is on-demand.** The recursive CTE in `trg_z_soft_domain_check` resolves closure at enforcement time, which is correct but not pre-materialised. For very deep hierarchies, consider caching or pre-computing closure in a separate table.

**The `stable_uuid()` function has a minor RFC 4122 variant-bit deviation.** The variant octet is not set correctly. This has no practical consequence until external systems that validate UUIDs strictly are involved. Fix deferred to v0.8.

**Context inheritance is a tree, not a DAG.** Multi-parent context inheritance is not yet supported. Deferred to v0.8 when a concrete use case drives it.

---

## License

MIT License

Copyright (c) 2026

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


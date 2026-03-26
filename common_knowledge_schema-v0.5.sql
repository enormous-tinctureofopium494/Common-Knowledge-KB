-- =============================================================
-- Common Knowledge KB — PostgreSQL Schema (v0.5)
-- =============================================================
-- Changes from v0.4:
--
--   STRUCTURAL
--   • object.kind simplified to coarse infrastructure only:
--     'entity', 'source', 'context', 'predicate'.
--     All finer typing now lives in subtype_of statements + type_membership.
--     'person' retained as a seed type object, not an enum value.
--   • basis_weights jsonb dropped from objects (undocumented, unused).
--   • negated boolean dropped from statements.
--     Evidential opposition is now handled exclusively via the
--     conflicts table (conflict_kind = 'direct_negation').
--     holds_at() updated accordingly.
--   • belief_mean added as a GENERATED ALWAYS stored column on
--     statements for fast precomputed access.
--
--   ARGUMENT REPRESENTATION
--   • statement_args table introduced: normalized, FK-enforced,
--     per-position indexable arguments.
--   • object_args uuid[] and literal_args jsonb RETAINED on statements
--     as a denormalized cache for fast tuple-matching queries.
--   • A trigger (trg_sync_statement_args) keeps statement_args in sync
--     with the arrays on INSERT/UPDATE.
--   • validate_statement_args() extended to enforce position < arity
--     and FK validity.
--
--   TYPE SYSTEM (three-layer model)
--   • interpretation enum added to statements:
--     'ontological', 'modeling', 'legal_fiction', 'metaphorical'.
--     Allows encoding "AI is an agent" as modeling, not ontology.
--   • domain_strictness enum added to predicates:
--     'hard', 'soft', 'none'.
--     Hard violations reject on insert; soft violations insert and
--     auto-record a type_mismatch conflict for belief attenuation.
--   • Seed data extended with ontological backbone objects:
--     entity, concrete, abstract, living, animate, sapient, artifact,
--     process, group — as 'entity'-kinded objects.
--   • models_as predicate seeded: models_as(subject, type, context).
--     Use for non-ontological modeling assumptions.
--   • has_role predicate seeded: has_role(entity, role, scope).
--   • has_capacity predicate seeded: has_capacity(entity, capacity).
--
--   PROVENANCE
--   • statement_dependencies table introduced: replaces the weak
--     derived_from uuid[] array. Records (parent, child, rule, weight)
--     for belief propagation and explanation graphs.
--     derived_from uuid[] retained on statements as a fast cache.
--
--   SOURCE CREDIBILITY
--   • is_protected boolean added to source_credibility.
--     Protected sources (e.g. system_kernel) require explicit override
--     to modify; update_trust() enforces this.
--   • system_kernel seeded with is_protected = true.
--
--   OPEN WORLD / REASONING MODE
--   • holds_at() gains a p_mode parameter:
--     'open_world'       — returns only positively supported statements
--     'default_true'     — original behaviour (true until contradicted)
--     'evidence_weighted'— returns all statements ordered by belief_mean
--   • Default mode is 'open_world' (consistent with Bayesian/open-world
--     design intent).
--
--   IDENTITY
--   • object_equivalence table introduced: probabilistic same-as links
--     between objects for entity resolution and alias canonicalization.
--
--   CONTEXT
--   • Context model unchanged (tree via parent_id). DAG noted as
--     future work when multi-parent context inheritance is needed.
--
-- =============================================================


-- ── Extensions ───────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "vector";
CREATE EXTENSION IF NOT EXISTS "btree_gist";


-- ── Stable UUID helper ────────────────────────────────────────
CREATE OR REPLACE FUNCTION stable_uuid(p_key text)
RETURNS uuid LANGUAGE sql IMMUTABLE STRICT AS $$
    SELECT (
        substring(md5(p_key), 1,  8) || '-' ||
        substring(md5(p_key), 9,  4) || '-4' ||
        substring(md5(p_key), 14, 3) || '-' ||
        substring(md5(p_key), 17, 4) || '-' ||
        substring(md5(p_key), 21, 12)
    )::uuid;
$$;

CREATE OR REPLACE FUNCTION stable_uuid(p_name text, p_kind text)
RETURNS uuid LANGUAGE sql IMMUTABLE STRICT AS $$
    SELECT stable_uuid(p_name || ':' || p_kind);
$$;


-- ── Enums ────────────────────────────────────────────────────

-- Coarse infrastructure kind only.
-- All domain-level typing lives in subtype_of / type_membership.
CREATE TYPE object_kind AS ENUM (
    'entity',       -- persons, institutions, concepts, events, quantities, etc.
    'predicate',    -- relation/property schema objects
    'context',      -- reasoning contexts (reality, domains, theories, fictions…)
    'source'        -- epistemic sources (users, databases, LLMs, …)
);

CREATE TYPE temporal_kind AS ENUM (
    'eternal',      -- true outside of time (mathematical facts, definitions)
    'always',       -- true for all of recorded/modeled time
    'interval',     -- true during [t_start, t_end)
    'point',        -- true at a single instant
    'default'       -- true until explicitly contradicted (open-world default)
);

CREATE TYPE time_granularity AS ENUM (
    'exact',
    'day',
    'month',
    'year',
    'decade',
    'century',
    'unknown'
);

CREATE TYPE predicate_status AS ENUM (
    'proposed',
    'confirmed',
    'deprecated'
);

-- How strictly predicate domain constraints are enforced.
-- hard  → reject insert if domain constraint violated
-- soft  → insert + auto-record type_mismatch conflict
-- none  → no domain enforcement
CREATE TYPE domain_strictness AS ENUM (
    'hard',
    'soft',
    'none'
);

CREATE TYPE context_kind AS ENUM (
    'reality',
    'domain',
    'theory',
    'fiction',
    'hypothetical',
    'game'
);

CREATE TYPE derivation_type AS ENUM (
    'axiomatic',
    'user_asserted',
    'source_ingested',
    'forward_chained',
    'abduced',
    'learned'
);

CREATE TYPE conflict_kind AS ENUM (
    'direct_negation',    -- P(a) vs ¬P(a) encoded as two competing statements
    'mutual_exclusion',   -- at most one of a set can hold
    'type_violation',     -- argument fails domain constraint
    'type_mismatch',      -- soft domain violation (auto-generated)
    'temporal_overlap',   -- two interval statements overlap impossibly
    'value_conflict'      -- literal values are mutually inconsistent
);

-- Epistemic interpretation tag on statements.
-- Prevents silent category errors when modeling conventions differ from ontology.
CREATE TYPE statement_interpretation AS ENUM (
    'ontological',    -- genuine ontological claim
    'modeling',       -- convenient modeling assumption (e.g. "AI is an agent")
    'legal_fiction',  -- legally or conventionally true, not ontologically
    'metaphorical'    -- figurative / analogical
);


-- ── Composite type: fuzzy timestamp ──────────────────────────
-- best: Julian Day Number of the central estimate
-- lo/hi: Julian Day Numbers of the uncertainty bounds
-- granularity: precision of the best estimate
-- Note: lo/hi are intentionally fuzzy themselves; a future reasoner
-- may treat them as the means of further Beta-like distributions.
CREATE TYPE fuzzy_time AS (
    best        double precision,   -- JD central estimate
    lo          double precision,   -- JD lower bound (uncertain)
    hi          double precision,   -- JD upper bound (uncertain)
    granularity time_granularity
);

CREATE OR REPLACE FUNCTION year_to_jd(y integer)
RETURNS double precision LANGUAGE sql IMMUTABLE AS $$
    SELECT 365.25 * (y + 4716) - 1524.5;
$$;

CREATE OR REPLACE FUNCTION jd_to_tstz(jd double precision)
RETURNS timestamptz LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN jd IS NULL      THEN NULL
        WHEN jd < 1721425.5  THEN '0001-01-01 00:00:00+00'::timestamptz
        WHEN jd > 5373484.5  THEN '9999-12-31 23:59:59+00'::timestamptz
        ELSE to_timestamp((jd - 2440587.5) * 86400.0)
    END;
$$;


-- ── updated_at trigger ────────────────────────────────────────
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;


-- =============================================================
-- CORE TABLES
-- =============================================================

-- ── Objects ───────────────────────────────────────────────────
-- Unified namespace for every named entity in the KB.
-- Fine-grained typing is expressed via type_membership and
-- subtype_of statements, NOT via this kind column.
CREATE TABLE objects (
    id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    kind            object_kind NOT NULL,
    canonical_name  text        NOT NULL,
    display_name    text,
    aliases         text[]      NOT NULL DEFAULT '{}',
    description     text,
    embedding       vector(768),   -- for semantic similarity / entity resolution
    external_ids    jsonb,         -- {"wikidata": "Q...", "dbpedia": "...", …}
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT canonical_name_kind_unique UNIQUE (canonical_name, kind)
);

CREATE INDEX idx_objects_kind      ON objects (kind);
CREATE INDEX idx_objects_aliases   ON objects USING GIN (aliases);
CREATE INDEX idx_objects_external  ON objects USING GIN (external_ids);
CREATE INDEX idx_objects_embedding ON objects USING hnsw (embedding vector_cosine_ops);

CREATE TRIGGER trg_objects_updated_at
    BEFORE UPDATE ON objects
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- ── Predicate metadata ────────────────────────────────────────
CREATE TABLE predicates (
    id               uuid               PRIMARY KEY
                         REFERENCES objects (id) ON DELETE CASCADE,
    arity            int                NOT NULL CHECK (arity BETWEEN 1 AND 8),
    -- arg_labels: human-readable role names per position (e.g. ['subject','object'])
    arg_labels       text[],
    -- arg_type_ids: expected type object IDs per position (soft or hard per domain_strictness)
    arg_type_ids     uuid[],
    fol_definition   text,
    nl_description   text,
    source_predicate text,             -- provenance if imported from external schema
    is_basis         boolean            NOT NULL DEFAULT false,
    domain_strictness domain_strictness NOT NULL DEFAULT 'soft',
    status           predicate_status   NOT NULL DEFAULT 'proposed',
    introduced_by    uuid               REFERENCES objects (id),
    introduced_at    timestamptz        NOT NULL DEFAULT now()
);

CREATE INDEX idx_predicates_basis   ON predicates (is_basis) WHERE is_basis;
CREATE INDEX idx_predicates_status  ON predicates (status);


-- ── Context metadata ──────────────────────────────────────────
-- Tree structure (parent_id). DAG generalisation deferred to v0.6+
-- when multi-parent context inheritance is concretely needed.
CREATE TABLE contexts (
    id          uuid         PRIMARY KEY
                    REFERENCES objects (id) ON DELETE CASCADE,
    kind        context_kind NOT NULL DEFAULT 'reality',
    parent_id   uuid         REFERENCES contexts (id),
    description text
);


-- ── Orphan-guard triggers ─────────────────────────────────────
CREATE OR REPLACE FUNCTION guard_predicate_object()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.kind = 'predicate' THEN
        IF NOT EXISTS (SELECT 1 FROM predicates WHERE id = NEW.id) THEN
            RAISE EXCEPTION
                'objects row with kind=''predicate'' requires a matching predicates row (id=%)', NEW.id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION guard_context_object()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.kind = 'context' THEN
        IF NOT EXISTS (SELECT 1 FROM contexts WHERE id = NEW.id) THEN
            RAISE EXCEPTION
                'objects row with kind=''context'' requires a matching contexts row (id=%)', NEW.id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_guard_predicate_object
    AFTER INSERT ON objects
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION guard_predicate_object();

CREATE CONSTRAINT TRIGGER trg_guard_context_object
    AFTER INSERT ON objects
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION guard_context_object();


-- ── Statements ───────────────────────────────────────────────
-- Ground atoms with belief, time, context, and derivation metadata.
--
-- Negation policy (v0.5):
--   The `negated` boolean has been removed. Logical negation and
--   evidential opposition are expressed via the conflicts table
--   (conflict_kind = 'direct_negation'). Two competing statements
--   P(a) and ¬P(a) are both stored as positive statements; their
--   conflict is registered explicitly, and the reasoner weighs them
--   by belief_mean. This preserves evidential gradation and avoids
--   conflating "we have evidence against X" with "X is false".
--
-- Argument caching policy:
--   object_args and literal_args are denormalized caches retained
--   for fast tuple-matching and GIN indexing. The authoritative,
--   normalized form is statement_args. A sync trigger keeps them
--   consistent.
CREATE TABLE statements (
    id               uuid                     PRIMARY KEY DEFAULT gen_random_uuid(),
    predicate_id     uuid                     NOT NULL REFERENCES objects (id),

    -- Denormalized argument cache (authoritative: statement_args)
    object_args      uuid[]                   NOT NULL DEFAULT '{}',
    literal_args     jsonb                    NOT NULL DEFAULT '[]'
                         CHECK (jsonb_typeof(literal_args) = 'array'),

    -- Belief: Beta(alpha, beta) distribution over truth
    belief_alpha     double precision         NOT NULL DEFAULT 1.0
                         CHECK (belief_alpha > 0),
    belief_beta      double precision         NOT NULL DEFAULT 1.0
                         CHECK (belief_beta  > 0),
    -- Precomputed belief mean for fast queries; kept in sync by trigger
    belief_mean      double precision         GENERATED ALWAYS AS (
                         belief_alpha / (belief_alpha + belief_beta)
                     ) STORED,

    -- Epistemic interpretation tag
    interpretation   statement_interpretation NOT NULL DEFAULT 'ontological',

    -- Temporal scope
    t_kind           temporal_kind            NOT NULL DEFAULT 'default',
    t_start          fuzzy_time,
    t_end            fuzzy_time,
    t_start_ts       timestamptz              GENERATED ALWAYS AS (
                         jd_to_tstz((t_start).best)
                     ) STORED,
    t_end_ts         timestamptz              GENERATED ALWAYS AS (
                         jd_to_tstz((t_end).best)
                     ) STORED,

    -- Reasoning context
    context_id       uuid                     NOT NULL REFERENCES objects (id),

    -- Provenance
    derivation_type  derivation_type          NOT NULL DEFAULT 'user_asserted',
    derivation_depth int                      NOT NULL DEFAULT 0
                         CHECK (derivation_depth >= 0),
    -- Denormalized provenance cache (authoritative: statement_dependencies)
    derived_from     uuid[]                   NOT NULL DEFAULT '{}',

    created_at       timestamptz              NOT NULL DEFAULT now(),
    updated_at       timestamptz              NOT NULL DEFAULT now(),

    CONSTRAINT args_nonempty CHECK (
        cardinality(object_args) >= 1
        OR jsonb_array_length(literal_args) >= 1
    )
);

CREATE INDEX idx_stmt_predicate     ON statements (predicate_id);
CREATE INDEX idx_stmt_context       ON statements (context_id);
CREATE INDEX idx_stmt_t_kind        ON statements (t_kind);
CREATE INDEX idx_stmt_deriv_type    ON statements (derivation_type);
CREATE INDEX idx_stmt_belief_mean   ON statements (belief_mean DESC);
CREATE INDEX idx_stmt_object_args   ON statements USING GIN (object_args);
CREATE INDEX idx_stmt_derived_from  ON statements USING GIN (derived_from);
CREATE INDEX idx_stmt_interp        ON statements (interpretation);

-- Partial index for temporal range queries via GiST
CREATE INDEX idx_stmt_temporal_range ON statements USING GIST (
    tstzrange(
        coalesce(t_start_ts, '-infinity'::timestamptz),
        coalesce(t_end_ts,   'infinity'::timestamptz),
        '[)'
    )
) WHERE t_kind IN ('interval', 'point');

CREATE INDEX idx_stmt_eternal ON statements (predicate_id)
    WHERE t_kind = 'eternal';

CREATE TRIGGER trg_statements_updated_at
    BEFORE UPDATE ON statements
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- ── Normalized argument table ─────────────────────────────────
-- Authoritative per-position argument store.
-- object_id XOR literal_value must be non-null (enforced by CHECK).
-- position is 0-based, must be < predicate arity (enforced by trigger).
CREATE TABLE statement_args (
    statement_id  uuid  NOT NULL REFERENCES statements (id) ON DELETE CASCADE,
    position      int   NOT NULL CHECK (position >= 0),
    object_id     uuid  REFERENCES objects (id),
    literal_value jsonb,
    PRIMARY KEY (statement_id, position),
    CONSTRAINT arg_xor CHECK (
        (object_id IS NOT NULL)::int +
        (literal_value IS NOT NULL)::int = 1
    )
);

CREATE INDEX idx_sargs_object   ON statement_args (object_id) WHERE object_id IS NOT NULL;
CREATE INDEX idx_sargs_stmt     ON statement_args (statement_id);


-- ── Statement arg validation trigger ─────────────────────────
-- Validates arity, duplicate positions, and position bounds.
-- Also enforces domain_strictness: hard violations reject;
-- soft violations insert and schedule a type_mismatch conflict
-- (recorded after-statement by a separate trigger).
CREATE OR REPLACE FUNCTION validate_statement_args()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_arity    int;
    v_total    int;
    v_dup_pos  int;
BEGIN
    SELECT arity INTO v_arity FROM predicates WHERE id = NEW.predicate_id;

    IF v_arity IS NULL THEN
        RAISE EXCEPTION 'predicate % not found in predicates table', NEW.predicate_id;
    END IF;

    v_total := cardinality(NEW.object_args) + jsonb_array_length(NEW.literal_args);

    IF v_total != v_arity THEN
        RAISE EXCEPTION
            'argument count mismatch: predicate arity=%, got object_args=% + literal_args=%',
            v_arity, cardinality(NEW.object_args), jsonb_array_length(NEW.literal_args);
    END IF;

    -- Check for duplicate pos values in literal_args
    SELECT count(*) INTO v_dup_pos
    FROM (
        SELECT elem->>'pos'
        FROM jsonb_array_elements(NEW.literal_args) AS elem
        GROUP BY elem->>'pos'
        HAVING count(*) > 1
    ) dups;

    IF v_dup_pos > 0 THEN
        RAISE EXCEPTION 'literal_args contains duplicate pos values';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_statement_args
    BEFORE INSERT OR UPDATE ON statements
    FOR EACH ROW EXECUTE FUNCTION validate_statement_args();


-- ── Sync trigger: statements → statement_args ─────────────────
-- Keeps the normalized statement_args table in sync with the
-- denormalized object_args/literal_args arrays on statements.
-- Runs after insert/update on statements.
CREATE OR REPLACE FUNCTION sync_statement_args()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_oid     uuid;
    v_pos     int;
    v_elem    jsonb;
    v_lit_pos int;
BEGIN
    -- Remove existing normalized args for this statement
    DELETE FROM statement_args WHERE statement_id = NEW.id;

    -- Insert object args (positions 0..n-1 in order of array)
    FOR v_pos IN 1 .. cardinality(NEW.object_args) LOOP
        INSERT INTO statement_args (statement_id, position, object_id)
        VALUES (NEW.id, v_pos - 1, NEW.object_args[v_pos]);
    END LOOP;

    -- Insert literal args using their embedded 'pos' field if present,
    -- otherwise assign sequentially after object_args
    FOR v_pos IN 0 .. jsonb_array_length(NEW.literal_args) - 1 LOOP
        v_elem    := NEW.literal_args -> v_pos;
        v_lit_pos := COALESCE((v_elem->>'pos')::int,
                              cardinality(NEW.object_args) + v_pos);
        INSERT INTO statement_args (statement_id, position, literal_value)
        VALUES (NEW.id, v_lit_pos, v_elem);
    END LOOP;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_sync_statement_args
    AFTER INSERT OR UPDATE ON statements
    FOR EACH ROW EXECUTE FUNCTION sync_statement_args();


-- =============================================================
-- VIEWS
-- =============================================================

CREATE VIEW statement_belief AS
SELECT
    id,
    belief_alpha,
    belief_beta,
    belief_mean,
    belief_alpha + belief_beta                                AS evidence_strength,
    (belief_alpha * belief_beta)
        / (pow(belief_alpha + belief_beta, 2)
           * (belief_alpha + belief_beta + 1))                AS variance,
    GREATEST(0,
        belief_mean - 1.96 * sqrt(
            (belief_alpha * belief_beta)
            / (pow(belief_alpha + belief_beta, 2)
               * (belief_alpha + belief_beta + 1))
        )
    )                                                         AS ci_low,
    LEAST(1,
        belief_mean + 1.96 * sqrt(
            (belief_alpha * belief_beta)
            / (pow(belief_alpha + belief_beta, 2)
               * (belief_alpha + belief_beta + 1))
        )
    )                                                         AS ci_high,
    interpretation,
    t_kind,
    context_id,
    derivation_type,
    derivation_depth
FROM statements;


CREATE VIEW statement_view AS
SELECT
    s.id,
    p.canonical_name                  AS predicate,
    s.object_args,
    arg_names.names                   AS arg_names,
    s.literal_args,
    s.belief_mean,
    s.belief_alpha + s.belief_beta    AS evidence_strength,
    s.interpretation,
    s.t_kind,
    s.t_start,
    s.t_end,
    c.canonical_name                  AS context,
    s.derivation_type,
    s.derivation_depth,
    s.derived_from,
    s.created_at
FROM statements s
JOIN objects p ON p.id = s.predicate_id
JOIN objects c ON c.id = s.context_id
LEFT JOIN LATERAL (
    SELECT array_agg(o.canonical_name ORDER BY ord) AS names
    FROM unnest(s.object_args) WITH ORDINALITY AS u(oid, ord)
    JOIN objects o ON o.id = u.oid
) arg_names ON true;


-- =============================================================
-- SUPPORTING TABLES
-- =============================================================

-- ── Attestations ─────────────────────────────────────────────
-- Records which sources support which statements, and with what weight.
-- evidence_group_id groups attestations that are not independent
-- (same underlying study, same author, etc.) to avoid double-counting.
CREATE TABLE attestations (
    id                uuid             PRIMARY KEY DEFAULT gen_random_uuid(),
    statement_id      uuid             NOT NULL REFERENCES statements (id) ON DELETE CASCADE,
    source_id         uuid             NOT NULL REFERENCES objects (id),
    evidence_group_id uuid,            -- non-null → attestations share an origin
    confidence_weight double precision NOT NULL DEFAULT 1.0
                          CHECK (confidence_weight BETWEEN 0.0 AND 1.0),
    raw_claim         text,
    url               text,
    accessed_at       timestamptz,
    created_at        timestamptz      NOT NULL DEFAULT now()
);

CREATE INDEX idx_attest_statement      ON attestations (statement_id);
CREATE INDEX idx_attest_source         ON attestations (source_id);
CREATE INDEX idx_attest_evidence_group ON attestations (evidence_group_id)
    WHERE evidence_group_id IS NOT NULL;


-- ── Source credibility ───────────────────────────────────────
-- Beta(alpha, beta) credibility distribution per (source, context).
-- is_protected: if true, update_trust() requires explicit override flag.
--   Used for system_kernel and other near-axiomatic sources.
CREATE TABLE source_credibility (
    source_id    uuid             NOT NULL REFERENCES objects (id),
    context_id   uuid             NOT NULL REFERENCES objects (id),
    alpha        double precision NOT NULL DEFAULT 1.0 CHECK (alpha > 0),
    beta         double precision NOT NULL DEFAULT 1.0 CHECK (beta  > 0),
    is_protected boolean          NOT NULL DEFAULT false,
    updated_at   timestamptz      NOT NULL DEFAULT now(),
    PRIMARY KEY (source_id, context_id)
);

CREATE VIEW source_credibility_score AS
SELECT
    source_id,
    context_id,
    alpha / (alpha + beta)                          AS mean,
    alpha + beta                                     AS evidence_strength,
    is_protected,
    GREATEST(0,
        alpha / (alpha + beta)
        - 1.96 * sqrt(alpha * beta
                      / (pow(alpha + beta, 2) * (alpha + beta + 1)))
    )                                                AS ci_low,
    LEAST(1,
        alpha / (alpha + beta)
        + 1.96 * sqrt(alpha * beta
                      / (pow(alpha + beta, 2) * (alpha + beta + 1)))
    )                                                AS ci_high
FROM source_credibility;


CREATE VIEW statement_credibility AS
SELECT
    a.statement_id,
    sum(coalesce(sc_domain.mean, sc_reality.mean, 0.5)
        * coalesce(sc_domain.evidence_strength, sc_reality.evidence_strength, 2.0)
        * a.confidence_weight)
        / nullif(
            sum(coalesce(sc_domain.evidence_strength, sc_reality.evidence_strength, 2.0)
                * a.confidence_weight),
            0
          )                                          AS weighted_credibility,
    sum(coalesce(sc_domain.evidence_strength,
                 sc_reality.evidence_strength, 2.0)
        * a.confidence_weight)                       AS total_source_weight,
    count(a.id)                                      AS source_count
FROM attestations a
JOIN statements s ON s.id = a.statement_id
LEFT JOIN source_credibility_score sc_domain
       ON sc_domain.source_id  = a.source_id
      AND sc_domain.context_id = s.context_id
LEFT JOIN source_credibility_score sc_reality
       ON sc_reality.source_id  = a.source_id
      AND sc_reality.context_id = stable_uuid('reality', 'context')
GROUP BY a.statement_id;


-- ── Statement dependencies ────────────────────────────────────
-- Replaces the weak derived_from uuid[] array as the authoritative
-- provenance graph. Records (parent → child) derivation edges with
-- the rule applied and the weight of the dependency.
-- Use for belief propagation, explanation graphs, and audit trails.
-- derived_from on statements is maintained as a fast cache of parent IDs.
CREATE TABLE statement_dependencies (
    parent_id    uuid             NOT NULL REFERENCES statements (id) ON DELETE CASCADE,
    child_id     uuid             NOT NULL REFERENCES statements (id) ON DELETE CASCADE,
    rule_name    text,            -- name of inference rule / function applied
    weight       double precision NOT NULL DEFAULT 1.0 CHECK (weight > 0),
    created_at   timestamptz      NOT NULL DEFAULT now(),
    PRIMARY KEY (parent_id, child_id)
);

CREATE INDEX idx_sdep_child  ON statement_dependencies (child_id);
CREATE INDEX idx_sdep_parent ON statement_dependencies (parent_id);


-- ── Predicate subsumption ────────────────────────────────────
-- Probabilistic sub-predicate / super-predicate relationships.
-- e.g. is_a(child=loves, parent=has_relation_to): belief-weighted.
CREATE TABLE predicate_subsumption (
    child_id    uuid             NOT NULL REFERENCES objects (id),
    parent_id   uuid             NOT NULL REFERENCES objects (id),
    alpha       double precision NOT NULL DEFAULT 1.0 CHECK (alpha > 0),
    beta        double precision NOT NULL DEFAULT 1.0 CHECK (beta  > 0),
    context_id  uuid             REFERENCES objects (id),
    PRIMARY KEY (child_id, parent_id)
);


-- ── Type membership ──────────────────────────────────────────
-- Probabilistic membership of an object in a type.
-- This is the primary fine-grained typing mechanism.
-- Replaces the old object.kind enum for domain-level types.
-- e.g. type_membership(aristotle, person, alpha=19, beta=1)
CREATE TABLE type_membership (
    object_id   uuid             NOT NULL REFERENCES objects (id),
    type_id     uuid             NOT NULL REFERENCES objects (id),
    alpha       double precision NOT NULL DEFAULT 1.0 CHECK (alpha > 0),
    beta        double precision NOT NULL DEFAULT 1.0 CHECK (beta  > 0),
    context_id  uuid             REFERENCES objects (id),
    PRIMARY KEY (object_id, type_id)
);

CREATE INDEX idx_typemem_type   ON type_membership (type_id);
CREATE INDEX idx_typemem_object ON type_membership (object_id);


-- ── Conflicts ────────────────────────────────────────────────
-- Records detected conflicts between statements.
-- This is also how negation is represented (v0.5+):
--   conflict_kind = 'direct_negation' between P(a) and its evidential opposite.
-- resolved: set true when a resolution strategy has been applied.
-- resolution_note: human-readable explanation of how the conflict was resolved.
CREATE TABLE conflicts (
    id              uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
    statement_a     uuid          NOT NULL REFERENCES statements (id),
    statement_b     uuid          NOT NULL REFERENCES statements (id),
    conflict_kind   conflict_kind,
    resolved        boolean       NOT NULL DEFAULT false,
    resolution_note text,
    created_at      timestamptz   NOT NULL DEFAULT now()
);

CREATE INDEX idx_conflicts_a        ON conflicts (statement_a);
CREATE INDEX idx_conflicts_b        ON conflicts (statement_b);
CREATE INDEX idx_conflicts_resolved ON conflicts (resolved) WHERE NOT resolved;


-- ── Object equivalence ────────────────────────────────────────
-- Probabilistic same-as links for entity resolution.
-- Prevents graph fragmentation when the same entity is ingested
-- under different names or from different sources.
-- alpha/beta: Beta distribution over whether the two objects are
-- truly the same entity.
CREATE TABLE object_equivalence (
    object_a   uuid             NOT NULL REFERENCES objects (id),
    object_b   uuid             NOT NULL REFERENCES objects (id),
    alpha      double precision NOT NULL DEFAULT 1.0 CHECK (alpha > 0),
    beta       double precision NOT NULL DEFAULT 1.0 CHECK (beta  > 0),
    context_id uuid             REFERENCES objects (id),
    PRIMARY KEY (object_a, object_b),
    CONSTRAINT equiv_no_self CHECK (object_a <> object_b),
    CONSTRAINT equiv_canonical CHECK (object_a < object_b)  -- enforce canonical ordering
);

CREATE INDEX idx_equiv_b ON object_equivalence (object_b);


-- =============================================================
-- FUNCTIONS
-- =============================================================

-- ── update_trust ──────────────────────────────────────────────
-- Updates source credibility via Bayesian update (Beta conjugate).
-- p_override: required to update a protected source. If false and
-- the source is protected, raises an exception.
CREATE OR REPLACE FUNCTION update_trust(
    p_source_id  uuid,
    p_context_id uuid,
    p_correct    boolean,
    p_weight     double precision DEFAULT 1.0,
    p_override   boolean          DEFAULT false
) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_protected boolean;
BEGIN
    INSERT INTO source_credibility (source_id, context_id, alpha, beta, is_protected)
    VALUES (p_source_id, p_context_id, 1.0, 1.0, false)
    ON CONFLICT (source_id, context_id) DO NOTHING;

    SELECT is_protected INTO v_protected
    FROM source_credibility
    WHERE source_id = p_source_id AND context_id = p_context_id;

    IF v_protected AND NOT p_override THEN
        RAISE EXCEPTION
            'source % is protected; pass p_override=true to modify', p_source_id;
    END IF;

    IF p_correct THEN
        UPDATE source_credibility
           SET alpha = alpha + p_weight, updated_at = now()
         WHERE source_id = p_source_id AND context_id = p_context_id;
    ELSE
        UPDATE source_credibility
           SET beta  = beta  + p_weight, updated_at = now()
         WHERE source_id = p_source_id AND context_id = p_context_id;
    END IF;
END;
$$;


-- ── update_belief ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION update_belief(
    p_statement_id uuid,
    p_weight       double precision,
    p_supports     boolean
) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF p_supports THEN
        UPDATE statements
           SET belief_alpha = belief_alpha + p_weight, updated_at = now()
         WHERE id = p_statement_id;
    ELSE
        UPDATE statements
           SET belief_beta  = belief_beta  + p_weight, updated_at = now()
         WHERE id = p_statement_id;
    END IF;
END;
$$;


-- ── holds_at ──────────────────────────────────────────────────
-- Returns statements for a predicate+args combination that hold at
-- a given time, in a given context, under a given reasoning mode.
--
-- p_mode options:
--   'open_world'        — returns only statements with positive
--                         evidential support (belief_mean > 0.5
--                         by default). No default-true assumption.
--                         Absence of evidence is not evidence of absence.
--   'default_true'      — original v0.4 behaviour. 'default' t_kind
--                         statements are treated as true until a
--                         direct_negation conflict exists.
--   'evidence_weighted' — returns all matching statements regardless
--                         of belief_mean, ordered by belief_mean DESC.
--                         Intended for the reasoning layer to aggregate.
--
-- Default mode: 'open_world' (consistent with Bayesian/open-world intent).
--
-- Note on negation (v0.5): the negated boolean has been removed.
-- The open_world and default_true branches now check for
-- direct_negation conflicts instead of s.negated = true.
CREATE OR REPLACE FUNCTION holds_at(
    p_predicate_id uuid,
    p_object_args  uuid[],
    p_time         timestamptz,
    p_context_id   uuid    DEFAULT NULL,
    p_mode         text    DEFAULT 'open_world'
) RETURNS TABLE (
    statement_id    uuid,
    belief_mean_val double precision,
    evidence_str    double precision,
    interp          statement_interpretation
) LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_context_id uuid;
BEGIN
    v_context_id := COALESCE(p_context_id, stable_uuid('reality', 'context'));

    IF p_mode = 'evidence_weighted' THEN
        -- Return all matching statements; let the caller aggregate.
        RETURN QUERY
        SELECT sub.statement_id, sub.belief_mean_val, sub.evidence_str, sub.interp
        FROM (
            SELECT s.id, s.belief_mean,
                   s.belief_alpha + s.belief_beta,
                   s.interpretation
            FROM statements s
            WHERE s.predicate_id = p_predicate_id
              AND s.object_args  = p_object_args
              AND s.context_id   = v_context_id
              AND s.t_kind IN ('eternal', 'always')

            UNION ALL

            SELECT s.id, s.belief_mean,
                   s.belief_alpha + s.belief_beta,
                   s.interpretation
            FROM statements s
            WHERE s.predicate_id = p_predicate_id
              AND s.object_args  = p_object_args
              AND s.context_id   = v_context_id
              AND s.t_kind IN ('interval', 'point')
              AND tstzrange(
                      coalesce(s.t_start_ts, '-infinity'::timestamptz),
                      coalesce(s.t_end_ts,   'infinity'::timestamptz),
                      '[)'
                  ) @> p_time

            UNION ALL

            SELECT s.id, s.belief_mean,
                   s.belief_alpha + s.belief_beta,
                   s.interpretation
            FROM statements s
            WHERE s.predicate_id = p_predicate_id
              AND s.object_args  = p_object_args
              AND s.context_id   = v_context_id
              AND s.t_kind       = 'default'
        ) sub(statement_id, belief_mean_val, evidence_str, interp)
        ORDER BY belief_mean_val DESC;

    ELSIF p_mode = 'default_true' THEN
        -- Original v0.4 semantics: default statements are true until
        -- a direct_negation conflict is registered against them.
        RETURN QUERY
        SELECT sub.statement_id, sub.belief_mean_val, sub.evidence_str, sub.interp
        FROM (
            SELECT s.id, s.belief_mean,
                   s.belief_alpha + s.belief_beta,
                   s.interpretation
            FROM statements s
            WHERE s.predicate_id = p_predicate_id
              AND s.object_args  = p_object_args
              AND s.context_id   = v_context_id
              AND s.t_kind IN ('eternal', 'always')

            UNION ALL

            SELECT s.id, s.belief_mean,
                   s.belief_alpha + s.belief_beta,
                   s.interpretation
            FROM statements s
            WHERE s.predicate_id = p_predicate_id
              AND s.object_args  = p_object_args
              AND s.context_id   = v_context_id
              AND s.t_kind       = 'default'
              AND s.t_end_ts     IS NULL
              AND NOT EXISTS (
                  SELECT 1 FROM conflicts c
                  WHERE c.conflict_kind = 'direct_negation'
                    AND (c.statement_a = s.id OR c.statement_b = s.id)
                    AND c.resolved = false
              )

            UNION ALL

            SELECT s.id, s.belief_mean,
                   s.belief_alpha + s.belief_beta,
                   s.interpretation
            FROM statements s
            WHERE s.predicate_id = p_predicate_id
              AND s.object_args  = p_object_args
              AND s.context_id   = v_context_id
              AND s.t_kind IN ('interval', 'point')
              AND tstzrange(
                      coalesce(s.t_start_ts, '-infinity'::timestamptz),
                      coalesce(s.t_end_ts,   'infinity'::timestamptz),
                      '[)'
                  ) @> p_time
        ) sub(statement_id, belief_mean_val, evidence_str, interp)
        ORDER BY belief_mean_val DESC;

    ELSE
        -- Default: 'open_world'
        -- Returns only statements with belief_mean > 0.5.
        -- Absence of a statement means unknown, not false.
        RETURN QUERY
        SELECT sub.statement_id, sub.belief_mean_val, sub.evidence_str, sub.interp
        FROM (
            SELECT s.id, s.belief_mean,
                   s.belief_alpha + s.belief_beta,
                   s.interpretation
            FROM statements s
            WHERE s.predicate_id = p_predicate_id
              AND s.object_args  = p_object_args
              AND s.context_id   = v_context_id
              AND s.belief_mean  > 0.5
              AND s.t_kind IN ('eternal', 'always')

            UNION ALL

            SELECT s.id, s.belief_mean,
                   s.belief_alpha + s.belief_beta,
                   s.interpretation
            FROM statements s
            WHERE s.predicate_id = p_predicate_id
              AND s.object_args  = p_object_args
              AND s.context_id   = v_context_id
              AND s.belief_mean  > 0.5
              AND s.t_kind IN ('interval', 'point')
              AND tstzrange(
                      coalesce(s.t_start_ts, '-infinity'::timestamptz),
                      coalesce(s.t_end_ts,   'infinity'::timestamptz),
                      '[)'
                  ) @> p_time

            UNION ALL

            SELECT s.id, s.belief_mean,
                   s.belief_alpha + s.belief_beta,
                   s.interpretation
            FROM statements s
            WHERE s.predicate_id = p_predicate_id
              AND s.object_args  = p_object_args
              AND s.context_id   = v_context_id
              AND s.belief_mean  > 0.5
              AND s.t_kind       = 'default'
        ) sub(statement_id, belief_mean_val, evidence_str, interp)
        ORDER BY belief_mean_val DESC;

    END IF;
END;
$$;


-- =============================================================
-- SEED DATA
-- =============================================================
-- Wrapped in a single transaction so DEFERRABLE INITIALLY DEFERRED
-- orphan-guard triggers fire at COMMIT (when all rows exist).

BEGIN;

-- ── Infrastructure objects ────────────────────────────────────
INSERT INTO objects (id, kind, canonical_name, display_name, description) VALUES

    -- Contexts
    (stable_uuid('reality', 'context'),
     'context', 'reality', 'Reality',
     'The default real-world context'),

    -- Sources
    (stable_uuid('user_parent', 'source'),
     'source', 'user_parent', 'User (parent)',
     'Primary user — highest trust, analogous to a parent'),

    (stable_uuid('wikidata', 'source'),
     'source', 'wikidata', 'Wikidata',
     'Wikidata knowledge graph'),

    (stable_uuid('llm_generated', 'source'),
     'source', 'llm_generated', 'LLM generated',
     'Fact proposed by language model; lower prior trust'),

    (stable_uuid('system_kernel', 'source'),
     'source', 'system_kernel', 'System kernel',
     'Axiomatic facts at KB initialisation. Near-certain (alpha=1000). '
     'is_protected=true: update_trust() requires explicit override. '
     'Kernel facts are correctable in principle but require deliberate '
     'human confirmation, not passive evidence drift.'),

    -- Boolean / unknown sentinels
    (stable_uuid('true',    'entity'), 'entity', 'true',    'True',    'The Boolean value true'),
    (stable_uuid('false',   'entity'), 'entity', 'false',   'False',   'The Boolean value false'),
    (stable_uuid('unknown', 'entity'), 'entity', 'unknown', 'Unknown', 'Unknown or anonymous entity');


-- ── Ontological backbone objects ──────────────────────────────
-- These are 'entity'-kinded objects that form the top of the type hierarchy.
-- Finer typing is expressed via type_membership and subtype_of statements,
-- not via the object.kind enum.
INSERT INTO objects (id, kind, canonical_name, display_name, description) VALUES

    -- Top-level ontological categories (Layer A: hard, minimal, mostly static)
    (stable_uuid('entity',    'entity'), 'entity', 'entity',    'Entity',
     'Top-level ontological category: everything that exists or is modeled'),
    (stable_uuid('concrete',  'entity'), 'entity', 'concrete',  'Concrete',
     'Entities with spatiotemporal existence'),
    (stable_uuid('abstract',  'entity'), 'entity', 'abstract',  'Abstract',
     'Entities without spatiotemporal existence: concepts, numbers, relations'),
    (stable_uuid('living',    'entity'), 'entity', 'living',    'Living',
     'Concrete entities that are or were alive'),
    (stable_uuid('animate',   'entity'), 'entity', 'animate',   'Animate',
     'Living entities capable of self-directed movement'),
    (stable_uuid('sapient',   'entity'), 'entity', 'sapient',   'Sapient',
     'Animate entities with higher cognition'),
    (stable_uuid('artifact',  'entity'), 'entity', 'artifact',  'Artifact',
     'Concrete entities created by agents'),
    (stable_uuid('process',   'entity'), 'entity', 'process',   'Process',
     'Events or processes: creation, destruction, transformation, etc.'),
    (stable_uuid('group',     'entity'), 'entity', 'group',     'Group',
     'Collections of entities. Not automatically an agent — see has_role.'),
    (stable_uuid('person',    'entity'), 'entity', 'person',    'Person',
     'A human individual (subtype of sapient)'),
    (stable_uuid('number',    'entity'), 'entity', 'number',    'Number',
     'Abstract numeric entity'),
    (stable_uuid('relation',  'entity'), 'entity', 'relation',  'Relation',
     'Abstract relational entity'),

    -- Functional roles (Layer B: soft, contextual, time-aware)
    -- "agent" is a role, not an ontological type.
    (stable_uuid('agent',       'entity'), 'entity', 'agent',       'Agent',
     'Functional role: entity that acts with intention in some context. '
     'Use has_role(X, agent, context) rather than typing X as agent.'),
    (stable_uuid('institution', 'entity'), 'entity', 'institution', 'Institution',
     'Functional role: organised group acting as a unit'),
    (stable_uuid('government',  'entity'), 'entity', 'government',  'Government',
     'Functional role: governing body of a polity');


-- ── Predicate objects and metadata ───────────────────────────
-- Predicates are inserted as objects (kind='predicate') and then
-- into the predicates table in the same transaction.

INSERT INTO objects (id, kind, canonical_name, display_name, description) VALUES

    -- Core ontological predicates
    (stable_uuid('subtype_of',   'predicate'), 'predicate', 'subtype_of',   'Subtype of',
     'T1 is a subtype of T2. Probabilistic subsumption.'),
    (stable_uuid('instance_of',  'predicate'), 'predicate', 'instance_of',  'Instance of',
     'X is an instance of type T.'),

    -- Functional role predicate (Layer B)
    (stable_uuid('has_role',     'predicate'), 'predicate', 'has_role',     'Has role',
     'Entity holds a functional role within a scope/context. '
     'e.g. has_role(openai, agent, domain_ai). '
     'Roles are not ontological types.'),

    -- Capacity predicate
    (stable_uuid('has_capacity', 'predicate'), 'predicate', 'has_capacity', 'Has capacity',
     'Entity possesses a capability. '
     'e.g. has_capacity(gpt4, language_generation). '
     'Distinct from roles: capacities are properties, roles are relational.'),

    -- Modeling abstraction predicate (Layer C)
    (stable_uuid('models_as',    'predicate'), 'predicate', 'models_as',    'Models as',
     'Subject is modeled as a type within a context, as a modeling '
     'convenience rather than an ontological commitment. '
     'e.g. models_as(openai, agent, domain_economics). '
     'Use interpretation=''modeling'' on such statements.');

INSERT INTO predicates
    (id, arity, arg_labels, nl_description, is_basis, domain_strictness, status)
VALUES
    (stable_uuid('subtype_of',   'predicate'), 2,
     ARRAY['subtype','supertype'],
     'First argument is a subtype of the second.',
     true, 'soft', 'confirmed'),

    (stable_uuid('instance_of',  'predicate'), 2,
     ARRAY['instance','type'],
     'First argument is an instance of the second.',
     true, 'soft', 'confirmed'),

    (stable_uuid('has_role',     'predicate'), 3,
     ARRAY['entity','role','scope'],
     'Entity holds the given functional role within the given scope.',
     false, 'none', 'confirmed'),

    (stable_uuid('has_capacity', 'predicate'), 2,
     ARRAY['entity','capacity'],
     'Entity possesses the given capability.',
     false, 'none', 'confirmed'),

    (stable_uuid('models_as',    'predicate'), 3,
     ARRAY['subject','type','context'],
     'Subject is modeled as a type within a context (non-ontological).',
     false, 'none', 'confirmed');


-- ── Context row ───────────────────────────────────────────────
INSERT INTO contexts (id, kind, parent_id) VALUES
    (stable_uuid('reality', 'context'), 'reality', NULL);


-- ── Source credibility ────────────────────────────────────────
INSERT INTO source_credibility (source_id, context_id, alpha, beta, is_protected) VALUES
    (stable_uuid('user_parent',   'source'),
     stable_uuid('reality',       'context'),   19.0,    1.0,   false),

    (stable_uuid('wikidata',      'source'),
     stable_uuid('reality',       'context'),   13.0,    2.0,   false),

    (stable_uuid('llm_generated', 'source'),
     stable_uuid('reality',       'context'),    3.0,    2.0,   false),

    -- system_kernel: ~99.9% credibility prior; protected from passive drift.
    -- alpha=999, beta=1 → mean = 0.999. Requires p_override=true to update.
    (stable_uuid('system_kernel', 'source'),
     stable_uuid('reality',       'context'),  999.0,    1.0,   true);


-- ── Ontological backbone statements ───────────────────────────
-- Seed the type hierarchy via subtype_of statements.
-- All sourced from system_kernel; axiomatic derivation; eternal.
-- High alpha/beta (kernel-level confidence).

-- person ⊂ sapient ⊂ animate ⊂ living ⊂ concrete ⊂ entity
-- artifact ⊂ concrete ⊂ entity
-- abstract ⊂ entity
-- process ⊂ entity
-- group ⊂ entity
-- number ⊂ abstract; relation ⊂ abstract

INSERT INTO statements
    (id, predicate_id, object_args, belief_alpha, belief_beta,
     interpretation, t_kind, context_id, derivation_type, derivation_depth)
VALUES
    (gen_random_uuid(), stable_uuid('subtype_of','predicate'),
     ARRAY[stable_uuid('concrete','entity'),  stable_uuid('entity','entity')],
     999,1,'ontological','eternal',stable_uuid('reality','context'),'axiomatic',0),

    (gen_random_uuid(), stable_uuid('subtype_of','predicate'),
     ARRAY[stable_uuid('abstract','entity'),  stable_uuid('entity','entity')],
     999,1,'ontological','eternal',stable_uuid('reality','context'),'axiomatic',0),

    (gen_random_uuid(), stable_uuid('subtype_of','predicate'),
     ARRAY[stable_uuid('living','entity'),    stable_uuid('concrete','entity')],
     999,1,'ontological','eternal',stable_uuid('reality','context'),'axiomatic',0),

    (gen_random_uuid(), stable_uuid('subtype_of','predicate'),
     ARRAY[stable_uuid('animate','entity'),   stable_uuid('living','entity')],
     999,1,'ontological','eternal',stable_uuid('reality','context'),'axiomatic',0),

    (gen_random_uuid(), stable_uuid('subtype_of','predicate'),
     ARRAY[stable_uuid('sapient','entity'),   stable_uuid('animate','entity')],
     999,1,'ontological','eternal',stable_uuid('reality','context'),'axiomatic',0),

    (gen_random_uuid(), stable_uuid('subtype_of','predicate'),
     ARRAY[stable_uuid('person','entity'),    stable_uuid('sapient','entity')],
     999,1,'ontological','eternal',stable_uuid('reality','context'),'axiomatic',0),

    (gen_random_uuid(), stable_uuid('subtype_of','predicate'),
     ARRAY[stable_uuid('artifact','entity'),  stable_uuid('concrete','entity')],
     999,1,'ontological','eternal',stable_uuid('reality','context'),'axiomatic',0),

    (gen_random_uuid(), stable_uuid('subtype_of','predicate'),
     ARRAY[stable_uuid('process','entity'),   stable_uuid('entity','entity')],
     999,1,'ontological','eternal',stable_uuid('reality','context'),'axiomatic',0),

    (gen_random_uuid(), stable_uuid('subtype_of','predicate'),
     ARRAY[stable_uuid('group','entity'),     stable_uuid('entity','entity')],
     999,1,'ontological','eternal',stable_uuid('reality','context'),'axiomatic',0),

    (gen_random_uuid(), stable_uuid('subtype_of','predicate'),
     ARRAY[stable_uuid('number','entity'),    stable_uuid('abstract','entity')],
     999,1,'ontological','eternal',stable_uuid('reality','context'),'axiomatic',0),

    (gen_random_uuid(), stable_uuid('subtype_of','predicate'),
     ARRAY[stable_uuid('relation','entity'),  stable_uuid('abstract','entity')],
     999,1,'ontological','eternal',stable_uuid('reality','context'),'axiomatic',0);

COMMIT;

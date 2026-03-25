-- =============================================================
-- Common Knowledge KB — PostgreSQL Schema  (v0.3)
-- =============================================================
-- Changes from v0.3:
--   • holds_at() converted to LANGUAGE plpgsql; DEFAULT for
--     p_context_id changed from stable_uuid('reality','context')
--     to NULL, resolved via COALESCE inside the body.
--     Reason: PostgreSQL's type resolver rejects function-call
--     DEFAULTs in LANGUAGE sql signatures when the called function
--     isn't yet known at parse time, and is strict about
--     unknown→text coercion in that context regardless of ::text
--     casts.  plpgsql evaluates the body at call time, sidestepping
--     the issue entirely.
--   • holds_at() ORDER BY belief_mean_val: UNION ALL wrapped in a
--     subquery so the alias is in scope for the ORDER BY clause.
--   • Seed data wrapped in BEGIN/COMMIT so the DEFERRABLE INITIALLY
--     DEFERRED orphan-guard trigger fires at end-of-transaction
--     (after both objects and contexts rows exist), not per-statement.
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

CREATE TYPE object_kind AS ENUM (
    'person',
    'institution',
    'concept',
    'predicate',
    'context',
    'source',
    'event',
    'quantity'
);

CREATE TYPE temporal_kind AS ENUM (
    'eternal',
    'always',
    'interval',
    'point',
    'default'
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
    'direct_negation',
    'mutual_exclusion',
    'type_violation',
    'temporal_overlap',
    'value_conflict'
);

-- ── Composite type: fuzzy timestamp ──────────────────────────
CREATE TYPE fuzzy_time AS (
    best        double precision,
    lo          double precision,
    hi          double precision,
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

-- ═════════════════════════════════════════════════════════════
-- CORE TABLES
-- ═════════════════════════════════════════════════════════════

-- ── Objects ───────────────────────────────────────────────────
CREATE TABLE objects (
    id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    kind            object_kind NOT NULL,
    canonical_name  text        NOT NULL,
    display_name    text,
    aliases         text[]      NOT NULL DEFAULT '{}',
    description     text,
    embedding       vector(768),
    basis_weights   jsonb,
    external_ids    jsonb,
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
    id               uuid             PRIMARY KEY
                         REFERENCES objects (id) ON DELETE CASCADE,
    arity            int              NOT NULL CHECK (arity BETWEEN 1 AND 8),
    arg_kinds        object_kind[],
    arg_labels       text[],
    arg_types        text[],
    fol_definition   text,
    nl_description   text,
    source_predicate text,
    is_basis         boolean          NOT NULL DEFAULT false,
    domains          text[]           NOT NULL DEFAULT '{}',
    status           predicate_status NOT NULL DEFAULT 'proposed',
    introduced_by    uuid             REFERENCES objects (id),
    introduced_at    timestamptz      NOT NULL DEFAULT now()
);

CREATE INDEX idx_predicates_basis   ON predicates (is_basis) WHERE is_basis;
CREATE INDEX idx_predicates_domains ON predicates USING GIN (domains);
CREATE INDEX idx_predicates_status  ON predicates (status);

-- ── Context metadata ──────────────────────────────────────────
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
CREATE TABLE statements (
    id              uuid             PRIMARY KEY DEFAULT gen_random_uuid(),
    predicate_id    uuid             NOT NULL REFERENCES objects (id),
    object_args     uuid[]           NOT NULL DEFAULT '{}',
    literal_args    jsonb            NOT NULL DEFAULT '[]'
                        CHECK (jsonb_typeof(literal_args) = 'array'),
    belief_alpha    double precision NOT NULL DEFAULT 1.0
                        CHECK (belief_alpha > 0),
    belief_beta     double precision NOT NULL DEFAULT 1.0
                        CHECK (belief_beta  > 0),
    negated         boolean          NOT NULL DEFAULT false,
    t_kind          temporal_kind    NOT NULL DEFAULT 'default',
    t_start         fuzzy_time,
    t_end           fuzzy_time,
    t_start_ts      timestamptz      GENERATED ALWAYS AS (
                        jd_to_tstz((t_start).best)
                    ) STORED,
    t_end_ts        timestamptz      GENERATED ALWAYS AS (
                        jd_to_tstz((t_end).best)
                    ) STORED,
    context_id      uuid             NOT NULL REFERENCES objects (id),
    derivation_type  derivation_type NOT NULL DEFAULT 'user_asserted',
    derivation_depth int             NOT NULL DEFAULT 0
                        CHECK (derivation_depth >= 0),
    derived_from    uuid[]           NOT NULL DEFAULT '{}',
    created_at      timestamptz      NOT NULL DEFAULT now(),
    updated_at      timestamptz      NOT NULL DEFAULT now(),
    CONSTRAINT args_nonempty CHECK (
        cardinality(object_args) >= 1
        OR jsonb_array_length(literal_args) >= 1
    )
);

CREATE INDEX idx_stmt_predicate    ON statements (predicate_id);
CREATE INDEX idx_stmt_context      ON statements (context_id);
CREATE INDEX idx_stmt_t_kind       ON statements (t_kind);
CREATE INDEX idx_stmt_deriv_type   ON statements (derivation_type);
CREATE INDEX idx_stmt_object_args  ON statements USING GIN (object_args);
CREATE INDEX idx_stmt_derived_from ON statements USING GIN (derived_from);

CREATE INDEX idx_stmt_negated ON statements (predicate_id, object_args)
    WHERE negated = true;

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

-- ── Statement arg validation trigger ─────────────────────────
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
            v_arity,
            cardinality(NEW.object_args),
            jsonb_array_length(NEW.literal_args);
    END IF;

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

-- ═════════════════════════════════════════════════════════════
-- VIEWS
-- ═════════════════════════════════════════════════════════════

CREATE VIEW statement_belief AS
SELECT
    id,
    belief_alpha,
    belief_beta,
    belief_alpha / (belief_alpha + belief_beta)             AS mean,
    belief_alpha + belief_beta                               AS evidence_strength,
    (belief_alpha * belief_beta)
        / (pow(belief_alpha + belief_beta, 2)
           * (belief_alpha + belief_beta + 1))               AS variance,
    GREATEST(0,
        belief_alpha / (belief_alpha + belief_beta)
        - 1.96 * sqrt(
            (belief_alpha * belief_beta)
            / (pow(belief_alpha + belief_beta, 2)
               * (belief_alpha + belief_beta + 1))
        )
    )                                                        AS ci_low,
    LEAST(1,
        belief_alpha / (belief_alpha + belief_beta)
        + 1.96 * sqrt(
            (belief_alpha * belief_beta)
            / (pow(belief_alpha + belief_beta, 2)
               * (belief_alpha + belief_beta + 1))
        )
    )                                                        AS ci_high,
    negated,
    t_kind,
    context_id,
    derivation_type,
    derivation_depth
FROM statements;

CREATE VIEW statement_view AS
SELECT
    s.id,
    p.canonical_name                                          AS predicate,
    s.object_args,
    arg_names.names                                           AS arg_names,
    s.literal_args,
    s.belief_alpha / (s.belief_alpha + s.belief_beta)         AS belief_mean,
    s.belief_alpha + s.belief_beta                             AS evidence_strength,
    s.negated,
    s.t_kind,
    s.t_start,
    s.t_end,
    c.canonical_name                                          AS context,
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

-- ── Attestations ─────────────────────────────────────────────
CREATE TABLE attestations (
    id                 uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    statement_id       uuid        NOT NULL REFERENCES statements (id) ON DELETE CASCADE,
    source_id          uuid        NOT NULL REFERENCES objects (id),
    evidence_group_id  uuid,
    confidence_weight  double precision NOT NULL DEFAULT 1.0
                           CHECK (confidence_weight BETWEEN 0.0 AND 1.0),
    raw_claim          text,
    url                text,
    accessed_at        timestamptz,
    created_at         timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_attest_statement      ON attestations (statement_id);
CREATE INDEX idx_attest_source         ON attestations (source_id);
CREATE INDEX idx_attest_evidence_group ON attestations (evidence_group_id)
    WHERE evidence_group_id IS NOT NULL;

-- ── Source credibility ───────────────────────────────────────
CREATE TABLE source_credibility (
    source_id   uuid             NOT NULL REFERENCES objects (id),
    context_id  uuid             NOT NULL REFERENCES objects (id),
    alpha       double precision NOT NULL DEFAULT 1.0 CHECK (alpha > 0),
    beta        double precision NOT NULL DEFAULT 1.0 CHECK (beta  > 0),
    updated_at  timestamptz      NOT NULL DEFAULT now(),
    PRIMARY KEY (source_id, context_id)
);

CREATE VIEW source_credibility_score AS
SELECT
    source_id,
    context_id,
    alpha / (alpha + beta)                          AS mean,
    alpha + beta                                     AS evidence_strength,
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
          )                                         AS weighted_credibility,
    sum(coalesce(sc_domain.evidence_strength,
                 sc_reality.evidence_strength, 2.0)
        * a.confidence_weight)                      AS total_source_weight,
    count(a.id)                                     AS source_count
FROM attestations a
JOIN statements s ON s.id = a.statement_id
LEFT JOIN source_credibility_score sc_domain
       ON sc_domain.source_id  = a.source_id
      AND sc_domain.context_id = s.context_id
LEFT JOIN source_credibility_score sc_reality
       ON sc_reality.source_id  = a.source_id
      AND sc_reality.context_id = stable_uuid('reality:context')
GROUP BY a.statement_id;

-- ── Predicate subsumption ────────────────────────────────────
CREATE TABLE predicate_subsumption (
    child_id    uuid             NOT NULL REFERENCES objects (id),
    parent_id   uuid             NOT NULL REFERENCES objects (id),
    alpha       double precision NOT NULL DEFAULT 1.0 CHECK (alpha > 0),
    beta        double precision NOT NULL DEFAULT 1.0 CHECK (beta  > 0),
    context_id  uuid             REFERENCES objects (id),
    PRIMARY KEY (child_id, parent_id)
);

-- ── Type membership ──────────────────────────────────────────
CREATE TABLE type_membership (
    object_id   uuid             NOT NULL REFERENCES objects (id),
    type_id     uuid             NOT NULL REFERENCES objects (id),
    alpha       double precision NOT NULL DEFAULT 1.0 CHECK (alpha > 0),
    beta        double precision NOT NULL DEFAULT 1.0 CHECK (beta  > 0),
    context_id  uuid             REFERENCES objects (id),
    PRIMARY KEY (object_id, type_id)
);

-- ── Conflicts ────────────────────────────────────────────────
CREATE TABLE conflicts (
    id              uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
    statement_a     uuid          NOT NULL REFERENCES statements (id),
    statement_b     uuid          NOT NULL REFERENCES statements (id),
    conflict_kind   conflict_kind,
    resolved        boolean       NOT NULL DEFAULT false,
    resolution_note text,
    created_at      timestamptz   NOT NULL DEFAULT now()
);

-- ═════════════════════════════════════════════════════════════
-- FUNCTIONS
-- ═════════════════════════════════════════════════════════════

-- ── update_trust ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION update_trust(
    p_source_id  uuid,
    p_context_id uuid,
    p_correct    boolean,
    p_weight     double precision DEFAULT 1.0
) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO source_credibility (source_id, context_id, alpha, beta)
    VALUES (p_source_id, p_context_id, 1.0, 1.0)
    ON CONFLICT (source_id, context_id) DO NOTHING;

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

-- ── belief_mean ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION belief_mean(p_statement_id uuid)
RETURNS double precision LANGUAGE sql STABLE AS $$
    SELECT belief_alpha / (belief_alpha + belief_beta)
      FROM statements WHERE id = p_statement_id;
$$;

-- ── holds_at ──────────────────────────────────────────────────
-- FIX (v0.4): Two changes from v0.3:
--
--   1. Converted to LANGUAGE plpgsql with p_context_id DEFAULT NULL,
--      resolved to the reality context via COALESCE inside the body.
--      Reason: PostgreSQL cannot resolve function-call DEFAULT
--      expressions in LANGUAGE sql signatures when the called function
--      involves string-literal arguments — the type resolver treats
--      bare literals as type `unknown` in that context and fails to
--      match the `text` overload, even with explicit ::text casts.
--      plpgsql evaluates the body at call time, so the COALESCE
--      executes after stable_uuid is fully resolved at runtime.
--
--   2. ORDER BY wraps the UNION ALL in a subquery so the alias
--      belief_mean_val is in scope.
CREATE OR REPLACE FUNCTION holds_at(
    p_predicate_id uuid,
    p_object_args  uuid[],
    p_time         timestamptz,
    p_context_id   uuid DEFAULT NULL   -- NULL → resolved to reality context below
) RETURNS TABLE (
    statement_id    uuid,
    belief_mean_val double precision,
    evidence_str    double precision
) LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_context_id uuid;
BEGIN
    -- Resolve default context at runtime — avoids the LANGUAGE sql
    -- DEFAULT-expression type-resolution bug with stable_uuid().
    v_context_id := COALESCE(p_context_id, stable_uuid('reality', 'context'));

    RETURN QUERY
    SELECT statement_id, belief_mean_val, evidence_str
    FROM (
        -- Branch 1a: eternal, always
        SELECT
            s.id                                              AS statement_id,
            s.belief_alpha / (s.belief_alpha + s.belief_beta) AS belief_mean_val,
            s.belief_alpha + s.belief_beta                     AS evidence_str
        FROM statements s
        WHERE s.predicate_id = p_predicate_id
          AND s.object_args  = p_object_args
          AND s.context_id   = v_context_id
          AND s.negated      = false
          AND s.t_kind IN ('eternal', 'always')

        UNION ALL

        -- Branch 1b: default — true until explicitly contradicted
        SELECT
            s.id,
            s.belief_alpha / (s.belief_alpha + s.belief_beta),
            s.belief_alpha + s.belief_beta
        FROM statements s
        WHERE s.predicate_id = p_predicate_id
          AND s.object_args  = p_object_args
          AND s.context_id   = v_context_id
          AND s.negated      = false
          AND s.t_kind       = 'default'
          AND s.t_end_ts     IS NULL
          AND NOT EXISTS (
              SELECT 1 FROM statements s2
              WHERE s2.predicate_id = s.predicate_id
                AND s2.object_args  = s.object_args
                AND s2.context_id   = v_context_id
                AND s2.negated      = true
          )

        UNION ALL

        -- Branch 2: interval / point — uses GiST index
        SELECT
            s.id,
            s.belief_alpha / (s.belief_alpha + s.belief_beta),
            s.belief_alpha + s.belief_beta
        FROM statements s
        WHERE s.predicate_id = p_predicate_id
          AND s.object_args  = p_object_args
          AND s.context_id   = v_context_id
          AND s.negated      = false
          AND s.t_kind IN ('interval', 'point')
          AND tstzrange(
                  coalesce(s.t_start_ts, '-infinity'::timestamptz),
                  coalesce(s.t_end_ts,   'infinity'::timestamptz),
                  '[)'
              ) @> p_time
    ) sub
    ORDER BY belief_mean_val DESC;
END;
$$;

-- ═════════════════════════════════════════════════════════════
-- SEED DATA
-- ═════════════════════════════════════════════════════════════
-- FIX (v0.4): wrapped in BEGIN/COMMIT so the DEFERRABLE INITIALLY
-- DEFERRED orphan-guard trigger fires at end-of-transaction (when
-- both the objects and contexts rows are present), not per-statement.
-- Without an explicit transaction, psql auto-commits each statement
-- individually and the deferred trigger becomes effectively immediate.

BEGIN;

INSERT INTO objects (id, kind, canonical_name, display_name, description) VALUES
    (stable_uuid('reality',       'context'),
     'context', 'reality',       'Reality',
     'The default real-world context'),

    (stable_uuid('user_parent',   'source'),
     'source',  'user_parent',   'User (parent)',
     'Primary user — highest trust, analogous to a parent'),

    (stable_uuid('wikidata',      'source'),
     'source',  'wikidata',      'Wikidata',
     'Wikidata knowledge graph'),

    (stable_uuid('llm_generated', 'source'),
     'source',  'llm_generated', 'LLM generated',
     'Fact proposed by language model; lower prior trust'),

    (stable_uuid('system_kernel', 'source'),
     'source',  'system_kernel', 'System kernel',
     'Axiomatic facts at KB initialisation; treated as near-certain.
      alpha=1000 means ~1000 high-credibility contradictions would be
      needed to meaningfully shift the belief mean.  This is intentional:
      kernel axioms and the empirical KB operate in different epistemic
      regimes.  Do not attempt to correct kernel statements via normal
      evidence accumulation.'),

    (stable_uuid('true',          'concept'),
     'concept', 'true',          'True',   'The Boolean value true'),

    (stable_uuid('false',         'concept'),
     'concept', 'false',         'False',  'The Boolean value false'),

    (stable_uuid('unknown',       'concept'),
     'concept', 'unknown',       'Unknown',
     'Placeholder for unknown or anonymous entities');

-- contexts row inserted in the same transaction — deferred guard
-- will find it when it fires at COMMIT.
INSERT INTO contexts (id, kind, parent_id) VALUES
    (stable_uuid('reality', 'context'), 'reality', NULL);

INSERT INTO source_credibility (source_id, context_id, alpha, beta) VALUES
    (stable_uuid('user_parent',   'source'),
     stable_uuid('reality',       'context'),   19.0,    1.0),

    (stable_uuid('wikidata',      'source'),
     stable_uuid('reality',       'context'),   13.0,    2.0),

    (stable_uuid('llm_generated', 'source'),
     stable_uuid('reality',       'context'),    3.0,    2.0),

    (stable_uuid('system_kernel', 'source'),
     stable_uuid('reality',       'context'), 1000.0,    0.001);

COMMIT;

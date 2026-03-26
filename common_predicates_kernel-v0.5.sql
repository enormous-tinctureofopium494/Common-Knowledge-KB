-- =============================================================
-- Common Knowledge KB — Basis Predicates (v0.5)
-- =============================================================
-- Compatibility notes vs. the v3 predicate file:
--
--   • object_kind enum is now coarse (entity/predicate/context/source).
--     arg_kinds object_kind[] has been DROPPED from predicates in v0.5
--     and is not inserted here.  Argument type constraints are expressed
--     via arg_type_ids uuid[] (references to type objects in the
--     ontological backbone), or left NULL for unconstrained args.
--
--   • arg_types text[] (old) → arg_type_ids uuid[] (v0.5).
--     Where a type object exists in the backbone seed (entity, concrete,
--     abstract, process, person, group, …), we reference it via
--     stable_uuid(name,'entity').  Where no backbone object exists yet
--     (e.g. 'language', 'material', 'symbol'), arg_type_ids is left NULL
--     for now and can be tightened in later migrations.
--
--   • domains text[] was dropped from predicates in v0.5.
--     Domain information is preserved in nl_description and
--     fol_definition comments; it can be re-introduced as a
--     jsonb tag on the object row if needed later.
--
--   • domain_strictness: all basis predicates default to 'soft'
--     unless a hard logical constraint is warranted (disjoint_with,
--     equivalent_to use 'soft'; none for unconstrained predicates).
--
--   • The five predicates already seeded by ckb_schema_v0.5.sql
--     (subtype_of, instance_of, has_role, has_capacity, models_as)
--     are re-inserted here with ON CONFLICT DO NOTHING / DO UPDATE
--     to fill in the richer metadata (arg_type_ids, fol_definition,
--     nl_description, is_basis=true, source_predicate).
--     NOTE: the schema seeds 'instance_of'; the basis predicate set
--     calls the same concept 'is_a'.  They are merged here under 'is_a';
--     the schema-seeded 'instance_of' object is left in place as an
--     alias (see object_equivalence insert at the end).
--
--   • 57 basis predicates across 13 groups (unchanged from v3).
--     held_office still absent; has_role covers it.
--     born_in / died_in still absent; use located_in + temporal scope.
--
-- =============================================================

BEGIN;

DO $$
DECLARE
    sys  uuid := stable_uuid('system_kernel', 'source');
    ctx  uuid := stable_uuid('reality',       'context');
    oid  uuid;

    -- Backbone type UUIDs (seeded by ckb_schema_v0.5.sql)
    t_entity    uuid := stable_uuid('entity',   'entity');
    t_abstract  uuid := stable_uuid('abstract', 'entity');
    t_concrete  uuid := stable_uuid('concrete', 'entity');
    t_animate   uuid := stable_uuid('animate',  'entity');
    t_sapient   uuid := stable_uuid('sapient',  'entity');
    t_person    uuid := stable_uuid('person',   'entity');
    t_process   uuid := stable_uuid('process',  'entity');
    t_group     uuid := stable_uuid('group',    'entity');
    t_number    uuid := stable_uuid('number',   'entity');
    t_relation  uuid := stable_uuid('relation', 'entity');

BEGIN

-- ════════════════════════════════════════════════════════════
-- GROUP 1: TAXONOMIC / TYPE  (5)
-- ════════════════════════════════════════════════════════════

-- is_a(instance, type)
-- The schema seeded 'instance_of' for this concept.  We insert 'is_a'
-- as the canonical basis predicate and record an equivalence below.
oid := stable_uuid('is_a', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'is_a', 'is a',
    'x is an instance of type y (crisp classification only). '
    'Do NOT use for role, state, property, typicality, or identity. '
    'See: has_role (role), has_property (predication), '
    'typical_of (exemplification), same_as (identity).')
ON CONFLICT (canonical_name, kind) DO NOTHING;

INSERT INTO predicates
    (id, arity, arg_type_ids, arg_labels,
     fol_definition, nl_description, source_predicate,
     is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2,
    ARRAY[t_entity, t_abstract],          -- instance:entity, type:abstract-or-entity
    ARRAY['instance', 'type'],
    'primitive',
    'x is an instance of y',
    'rdf:type / wikidata:P31',
    true, 'soft', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET
    arg_type_ids    = EXCLUDED.arg_type_ids,
    arg_labels      = EXCLUDED.arg_labels,
    fol_definition  = EXCLUDED.fol_definition,
    nl_description  = EXCLUDED.nl_description,
    source_predicate= EXCLUDED.source_predicate,
    is_basis        = true,
    status          = 'confirmed',
    introduced_by   = EXCLUDED.introduced_by;

-- subtype_of(subtype, supertype) — already seeded by schema; enrich metadata.
oid := stable_uuid('subtype_of', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'subtype_of', 'subtype of',
    'Every instance of x is also an instance of y (transitive, asymmetric).')
ON CONFLICT (canonical_name, kind) DO NOTHING;

INSERT INTO predicates
    (id, arity, arg_type_ids, arg_labels,
     fol_definition, nl_description, source_predicate,
     is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2,
    ARRAY[t_abstract, t_abstract],
    ARRAY['subtype', 'supertype'],
    'subtype_of(X,Y) :- forall Z, is_a(Z,X) -> is_a(Z,Y)',
    'x is a subtype of y',
    'rdfs:subClassOf',
    true, 'soft', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET
    arg_type_ids    = EXCLUDED.arg_type_ids,
    arg_labels      = EXCLUDED.arg_labels,
    fol_definition  = EXCLUDED.fol_definition,
    nl_description  = EXCLUDED.nl_description,
    source_predicate= EXCLUDED.source_predicate,
    is_basis        = true,
    status          = 'confirmed',
    introduced_by   = EXCLUDED.introduced_by;

-- has_property(entity, property)
oid := stable_uuid('has_property', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'has_property', 'has property',
    'x has property or attribute y (predication sense of copula). '
    '"The sky is blue" → has_property(sky, blue).')
ON CONFLICT (canonical_name, kind) DO NOTHING;

INSERT INTO predicates
    (id, arity, arg_type_ids, arg_labels,
     fol_definition, nl_description, source_predicate,
     is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2,
    ARRAY[t_entity, t_entity],
    ARRAY['entity', 'property'],
    'primitive',
    'x has property y',
    'conceptnet:HasProperty',
    true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET
    arg_type_ids    = EXCLUDED.arg_type_ids,
    arg_labels      = EXCLUDED.arg_labels,
    fol_definition  = EXCLUDED.fol_definition,
    nl_description  = EXCLUDED.nl_description,
    source_predicate= EXCLUDED.source_predicate,
    is_basis        = true,
    status          = 'confirmed';

-- same_as(x, y) — identity
oid := stable_uuid('same_as', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'same_as', 'same as',
    'x and y refer to the same real-world entity (identity, not classification).')
ON CONFLICT (canonical_name, kind) DO NOTHING;

INSERT INTO predicates
    (id, arity, arg_type_ids, arg_labels,
     fol_definition, nl_description, source_predicate,
     is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2,
    ARRAY[t_entity, t_entity],
    ARRAY['entity_a', 'entity_b'],
    'primitive; symmetric; same_as(X,Y) -> same_as(Y,X)',
    'x and y are the same entity',
    'owl:sameAs',
    true, 'soft', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET
    arg_type_ids    = EXCLUDED.arg_type_ids,
    arg_labels      = EXCLUDED.arg_labels,
    fol_definition  = EXCLUDED.fol_definition,
    nl_description  = EXCLUDED.nl_description,
    source_predicate= EXCLUDED.source_predicate,
    is_basis        = true,
    status          = 'confirmed';

-- different_from(x, y)
oid := stable_uuid('different_from', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'different_from', 'different from',
    'x and y are distinct entities.')
ON CONFLICT (canonical_name, kind) DO NOTHING;

INSERT INTO predicates
    (id, arity, arg_type_ids, arg_labels,
     fol_definition, nl_description, source_predicate,
     is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2,
    ARRAY[t_entity, t_entity],
    ARRAY['entity_a', 'entity_b'],
    'different_from(X,Y) :- not same_as(X,Y)',
    'x and y are not the same entity',
    'owl:differentFrom',
    true, 'soft', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET
    arg_type_ids    = EXCLUDED.arg_type_ids,
    arg_labels      = EXCLUDED.arg_labels,
    fol_definition  = EXCLUDED.fol_definition,
    nl_description  = EXCLUDED.nl_description,
    source_predicate= EXCLUDED.source_predicate,
    is_basis        = true,
    status          = 'confirmed';


-- ════════════════════════════════════════════════════════════
-- GROUP 2: MEREOLOGY  (4)
-- ════════════════════════════════════════════════════════════

oid := stable_uuid('part_of', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'part_of', 'part of',
    'x is a component or part of y (transitive, asymmetric).')
ON CONFLICT (canonical_name, kind) DO NOTHING;

INSERT INTO predicates
    (id, arity, arg_type_ids, arg_labels,
     fol_definition, nl_description, source_predicate,
     is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2,
    ARRAY[t_entity, t_entity],
    ARRAY['part', 'whole'],
    'primitive; transitive; asymmetric',
    'x is a part of y',
    'conceptnet:PartOf / wikidata:P361',
    true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET
    arg_type_ids = EXCLUDED.arg_type_ids,
    arg_labels   = EXCLUDED.arg_labels,
    fol_definition = EXCLUDED.fol_definition,
    nl_description = EXCLUDED.nl_description,
    source_predicate = EXCLUDED.source_predicate,
    is_basis = true, status = 'confirmed';

oid := stable_uuid('has_part', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'has_part', 'has part',
    'x contains y as a component.')
ON CONFLICT (canonical_name, kind) DO NOTHING;

INSERT INTO predicates
    (id, arity, arg_type_ids, arg_labels,
     fol_definition, nl_description, source_predicate,
     is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2,
    ARRAY[t_entity, t_entity],
    ARRAY['whole', 'part'],
    'has_part(X,Y) :- part_of(Y,X)',
    'x has y as a part',
    'conceptnet:HasA / wikidata:P527',
    true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET
    arg_type_ids = EXCLUDED.arg_type_ids,
    arg_labels   = EXCLUDED.arg_labels,
    fol_definition = EXCLUDED.fol_definition,
    nl_description = EXCLUDED.nl_description,
    source_predicate = EXCLUDED.source_predicate,
    is_basis = true, status = 'confirmed';

oid := stable_uuid('member_of', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'member_of', 'member of',
    'x is a member of group or set y (not part-whole; no transitivity assumed).')
ON CONFLICT (canonical_name, kind) DO NOTHING;

INSERT INTO predicates
    (id, arity, arg_type_ids, arg_labels,
     fol_definition, nl_description, source_predicate,
     is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2,
    ARRAY[t_entity, t_group],
    ARRAY['member', 'group'],
    'primitive',
    'x is a member of y',
    'wikidata:P463',
    true, 'soft', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET
    arg_type_ids = EXCLUDED.arg_type_ids,
    arg_labels   = EXCLUDED.arg_labels,
    fol_definition = EXCLUDED.fol_definition,
    nl_description = EXCLUDED.nl_description,
    source_predicate = EXCLUDED.source_predicate,
    is_basis = true, status = 'confirmed';

oid := stable_uuid('contains', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'contains', 'contains',
    'x physically or abstractly contains y.')
ON CONFLICT (canonical_name, kind) DO NOTHING;

INSERT INTO predicates
    (id, arity, arg_type_ids, arg_labels,
     fol_definition, nl_description, source_predicate,
     is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2,
    ARRAY[t_entity, t_entity],
    ARRAY['container', 'contained'],
    'contains(X,Y) :- part_of(Y,X) [spatial sense]',
    'x contains y',
    NULL,
    true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET
    arg_type_ids = EXCLUDED.arg_type_ids,
    arg_labels   = EXCLUDED.arg_labels,
    fol_definition = EXCLUDED.fol_definition,
    nl_description = EXCLUDED.nl_description,
    is_basis = true, status = 'confirmed';


-- ════════════════════════════════════════════════════════════
-- GROUP 3: SPATIAL  (4)
-- located_in(entity, place, time) — ternary
-- transferred_to(thing, source, target) — ternary
-- ════════════════════════════════════════════════════════════

-- located_in(entity, place, time) — third arg is a time/temporal object.
-- time arg may be NULL (literal) for timeless geographic facts.
oid := stable_uuid('located_in', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'located_in', 'located in',
    'x is situated within or at location y at time z. '
    'Third arg (time) may be NULL for timeless geographic containment.')
ON CONFLICT (canonical_name, kind) DO NOTHING;

INSERT INTO predicates
    (id, arity, arg_type_ids, arg_labels,
     fol_definition, nl_description, source_predicate,
     is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 3,
    ARRAY[t_entity, t_entity, t_entity],  -- entity, place, time/event
    ARRAY['entity', 'place', 'time'],
    'primitive',
    'x is located in y at time z',
    'conceptnet:AtLocation / wikidata:P131',
    true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET
    arg_type_ids = EXCLUDED.arg_type_ids,
    arg_labels   = EXCLUDED.arg_labels,
    fol_definition = EXCLUDED.fol_definition,
    nl_description = EXCLUDED.nl_description,
    source_predicate = EXCLUDED.source_predicate,
    is_basis = true, status = 'confirmed';

oid := stable_uuid('adjacent_to', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'adjacent_to', 'adjacent to',
    'x is spatially next to or bordering y (symmetric).')
ON CONFLICT (canonical_name, kind) DO NOTHING;

INSERT INTO predicates
    (id, arity, arg_type_ids, arg_labels,
     fol_definition, nl_description, source_predicate,
     is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2,
    ARRAY[t_entity, t_entity],
    ARRAY['entity_a', 'entity_b'],
    'primitive; symmetric',
    'x is next to or borders y',
    NULL,
    true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET
    arg_type_ids = EXCLUDED.arg_type_ids,
    arg_labels   = EXCLUDED.arg_labels,
    fol_definition = EXCLUDED.fol_definition,
    nl_description = EXCLUDED.nl_description,
    is_basis = true, status = 'confirmed';

oid := stable_uuid('origin_of', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'origin_of', 'origin of',
    'x is the place, source, or cause from which y originates.')
ON CONFLICT (canonical_name, kind) DO NOTHING;

INSERT INTO predicates
    (id, arity, arg_type_ids, arg_labels,
     fol_definition, nl_description, source_predicate,
     is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2,
    ARRAY[t_entity, t_entity],
    ARRAY['origin', 'thing'],
    'primitive',
    'x is the origin of y',
    'wikidata:P19 generalised',
    true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET
    arg_type_ids = EXCLUDED.arg_type_ids,
    arg_labels   = EXCLUDED.arg_labels,
    fol_definition = EXCLUDED.fol_definition,
    nl_description = EXCLUDED.nl_description,
    source_predicate = EXCLUDED.source_predicate,
    is_basis = true, status = 'confirmed';

oid := stable_uuid('transferred_to', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'transferred_to', 'transferred to',
    'x moved or was transferred from source y to destination z. '
    'Covers physical movement, ownership transfer, transmission of information.')
ON CONFLICT (canonical_name, kind) DO NOTHING;

INSERT INTO predicates
    (id, arity, arg_type_ids, arg_labels,
     fol_definition, nl_description, source_predicate,
     is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 3,
    ARRAY[t_entity, t_entity, t_entity],
    ARRAY['thing', 'source', 'destination'],
    'primitive; bitransitive',
    'x is transferred from y to z',
    'wikidata:P185 generalised',
    true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET
    arg_type_ids = EXCLUDED.arg_type_ids,
    arg_labels   = EXCLUDED.arg_labels,
    fol_definition = EXCLUDED.fol_definition,
    nl_description = EXCLUDED.nl_description,
    source_predicate = EXCLUDED.source_predicate,
    is_basis = true, status = 'confirmed';


-- ════════════════════════════════════════════════════════════
-- GROUP 4: TEMPORAL  (5)
-- Allen interval algebra + has_duration.
-- Temporal predicates take process/event-typed args.
-- ════════════════════════════════════════════════════════════

oid := stable_uuid('before', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'before', 'before',
    'Event or time x occurs strictly before y (transitive, asymmetric).')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_process, t_process], ARRAY['earlier','later'],
    'primitive; transitive; asymmetric', 'x happens strictly before y',
    'allen:before', true, 'soft', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

oid := stable_uuid('after', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'after', 'after',
    'Event or time x occurs strictly after y.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_process, t_process], ARRAY['later','earlier'],
    'after(X,Y) :- before(Y,X)', 'x happens strictly after y',
    'allen:after', true, 'soft', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

oid := stable_uuid('during', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'during', 'during',
    'Event x occurs entirely within the time span of event y.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_process, t_process], ARRAY['contained_event','containing_event'],
    'primitive (Allen interval relation)', 'x occurs within the span of y',
    'allen:during', true, 'soft', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

oid := stable_uuid('simultaneous_with', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'simultaneous_with', 'simultaneous with',
    'Events x and y occur at the same time (symmetric).')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_process, t_process], ARRAY['event_a','event_b'],
    'primitive; symmetric', 'x and y happen at the same time',
    'allen:equals', true, 'soft', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

oid := stable_uuid('has_duration', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'has_duration', 'has duration',
    'Event or state x lasts for duration y.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_process, t_number], ARRAY['event_or_state','quantity'],
    'primitive', 'x lasts for duration y',
    'wikidata:P2047', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';


-- ════════════════════════════════════════════════════════════
-- GROUP 5: CAUSAL / FUNCTIONAL  (6)
-- causes(cause, effect, mechanism) — ternary
-- mechanism arg is often unknown; stored as NULL literal.
-- ════════════════════════════════════════════════════════════

oid := stable_uuid('causes', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'causes', 'causes',
    'x brings about y via mechanism z. '
    'mechanism (z) may be NULL when unknown or irrelevant.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 3, ARRAY[t_entity, t_entity, t_entity],
    ARRAY['cause','effect','mechanism'],
    'primitive; bitransitive', 'x causes y via mechanism z',
    'conceptnet:Causes', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

oid := stable_uuid('enables', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'enables', 'enables',
    'x makes y possible without necessarily causing it.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_entity, t_entity], ARRAY['enabler','enabled'],
    'primitive; weaker than causes', 'x enables y',
    'conceptnet:Enables', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

oid := stable_uuid('prevents', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'prevents', 'prevents',
    'x inhibits or blocks y.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_entity, t_entity], ARRAY['preventer','prevented'],
    'primitive', 'x prevents y',
    'conceptnet:Obstructs', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

oid := stable_uuid('used_for', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'used_for', 'used for',
    'x is typically used to accomplish y.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_entity, t_entity], ARRAY['tool','purpose'],
    'primitive', 'x is used for y',
    'conceptnet:UsedFor', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

oid := stable_uuid('capable_of', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'capable_of', 'capable of',
    'x has the capacity or disposition to do y.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_animate, t_entity], ARRAY['agent','action'],
    'primitive', 'x is capable of y',
    'conceptnet:CapableOf', true, 'soft', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

oid := stable_uuid('motivated_by', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'motivated_by', 'motivated by',
    'Action x is done because of reason or goal y.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_process, t_entity], ARRAY['action','goal'],
    'primitive', 'x is motivated by y',
    'conceptnet:MotivatedByGoal', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';


-- ════════════════════════════════════════════════════════════
-- GROUP 6: AGENTIVE / SOCIAL  (6)
-- has_role(entity, role, scope) — ternary; already seeded by schema.
-- affiliated_with(entity, org, capacity) — ternary.
-- ════════════════════════════════════════════════════════════

-- agent_of(agent, event)
oid := stable_uuid('agent_of', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'agent_of', 'agent of',
    'x is the intentional agent who performs action or event y.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_animate, t_process], ARRAY['agent','action'],
    'primitive', 'x performs y',
    'wikidata:P664', true, 'soft', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

-- created_by(creation, creator)
oid := stable_uuid('created_by', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'created_by', 'created by',
    'x was made, authored, or produced by agent y.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_entity, t_entity], ARRAY['creation','creator'],
    'primitive', 'x was created by y',
    'wikidata:P170 / conceptnet:CreatedBy', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

-- has_role(entity, role, scope) — enrich the schema-seeded predicate.
oid := stable_uuid('has_role', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'has_role', 'has role',
    'x holds role y within scope z (organisation, domain, or context). '
    'Replaces held_office. Scope may be NULL for informal roles. '
    'This is the role/state sense of the copula: '
    '"X is president" → has_role(X, president, [organisation]).')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 3, ARRAY[t_entity, t_entity, t_entity],
    ARRAY['entity','role','scope'],
    'primitive; bitransitive; scope may be NULL',
    'x holds role y within z',
    'wikidata:P39 generalised', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

-- affiliated_with(entity, organisation, capacity)
oid := stable_uuid('affiliated_with', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'affiliated_with', 'affiliated with',
    'x is associated with organisation y in capacity z. '
    'Capacity (z) may be NULL for generic affiliation.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 3, ARRAY[t_entity, t_entity, t_entity],
    ARRAY['entity','organisation','capacity'],
    'primitive; bitransitive', 'x is affiliated with y in capacity z',
    'wikidata:P108 / P463', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

-- related_to — generic fallback; symmetric.
oid := stable_uuid('related_to', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'related_to', 'related to',
    'x and y are related (generic, symmetric). '
    'Use a more specific predicate if one applies.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_entity, t_entity], ARRAY['entity_a','entity_b'],
    'primitive; symmetric', 'x and y are related',
    'conceptnet:RelatedTo', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

-- opposite_of — symmetric, conceptual antonymy.
oid := stable_uuid('opposite_of', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'opposite_of', 'opposite of',
    'x is the conceptual opposite or antonym of y (symmetric).')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_abstract, t_abstract], ARRAY['concept_a','concept_b'],
    'primitive; symmetric', 'x is the opposite of y',
    'conceptnet:Antonym', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';


-- ════════════════════════════════════════════════════════════
-- GROUP 7: QUANTITATIVE  (3)
-- ════════════════════════════════════════════════════════════

oid := stable_uuid('has_quantity', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'has_quantity', 'has quantity',
    'x has measurable quantity y (population, mass, length, …).')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_entity, t_number], ARRAY['entity','quantity'],
    'primitive', 'x has quantity y',
    'wikidata:P1082 etc.', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

oid := stable_uuid('greater_than', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'greater_than', 'greater than',
    'Quantity x is greater than quantity y (asymmetric, transitive).')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_number, t_number], ARRAY['larger','smaller'],
    'primitive; asymmetric; transitive', 'x > y',
    NULL, true, 'soft', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description,
    is_basis=true, status='confirmed';

oid := stable_uuid('approximately_equal', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'approximately_equal', 'approximately equal',
    'x and y are approximately equal in magnitude (symmetric, fuzzy).')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_number, t_number], ARRAY['quantity_a','quantity_b'],
    'primitive; symmetric; fuzzy', 'x ≈ y',
    NULL, true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description,
    is_basis=true, status='confirmed';


-- ════════════════════════════════════════════════════════════
-- GROUP 8: EPISTEMIC / MODAL  (5)
-- knows, believes: agent arg constrained to sapient.
-- possible, necessary: unary (1 arg).
-- ════════════════════════════════════════════════════════════

oid := stable_uuid('knows', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'knows', 'knows',
    'Agent x has knowledge of fact, concept, or entity y (veridical).')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_sapient, t_entity], ARRAY['knower','known'],
    'primitive; knows(X,Y) -> true(Y)', 'x knows y',
    NULL, true, 'soft', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, is_basis=true, status='confirmed';

oid := stable_uuid('believes', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'believes', 'believes',
    'Agent x believes y to be true (non-veridical; belief may be false).')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_sapient, t_entity], ARRAY['believer','believed'],
    'primitive; distinct from knows; believes(X,Y) does not entail true(Y)',
    'x believes y', NULL, true, 'soft', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, is_basis=true, status='confirmed';

oid := stable_uuid('desires', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'desires', 'desires',
    'Agent x wants or desires y.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_sapient, t_entity], ARRAY['desirer','desired'],
    'primitive', 'x desires y',
    'conceptnet:Desires', true, 'soft', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

-- possible(proposition) — unary (1 arg)
oid := stable_uuid('possible', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'possible', 'possible',
    'Proposition x is possible (not necessarily actual). Intransitive (1 arg).')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 1, ARRAY[t_entity], ARRAY['proposition'],
    'primitive; modal', 'x is possible',
    NULL, true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, is_basis=true, status='confirmed';

-- necessary(proposition) — unary (1 arg)
oid := stable_uuid('necessary', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'necessary', 'necessary',
    'x is necessarily true — could not be otherwise. Intransitive (1 arg).')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 1, ARRAY[t_entity], ARRAY['proposition'],
    'primitive; modal; necessary(X) -> possible(X)', 'x is necessarily true',
    NULL, true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, is_basis=true, status='confirmed';


-- ════════════════════════════════════════════════════════════
-- GROUP 9: LINGUISTIC / REPRESENTATIONAL  (3)
-- arg_type_ids left NULL where no backbone type exists yet
-- (language, symbol, name) — tighten in a later migration.
-- ════════════════════════════════════════════════════════════

oid := stable_uuid('named', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'named', 'named',
    'Entity x has name y in natural language.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_entity, NULL], ARRAY['entity','name'],
    'primitive', 'x is named y',
    'rdfs:label / wikidata:P2561', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

oid := stable_uuid('symbol_for', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'symbol_for', 'symbol for',
    'x is a symbol or representation of y.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_entity, t_entity], ARRAY['symbol','concept'],
    'primitive', 'x is a symbol of y',
    'conceptnet:SymbolOf', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

oid := stable_uuid('language_of', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'language_of', 'language of',
    'Language x is spoken, written, or used by y.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_entity, t_entity], ARRAY['language','entity'],
    'primitive', 'x is the language of y',
    'wikidata:P407', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';


-- ════════════════════════════════════════════════════════════
-- GROUP 10: EVENT CALCULUS CORE  (4)
-- holds_at_ec avoids collision with the holds_at() SQL function.
-- ════════════════════════════════════════════════════════════

oid := stable_uuid('initiates', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'initiates', 'initiates',
    'Event x causes state/fluent y to begin holding.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_process, t_entity], ARRAY['event','fluent'],
    'primitive; event calculus', 'event x initiates fluent y',
    'ec:Initiates', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

oid := stable_uuid('terminates', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'terminates', 'terminates',
    'Event x causes state/fluent y to stop holding.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_process, t_entity], ARRAY['event','fluent'],
    'primitive; event calculus', 'event x terminates fluent y',
    'ec:Terminates', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

oid := stable_uuid('happens_at', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'happens_at', 'happens at',
    'Event x occurs at time y.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_process, t_entity], ARRAY['event','time'],
    'primitive; event calculus', 'event x happens at time y',
    'ec:HappensAt', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

oid := stable_uuid('holds_at_ec', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'holds_at_ec', 'holds at (EC)',
    'State or fluent x is true at time y (Event Calculus meta-predicate). '
    'Named holds_at_ec to avoid collision with the holds_at() SQL function.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_entity, t_entity], ARRAY['fluent','time'],
    'derived from initiates/terminates/happens_at chain', 'fluent x holds at time y',
    'ec:HoldsAt', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';


-- ════════════════════════════════════════════════════════════
-- GROUP 11: PHYSICAL / LIFECYCLE  (4)
-- born_in / died_in absent — use located_in + temporal scope.
-- ════════════════════════════════════════════════════════════

oid := stable_uuid('made_of', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'made_of', 'made of',
    'x is composed of or constructed from material y.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_concrete, t_entity], ARRAY['object','material'],
    'primitive', 'x is made of y',
    'conceptnet:MadeOf', true, 'soft', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

oid := stable_uuid('has_state', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'has_state', 'has state',
    'Entity x is in physical or abstract state y.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_entity, t_entity], ARRAY['entity','state'],
    'primitive', 'x is in state y',
    NULL, true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, is_basis=true, status='confirmed';

oid := stable_uuid('precondition_of', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'precondition_of', 'precondition of',
    'x must hold before y can occur.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_entity, t_process], ARRAY['condition','event'],
    'precondition_of(X,Y) :- necessary(X) ∧ before(X,Y)', 'x is a precondition of y',
    'conceptnet:HasPrerequisite', true, 'soft', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

oid := stable_uuid('affects', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'affects', 'affects',
    'x has some effect on y (weaker than causes; no mechanism implied).')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_entity, t_entity], ARRAY['influencer','influenced'],
    'weaker than causes; affects(X,Y) does not assert direction', 'x affects y',
    'conceptnet:Causes (weak)', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';


-- ════════════════════════════════════════════════════════════
-- GROUP 12: INFERENTIAL / CORRELATIONAL  (4)
-- ════════════════════════════════════════════════════════════

oid := stable_uuid('implies', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'implies', 'implies',
    'x logically or probabilistically entails y. '
    'Distinct from causes: no temporal order or mechanism required.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_entity, t_entity], ARRAY['antecedent','consequent'],
    'primitive; crisp at P=1, probabilistic at P<1', 'x implies y',
    NULL, true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, is_basis=true, status='confirmed';

oid := stable_uuid('correlated_with', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'correlated_with', 'correlated with',
    'x and y tend to co-occur or vary together (symmetric; no causal claim).')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_entity, t_entity], ARRAY['entity_a','entity_b'],
    'primitive; symmetric; weaker than causes or implies', 'x and y are correlated',
    NULL, true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, is_basis=true, status='confirmed';

oid := stable_uuid('typical_of', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'typical_of', 'typical of',
    'x is a typical or prototypical instance of category y (graded). '
    'Encodes the exemplification sense of the copula. '
    'Belief value encodes typicality degree; belief=1 → maximally typical.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_entity, t_abstract], ARRAY['instance','category'],
    'primitive; graded; distinct from is_a (crisp) and has_property',
    'x is a typical instance of y',
    'conceptnet:IsA (prototype sense)', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

oid := stable_uuid('occurs_in', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'occurs_in', 'occurs in',
    'Event x takes place within situation, context, or location y.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_process, t_entity], ARRAY['event','situation'],
    'primitive; complements located_in (objects) and during (time)',
    'event x occurs in situation or location y',
    NULL, true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, is_basis=true, status='confirmed';


-- ════════════════════════════════════════════════════════════
-- GROUP 13: STRUCTURAL / LOGICAL  (3)
-- ════════════════════════════════════════════════════════════

-- equivalent_to — intensional equivalence; stronger than same_as.
oid := stable_uuid('equivalent_to', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'equivalent_to', 'equivalent to',
    'x and y are definitionally or intensionally equivalent. '
    'Stronger than same_as (co-reference): equivalent_to requires '
    'the same meaning, not just the same referent.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_abstract, t_abstract], ARRAY['concept_a','concept_b'],
    'primitive; symmetric; equivalent_to(X,Y) → same_as(X,Y) but not vice versa',
    'x is definitionally equivalent to y',
    'owl:equivalentClass / owl:equivalentProperty', true, 'soft', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

-- disjoint_with — no instance can belong to both types.
oid := stable_uuid('disjoint_with', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'disjoint_with', 'disjoint with',
    'No entity can simultaneously be an instance of both x and y. '
    'Essential for type-violation conflict detection.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_abstract, t_abstract], ARRAY['type_a','type_b'],
    'disjoint_with(X,Y) :- not exists Z s.t. is_a(Z,X) ∧ is_a(Z,Y)',
    'types x and y share no instances',
    'owl:disjointWith', true, 'hard', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';

-- has_value(entity, attribute, value) — ternary; third arg usually a literal.
oid := stable_uuid('has_value', 'predicate');
INSERT INTO objects (id, kind, canonical_name, display_name, description)
VALUES (oid, 'predicate', 'has_value', 'has value',
    'Entity x has attribute y with value z. '
    'Third arg (z) is typically a literal (integer, float, string). '
    'Distinct from has_quantity: has_value names the attribute explicitly.')
ON CONFLICT (canonical_name, kind) DO NOTHING;
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 3, ARRAY[t_entity, t_abstract, NULL],
    ARRAY['entity','attribute','value'],
    'primitive; bitransitive; value arg is typically in literal_args',
    'x has attribute y with value z',
    'wikidata:P1 generalised', true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, source_predicate=EXCLUDED.source_predicate,
    is_basis=true, status='confirmed';


-- ════════════════════════════════════════════════════════════
-- ENRICHMENT: schema-seeded predicates not already covered
-- ════════════════════════════════════════════════════════════

-- has_capacity — seeded by schema; enrich with arg_type_ids.
oid := stable_uuid('has_capacity', 'predicate');
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 2, ARRAY[t_entity, t_entity], ARRAY['entity','capacity'],
    'primitive', 'x possesses capacity y',
    NULL, true, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, is_basis=true, status='confirmed';

-- models_as — seeded by schema; enrich with arg_type_ids.
oid := stable_uuid('models_as', 'predicate');
INSERT INTO predicates (id, arity, arg_type_ids, arg_labels, fol_definition,
    nl_description, source_predicate, is_basis, domain_strictness, status, introduced_by)
VALUES (oid, 3, ARRAY[t_entity, t_abstract, t_entity],
    ARRAY['subject','type','context'],
    'primitive; non-ontological modeling convenience',
    'subject is modeled as type within context',
    NULL, false, 'none', 'confirmed', sys)
ON CONFLICT (id) DO UPDATE SET arg_type_ids=EXCLUDED.arg_type_ids,
    arg_labels=EXCLUDED.arg_labels, fol_definition=EXCLUDED.fol_definition,
    nl_description=EXCLUDED.nl_description, status='confirmed';

-- instance_of — seeded by schema; record equivalence to is_a.
-- We do NOT delete instance_of; instead we link it via object_equivalence.
-- Callers should prefer is_a; instance_of remains as an alias.
INSERT INTO object_equivalence (object_a, object_b, alpha, beta, context_id)
VALUES (
    LEAST(   stable_uuid('is_a',        'predicate'),
             stable_uuid('instance_of', 'predicate') ),
    GREATEST(stable_uuid('is_a',        'predicate'),
             stable_uuid('instance_of', 'predicate') ),
    19.0, 1.0, stable_uuid('reality', 'context')
)
ON CONFLICT (object_a, object_b) DO NOTHING;

END $$;

COMMIT;

-- ── Verification query ────────────────────────────────────────
SELECT
    o.canonical_name,
    p.arity,
    CASE p.arity
        WHEN 1 THEN 'intransitive'
        WHEN 2 THEN 'transitive'
        WHEN 3 THEN 'bitransitive'
        ELSE        'higher'
    END                AS transitivity,
    p.arg_labels,
    p.domain_strictness,
    p.source_predicate
FROM predicates p
JOIN objects    o ON o.id = p.id
WHERE p.is_basis = true
ORDER BY p.arity, o.canonical_name;

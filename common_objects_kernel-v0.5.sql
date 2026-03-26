-- =============================================================
-- Common Knowledge KB — Basis Objects & Statements (v0.5)
-- =============================================================
-- Compatibility notes vs. the v3 object/statement kernel:
--
--   UUID KEY SCHEME (breaking change from v3):
--   • All entity-kinded objects now use stable_uuid(name, 'entity').
--   • The v0.5 schema backbone already seeds a subset of these
--     (entity, concrete, abstract, living, animate, sapient,
--      artifact, process, group, person, number, relation) under
--     stable_uuid(name, 'entity').
--   • This file UPSERTS those backbone rows (DO NOTHING on conflict)
--     and adds the remaining concept objects, all using the same
--     'entity' suffix — so the entire ontology shares one namespace.
--   • Where v3 used stable_uuid(name, 'concept'), this file uses
--     stable_uuid(name, 'entity').  If you have existing data from
--     the v3 kernel, run the migration note at the bottom.
--
--   KIND CHANGE:
--   • object.kind = 'concept' no longer exists.  All concept/type
--     objects now use kind = 'entity'.  This is correct: types are
--     abstract entities in the ontology.
--
--   BACKBONE OVERLAP:
--   • The schema backbone (ckb_schema_v0.5.sql) seeds:
--       entity, concrete, abstract, living, animate, sapient,
--       artifact, process, group, person, number, relation,
--       agent, institution, government
--     plus subtype_of statements linking them.
--   • This file does NOT duplicate those subtype_of statements;
--     it extends the hierarchy downward and adds the full concept
--     vocabulary.
--   • object_equivalence rows are inserted where this file's
--     canonical names differ from backbone names (e.g.
--     'abstract_thing' ↔ 'abstract', 'physical_thing' ↔ 'concrete').
--
--   STATEMENT CHANGES:
--   • No arg_types on statements (lives on predicates in v0.5).
--   • negated boolean removed; use conflicts table for opposition.
--   • interpretation column added; all axiomatic statements use
--     'ontological' (the default).
--   • FOL implies statements: object_args = '{}' with literal_args
--     satisfies the args_nonempty constraint (literal_args has rows).
--
--   DOMAIN CONTEXTS:
--   • kind = 'context' objects still exist; contexts table rows
--     required by orphan-guard trigger.
--
-- What is NOT here:
--   • Named individuals (specific persons, places, events).
--   • Contingent or time-bounded facts.
--   • Anything requiring a source other than system_kernel.
--
-- All statements use:
--   belief_alpha = 1000.0, belief_beta = 0.001  (near-certain)
--   t_kind       = 'eternal' (unless noted)
--   interpretation = 'ontological' (default)
--   derivation_type = 'axiomatic'
-- =============================================================

BEGIN;

DO $$
DECLARE
    -- ── Fixed IDs from schema seed ────────────────────────────
    reality  uuid := stable_uuid('reality',       'context');
    sys      uuid := stable_uuid('system_kernel', 'source');

    -- ── Predicate IDs ─────────────────────────────────────────
    p_is_a           uuid := stable_uuid('is_a',            'predicate');
    p_subtype_of     uuid := stable_uuid('subtype_of',      'predicate');
    p_has_property   uuid := stable_uuid('has_property',    'predicate');
    p_same_as        uuid := stable_uuid('same_as',         'predicate');
    p_different_from uuid := stable_uuid('different_from',  'predicate');
    p_opposite_of    uuid := stable_uuid('opposite_of',     'predicate');
    p_implies        uuid := stable_uuid('implies',         'predicate');
    p_typical_of     uuid := stable_uuid('typical_of',      'predicate');
    p_disjoint_with  uuid := stable_uuid('disjoint_with',   'predicate');
    p_has_value      uuid := stable_uuid('has_value',       'predicate');
    p_equivalent_to  uuid := stable_uuid('equivalent_to',   'predicate');
    p_part_of        uuid := stable_uuid('part_of',         'predicate');
    p_member_of      uuid := stable_uuid('member_of',       'predicate');

    -- ── Kernel belief parameters ──────────────────────────────
    ka  double precision := 1000.0;
    kb  double precision := 0.001;

    -- ── Object IDs — all stable_uuid(name, 'entity') ─────────
    -- Backbone objects (seeded by schema; DO NOTHING on conflict)
    o_entity        uuid := stable_uuid('entity',           'entity');
    o_abstract      uuid := stable_uuid('abstract',         'entity');  -- = abstract_thing
    o_concrete      uuid := stable_uuid('concrete',         'entity');  -- = physical_thing
    o_living        uuid := stable_uuid('living',           'entity');
    o_animate       uuid := stable_uuid('animate',          'entity');
    o_sapient       uuid := stable_uuid('sapient',          'entity');
    o_artifact      uuid := stable_uuid('artifact',         'entity');
    o_process       uuid := stable_uuid('process',          'entity');
    o_group         uuid := stable_uuid('group',            'entity');
    o_person        uuid := stable_uuid('person',           'entity');
    o_number        uuid := stable_uuid('number',           'entity');
    o_relation      uuid := stable_uuid('relation',         'entity');
    o_agent         uuid := stable_uuid('agent',            'entity');
    o_institution   uuid := stable_uuid('institution',      'entity');

    -- Animate / social (extensions beyond backbone)
    o_biological_taxon uuid := stable_uuid('biological_taxon','entity');
    o_organism      uuid := stable_uuid('organism',         'entity');
    o_animal        uuid := stable_uuid('animal',           'entity');
    o_mammal        uuid := stable_uuid('mammal',           'entity');

    -- Abstract concept vocabulary
    o_concept_type  uuid := stable_uuid('concept_type',     'entity');
    o_property_c    uuid := stable_uuid('property',         'entity');
    o_attribute     uuid := stable_uuid('attribute',        'entity');
    o_relation_type uuid := stable_uuid('relation_type',    'entity');
    o_proposition   uuid := stable_uuid('proposition',      'entity');
    o_information   uuid := stable_uuid('information',      'entity');
    o_knowledge_st  uuid := stable_uuid('knowledge_state',  'entity');
    o_norm          uuid := stable_uuid('norm',             'entity');
    o_rule          uuid := stable_uuid('rule',             'entity');
    o_goal          uuid := stable_uuid('goal',             'entity');
    o_role_c        uuid := stable_uuid('role',             'entity');
    o_symbol        uuid := stable_uuid('symbol',           'entity');
    o_language      uuid := stable_uuid('language',         'entity');
    o_word          uuid := stable_uuid('word',             'entity');
    o_sentence      uuid := stable_uuid('sentence',         'entity');

    -- Events / processes / states
    o_event         uuid := stable_uuid('event_type',       'entity');
    o_change_event  uuid := stable_uuid('change_event',     'entity');
    o_state_c       uuid := stable_uuid('state',            'entity');
    o_action        uuid := stable_uuid('action',           'entity');

    -- Physical subtypes
    o_phys_obj      uuid := stable_uuid('physical_object',  'entity');
    o_place         uuid := stable_uuid('place',            'entity');
    o_region        uuid := stable_uuid('region',           'entity');
    o_location      uuid := stable_uuid('location',         'entity');
    o_boundary      uuid := stable_uuid('boundary',         'entity');

    -- Quantities and numbers
    o_quantity      uuid := stable_uuid('quantity',         'entity');
    o_real          uuid := stable_uuid('real_number',      'entity');
    o_integer       uuid := stable_uuid('integer',          'entity');
    o_natural       uuid := stable_uuid('natural_number',   'entity');
    o_unit          uuid := stable_uuid('unit_of_measure',  'entity');
    o_measurement   uuid := stable_uuid('measurement',      'entity');
    o_duration      uuid := stable_uuid('duration',         'entity');

    -- Time
    o_time          uuid := stable_uuid('time',             'entity');
    o_interval_t    uuid := stable_uuid('time_interval',    'entity');
    o_point_t       uuid := stable_uuid('time_point',       'entity');

    -- Truth values (schema seeds true/false/unknown as 'entity' kind in v0.5)
    o_truth_value   uuid := stable_uuid('truth_value',      'entity');
    o_true_val      uuid := stable_uuid('true',             'entity');
    o_false_val     uuid := stable_uuid('false',            'entity');
    o_unknown_val   uuid := stable_uuid('unknown',          'entity');

    -- Domain contexts
    o_dom_history   uuid := stable_uuid('domain_history',   'context');
    o_dom_science   uuid := stable_uuid('domain_science',   'context');
    o_dom_math      uuid := stable_uuid('domain_mathematics','context');
    o_dom_geography uuid := stable_uuid('domain_geography', 'context');
    o_dom_biology   uuid := stable_uuid('domain_biology',   'context');
    o_dom_physics   uuid := stable_uuid('domain_physics',   'context');
    o_dom_law       uuid := stable_uuid('domain_law',       'context');
    o_dom_language  uuid := stable_uuid('domain_linguistics','context');
    o_dom_social    uuid := stable_uuid('domain_social',    'context');
    o_dom_tech      uuid := stable_uuid('domain_technology','context');

BEGIN

-- ═════════════════════════════════════════════════════════════
-- SECTION 1: Sanity check
-- ═════════════════════════════════════════════════════════════

IF NOT EXISTS (SELECT 1 FROM objects WHERE id = p_is_a AND kind = 'predicate') THEN
    RAISE EXCEPTION
        'Basis predicates not found (expected is_a at %). '
        'Run ckb_basis_predicates_v0.5.sql before this file.',
        p_is_a;
END IF;

IF NOT EXISTS (SELECT 1 FROM objects WHERE id = o_entity AND kind = 'entity') THEN
    RAISE EXCEPTION
        'Backbone entity objects not found. '
        'Run ckb_schema_v0.5.sql before this file.';
END IF;

-- ═════════════════════════════════════════════════════════════
-- SECTION 2: Backbone objects — upsert to add descriptions
-- (schema seed inserts them with minimal descriptions; we enrich here)
-- ═════════════════════════════════════════════════════════════

UPDATE objects SET
    display_name = 'Entity',
    description  = 'Anything that exists or can be referred to. '
                   'Absolute top of the object hierarchy.'
WHERE id = o_entity;

UPDATE objects SET
    display_name = 'Abstract',
    description  = 'An entity with no direct physical instantiation: '
                   'concepts, numbers, propositions, rules, relations.'
WHERE id = o_abstract;

UPDATE objects SET
    display_name = 'Concrete',
    description  = 'An entity that occupies or is located in physical space and time.'
WHERE id = o_concrete;

-- true/false/unknown: schema seeds these; enrich descriptions
UPDATE objects SET description = 'The Boolean value true; an instance of truth_value.'
WHERE id = o_true_val;
UPDATE objects SET description = 'The Boolean value false; an instance of truth_value.'
WHERE id = o_false_val;
UPDATE objects SET description = 'Unknown or indeterminate truth value; an instance of truth_value.'
WHERE id = o_unknown_val;

-- ═════════════════════════════════════════════════════════════
-- SECTION 3: Animate / social objects (extensions beyond backbone)
-- ═════════════════════════════════════════════════════════════

INSERT INTO objects (id, kind, canonical_name, display_name, description) VALUES
    (o_biological_taxon, 'entity', 'biological_taxon', 'Biological taxon',
     'A named group in a biological classification system '
     '(species, genus, family, …). Abstract type, not a physical organism.'),
    (o_organism, 'entity', 'organism', 'Organism',
     'A living entity: plant, animal, fungus, microbe.'),
    (o_animal,   'entity', 'animal',   'Animal',
     'A multicellular organism of the kingdom Animalia.'),
    (o_mammal,   'entity', 'mammal',   'Mammal',
     'A warm-blooded vertebrate of class Mammalia; nurses young with milk.')
ON CONFLICT (canonical_name, kind) DO NOTHING;

-- ═════════════════════════════════════════════════════════════
-- SECTION 4: Abstract concept vocabulary
-- ═════════════════════════════════════════════════════════════

INSERT INTO objects (id, kind, canonical_name, display_name, description) VALUES
    (o_concept_type, 'entity', 'concept_type', 'Concept',
     'An abstract idea, category, or mental representation.'),
    (o_property_c,   'entity', 'property',     'Property',
     'An attribute or characteristic that an entity can have; a unary predicate.'),
    (o_attribute,    'entity', 'attribute',    'Attribute',
     'A named feature of an entity that takes a value. '
     'Distinct from property: attributes have values; properties are Boolean.'),
    (o_relation_type,'entity', 'relation_type','Relation type',
     'A type of relation in the predicate vocabulary '
     '(e.g. subtype_of, causes). Subtype of relation.'),
    (o_proposition,  'entity', 'proposition',  'Proposition',
     'A statement that is either true or false in some context.'),
    (o_information,  'entity', 'information',  'Information',
     'Structured content that can be communicated or encoded. '
     'Distinct from knowledge: information does not require a knowing agent.'),
    (o_knowledge_st, 'entity', 'knowledge_state', 'Knowledge state',
     'The set of propositions an agent takes to be true at a time. '
     'Argument type for knows() and believes().'),
    (o_norm,         'entity', 'norm',         'Norm',
     'A standard, obligation, or expectation governing behaviour in a context.'),
    (o_rule,         'entity', 'rule',         'Rule',
     'A formal or informal prescription specifying what should happen '
     'under a condition. Subtype of norm.'),
    (o_goal,         'entity', 'goal',         'Goal',
     'A desired state or outcome that an agent is motivated to bring about.'),
    (o_role_c,       'entity', 'role',         'Role',
     'A position, function, or capacity that an entity occupies within a scope. '
     'Second argument of has_role(entity, role, scope).'),
    (o_symbol,       'entity', 'symbol',       'Symbol',
     'A sign that represents something else by convention.'),
    (o_language,     'entity', 'language',     'Language',
     'A system of communication using symbols according to a grammar.'),
    (o_word,         'entity', 'word',         'Word',
     'A minimal free-standing linguistic unit in a language.'),
    (o_sentence,     'entity', 'sentence',     'Sentence',
     'A grammatical unit expressing a complete thought or proposition.')
ON CONFLICT (canonical_name, kind) DO NOTHING;

-- ═════════════════════════════════════════════════════════════
-- SECTION 5: Event / process / state objects
-- ═════════════════════════════════════════════════════════════

INSERT INTO objects (id, kind, canonical_name, display_name, description) VALUES
    (o_event,       'entity', 'event_type',   'Event',
     'A change or occurrence at a time, involving participants. '
     'Abstract type; not a physical object.'),
    (o_change_event,'entity', 'change_event', 'Change event',
     'An event in which some property or state transitions from one value to another. '
     'Core to Event Calculus: initiates() and terminates() apply to change_events.'),
    (o_state_c,     'entity', 'state',        'State',
     'A condition that persists over a time interval without requiring ongoing action.'),
    (o_action,      'entity', 'action',       'Action',
     'An event intentionally performed by an agent.')
ON CONFLICT (canonical_name, kind) DO NOTHING;

-- ═════════════════════════════════════════════════════════════
-- SECTION 6: Physical / spatial objects
-- ═════════════════════════════════════════════════════════════

INSERT INTO objects (id, kind, canonical_name, display_name, description) VALUES
    (o_phys_obj,  'entity', 'physical_object', 'Physical object',
     'A bounded physical entity: tool, artifact, natural body.'),
    (o_place,     'entity', 'place',           'Place',
     'A location or region in physical space.'),
    (o_region,    'entity', 'region',          'Region',
     'An extended area of space, possibly with administrative or natural boundaries.'),
    (o_location,  'entity', 'location',        'Location',
     'A specific point or area used to describe where something is.'),
    (o_boundary,  'entity', 'boundary',        'Boundary',
     'The interface or limit between two regions or entities. '
     'Part of a region without being a region itself.')
ON CONFLICT (canonical_name, kind) DO NOTHING;

-- ═════════════════════════════════════════════════════════════
-- SECTION 7: Quantities and measurement
-- ═════════════════════════════════════════════════════════════

INSERT INTO objects (id, kind, canonical_name, display_name, description) VALUES
    (o_quantity,   'entity', 'quantity',       'Quantity',
     'A measurable or countable amount.'),
    (o_real,       'entity', 'real_number',    'Real number',
     'A number on the continuous number line, including irrationals.'),
    (o_integer,    'entity', 'integer',        'Integer',
     'A whole number: …−2, −1, 0, 1, 2…  Subtype of real_number.'),
    (o_natural,    'entity', 'natural_number', 'Natural number',
     'A non-negative integer: 0, 1, 2, 3…  Convention here includes 0.'),
    (o_unit,       'entity', 'unit_of_measure','Unit of measure',
     'A standard quantity used to express a measurement '
     '(metre, kilogram, second, …).'),
    (o_measurement,'entity', 'measurement',   'Measurement',
     'A quantity expressed in a specific unit; a pairing of number and unit.'),
    (o_duration,   'entity', 'duration',      'Duration',
     'The length of a time interval, expressed as a quantity. '
     'A duration is NOT a time interval — it is a measure of one.')
ON CONFLICT (canonical_name, kind) DO NOTHING;

-- ═════════════════════════════════════════════════════════════
-- SECTION 8: Time objects
-- duration is a quantity (measures time), not a subtype of time.
-- ═════════════════════════════════════════════════════════════

INSERT INTO objects (id, kind, canonical_name, display_name, description) VALUES
    (o_time,       'entity', 'time',          'Time',
     'The dimension along which events are ordered; '
     'the abstract type for temporal entities.'),
    (o_interval_t, 'entity', 'time_interval', 'Time interval',
     'A bounded span of time with a start and an end.'),
    (o_point_t,    'entity', 'time_point',    'Time point',
     'An instantaneous moment in time.')
ON CONFLICT (canonical_name, kind) DO NOTHING;

-- ═════════════════════════════════════════════════════════════
-- SECTION 9: Truth value supertype
-- true/false/unknown already seeded by schema; add truth_value.
-- ═════════════════════════════════════════════════════════════

INSERT INTO objects (id, kind, canonical_name, display_name, description) VALUES
    (o_truth_value, 'entity', 'truth_value', 'Truth value',
     'The type whose instances are true, false, and unknown.')
ON CONFLICT (canonical_name, kind) DO NOTHING;

-- ═════════════════════════════════════════════════════════════
-- SECTION 10: Domain context objects
-- ═════════════════════════════════════════════════════════════

INSERT INTO objects (id, kind, canonical_name, display_name, description) VALUES
    (o_dom_history,  'context', 'domain_history',    'History',
     'Historical facts, events, persons, dates.'),
    (o_dom_science,  'context', 'domain_science',    'Science (general)',
     'Scientific facts not specific to one discipline.'),
    (o_dom_math,     'context', 'domain_mathematics','Mathematics',
     'Mathematical definitions, theorems, structures.'),
    (o_dom_geography,'context', 'domain_geography',  'Geography',
     'Geographical facts: locations, borders, populations.'),
    (o_dom_biology,  'context', 'domain_biology',    'Biology',
     'Biological facts: taxonomy, anatomy, physiology, ecology.'),
    (o_dom_physics,  'context', 'domain_physics',    'Physics',
     'Physical laws, constants, and phenomena.'),
    (o_dom_law,      'context', 'domain_law',        'Law',
     'Legal facts, statutes, decisions — jurisdiction-sensitive.'),
    (o_dom_language, 'context', 'domain_linguistics','Linguistics',
     'Facts about language, grammar, and meaning.'),
    (o_dom_social,   'context', 'domain_social',     'Social science',
     'Facts about society, culture, economics, politics.'),
    (o_dom_tech,     'context', 'domain_technology', 'Technology',
     'Facts about technology, engineering, computing.')
ON CONFLICT (canonical_name, kind) DO NOTHING;

-- Register domain contexts (orphan-guard requires contexts row)
INSERT INTO contexts (id, kind, parent_id) VALUES
    (o_dom_history,   'domain', reality),
    (o_dom_science,   'domain', reality),
    (o_dom_math,      'domain', reality),
    (o_dom_geography, 'domain', reality),
    (o_dom_biology,   'domain', reality),
    (o_dom_physics,   'domain', reality),
    (o_dom_law,       'domain', reality),
    (o_dom_language,  'domain', reality),
    (o_dom_social,    'domain', reality),
    (o_dom_tech,      'domain', reality)
ON CONFLICT (id) DO NOTHING;

-- ═════════════════════════════════════════════════════════════
-- SECTION 11: Object equivalences
-- Where this file's canonical names differ from backbone names,
-- record a near-certain same_as equivalence so queries using
-- either name find the same object.
-- Note: backbone uses 'abstract'; this file adds 'abstract_thing'
-- as an alias via equivalence rather than a separate object.
-- ═════════════════════════════════════════════════════════════

-- 'relation' (backbone) ↔ 'relation' (this file: same ID, no conflict)
-- 'abstract' (backbone) ↔ conceptually 'abstract_thing' from v3
-- We record this as a description alias rather than a separate object,
-- since the IDs are now unified.

-- process: backbone seeds 'process'; event_type is new here.
-- They are NOT equivalent — process ⊂ event_type.
-- No equivalence needed; subtype_of handles it below.

-- ═════════════════════════════════════════════════════════════
-- SECTION 12: Type hierarchy — subtype_of statements
-- The backbone already seeds:
--   concrete ⊂ entity, abstract ⊂ entity,
--   living ⊂ concrete, animate ⊂ living, sapient ⊂ animate,
--   person ⊂ sapient, artifact ⊂ concrete,
--   process ⊂ entity, group ⊂ entity,
--   number ⊂ abstract, relation ⊂ abstract
-- We DO NOT repeat those here.  We extend downward and sideways.
-- ═════════════════════════════════════════════════════════════

INSERT INTO statements
    (predicate_id, object_args, belief_alpha, belief_beta,
     interpretation, t_kind, context_id, derivation_type, derivation_depth)
VALUES

-- ── Concrete subtypes (beyond backbone) ──────────────────────
(p_subtype_of, ARRAY[o_organism,    o_concrete],   ka,kb,'ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_phys_obj,    o_concrete],   ka,kb,'ontological','eternal',reality,'axiomatic',0),
-- artifact is already seeded as artifact ⊂ concrete by backbone;
-- here we add it also under phys_obj (more specific)
(p_subtype_of, ARRAY[o_artifact,    o_phys_obj],   ka,kb,'ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_place,       o_concrete],   ka,kb,'ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_region,      o_place],      ka,kb,'ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_location,    o_place],      ka,kb,'ontological','eternal',reality,'axiomatic',0),
-- boundary is abstract (it has no volume; it is a limit, not a region)
(p_subtype_of, ARRAY[o_boundary,    o_abstract],   ka,kb,'ontological','eternal',reality,'axiomatic',0),

-- ── Animate hierarchy (extensions below backbone's sapient) ──
(p_subtype_of, ARRAY[o_biological_taxon, o_concept_type], ka,kb,'ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_animal,      o_organism],   ka,kb,'ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_mammal,      o_animal],     ka,kb,'ontological','eternal',reality,'axiomatic',0),
-- person ⊂ mammal (more specific than backbone's person ⊂ sapient)
(p_subtype_of, ARRAY[o_person,      o_mammal],     ka,kb,'ontological','eternal',reality,'axiomatic',0),
-- person is also an agent (dual supertype; tree allows multiple statements)
(p_subtype_of, ARRAY[o_person,      o_agent],      ka,kb,'ontological','eternal',reality,'axiomatic',0),
-- agent ⊂ entity (agent is a role-type, but also a real entity category)
(p_subtype_of, ARRAY[o_agent,       o_entity],     ka,kb,'ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_institution, o_agent],      ka,kb,'ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_group,       o_entity],     ka,kb,'ontological','eternal',reality,'axiomatic',0),

-- ── Abstract subtypes ─────────────────────────────────────────
(p_subtype_of, ARRAY[o_concept_type,  o_abstract], ka,kb,'ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_property_c,    o_abstract], ka,kb,'ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_attribute,     o_property_c],ka,kb,'ontological','eternal',reality,'axiomatic',0),
-- relation is already seeded; relation_type is its subtype
(p_subtype_of, ARRAY[o_relation_type, o_relation], ka,kb,'ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_proposition,   o_abstract], ka,kb,'ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_information,   o_abstract], ka,kb,'ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_knowledge_st,  o_information],ka,kb,'ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_norm,          o_abstract], ka,kb,'ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_rule,          o_norm],     ka,kb,'ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_goal,          o_abstract], ka,kb,'ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_role_c,        o_abstract], ka,kb,'ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_symbol,        o_abstract], ka,kb,'ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_language,      o_symbol],   ka,kb,'ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_word,          o_symbol],   ka,kb,'ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_sentence,      o_symbol],   ka,kb,'ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_truth_value,   o_abstract], ka,kb,'ontological','eternal',reality,'axiomatic',0),

-- ── Event / process / state ───────────────────────────────────
-- event_type is abstract (events are not physical objects)
(p_subtype_of, ARRAY[o_event,         o_abstract], ka,kb,'ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_change_event,  o_event],    ka,kb,'ontological','eternal',reality,'axiomatic',0),
-- backbone seeds process ⊂ entity; here we refine: process ⊂ event
(p_subtype_of, ARRAY[o_process,       o_event],    ka,kb,'ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_action,        o_event],    ka,kb,'ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_state_c,       o_abstract], ka,kb,'ontological','eternal',reality,'axiomatic',0),

-- ── Quantity / number hierarchy ───────────────────────────────
(p_subtype_of, ARRAY[o_quantity,      o_abstract], ka,kb,'ontological','eternal',reality,'axiomatic',0),
-- backbone seeds number ⊂ abstract; here we refine: number ⊂ quantity
(p_subtype_of, ARRAY[o_number,        o_quantity], ka,kb,'ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_real,          o_number],   ka,kb,'ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_integer,       o_real],     ka,kb,'ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_natural,       o_integer],  ka,kb,'ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_measurement,   o_quantity], ka,kb,'ontological','eternal',reality,'axiomatic',0),
-- duration: a quantity that measures time; NOT a subtype of time
(p_subtype_of, ARRAY[o_duration,      o_quantity], ka,kb,'ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_unit,          o_abstract], ka,kb,'ontological','eternal',reality,'axiomatic',0),

-- ── Time hierarchy ────────────────────────────────────────────
(p_subtype_of, ARRAY[o_time,          o_abstract], ka,kb,'ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_interval_t,    o_time],     ka,kb,'ontological','eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_point_t,       o_time],     ka,kb,'ontological','eternal',reality,'axiomatic',0)

ON CONFLICT DO NOTHING;

-- ── Truth value membership ─────────────────────────────────────
INSERT INTO statements
    (predicate_id, object_args, belief_alpha, belief_beta,
     interpretation, t_kind, context_id, derivation_type, derivation_depth)
VALUES
(p_is_a, ARRAY[o_true_val,   o_truth_value], ka,kb,'ontological','eternal',reality,'axiomatic',0),
(p_is_a, ARRAY[o_false_val,  o_truth_value], ka,kb,'ontological','eternal',reality,'axiomatic',0),
(p_is_a, ARRAY[o_unknown_val,o_truth_value], ka,kb,'ontological','eternal',reality,'axiomatic',0)
ON CONFLICT DO NOTHING;

-- ═════════════════════════════════════════════════════════════
-- SECTION 13: Disjointness axioms
-- disjoint_with(A, B): no entity can be both an A and a B.
-- Essential for type-violation conflict detection.
-- ═════════════════════════════════════════════════════════════

INSERT INTO statements
    (predicate_id, object_args, belief_alpha, belief_beta,
     interpretation, t_kind, context_id, derivation_type, derivation_depth)
VALUES
-- Abstract vs concrete: nothing is both (foundational)
(p_disjoint_with, ARRAY[o_abstract,   o_concrete],   ka,  kb,  'ontological','eternal',reality,'axiomatic',0),

-- Time vs physical object: a time interval is not a place
(p_disjoint_with, ARRAY[o_time,       o_phys_obj],   ka,  kb,  'ontological','eternal',reality,'axiomatic',0),

-- Numbers vs organisms: no number is alive
(p_disjoint_with, ARRAY[o_number,     o_organism],   ka,  kb,  'ontological','eternal',reality,'axiomatic',0),

-- Persons vs institutions: a person is not an institution
-- (belief < 1.0: sole trader edge case in law)
(p_disjoint_with, ARRAY[o_person,     o_institution],900.0,100.0,'ontological','eternal',reality,'axiomatic',0),

-- Truth values vs persons
(p_disjoint_with, ARRAY[o_truth_value,o_person],     ka,  kb,  'ontological','eternal',reality,'axiomatic',0),

-- Truth values vs numbers
-- (belief < 1.0: in Boolean arithmetic true=1, false=0)
(p_disjoint_with, ARRAY[o_truth_value,o_number],     700.0,300.0,'ontological','eternal',reality,'axiomatic',0),

-- Places vs numbers
(p_disjoint_with, ARRAY[o_place,      o_number],     ka,  kb,  'ontological','eternal',reality,'axiomatic',0),

-- Events vs physical objects: an event is not a thing
(p_disjoint_with, ARRAY[o_event,      o_phys_obj],   ka,  kb,  'ontological','eternal',reality,'axiomatic',0),

-- Propositions vs physical objects
(p_disjoint_with, ARRAY[o_proposition,o_phys_obj],   ka,  kb,  'ontological','eternal',reality,'axiomatic',0),

-- Duration vs time (duration measures time; it is not a temporal entity)
(p_disjoint_with, ARRAY[o_duration,   o_time],       ka,  kb,  'ontological','eternal',reality,'axiomatic',0)

ON CONFLICT DO NOTHING;

-- ═════════════════════════════════════════════════════════════
-- SECTION 14: Logical / modal eternal statements
-- ═════════════════════════════════════════════════════════════

INSERT INTO statements
    (predicate_id, object_args, belief_alpha, belief_beta,
     interpretation, t_kind, context_id, derivation_type, derivation_depth)
VALUES
(p_opposite_of,   ARRAY[o_true_val,  o_false_val],  ka,kb,'ontological','eternal',reality,'axiomatic',0),
(p_different_from,ARRAY[o_true_val,  o_false_val],  ka,kb,'ontological','eternal',reality,'axiomatic',0),
(p_different_from,ARRAY[o_true_val,  o_unknown_val],ka,kb,'ontological','eternal',reality,'axiomatic',0),
(p_different_from,ARRAY[o_false_val, o_unknown_val],ka,kb,'ontological','eternal',reality,'axiomatic',0)
ON CONFLICT DO NOTHING;

-- ── FOL rule statements ───────────────────────────────────────
-- Inference rules encoded as implies(antecedent, consequent)
-- with both args as string literals.
-- object_args = '{}' — satisfies args_nonempty via literal_args.
-- interpretation = 'ontological' (these are logical truths).
-- Not directly queryable via holds_at(); consumed by the
-- reasoning layer / ProbLog compiler.

-- Modal axiom T: necessary(P) → possible(P)
INSERT INTO statements
    (predicate_id, object_args, literal_args, belief_alpha, belief_beta,
     interpretation, t_kind, context_id, derivation_type, derivation_depth)
VALUES (p_implies, '{}'::uuid[],
    '[{"pos":0,"type":"string","value":"necessary(P)"},
      {"pos":1,"type":"string","value":"possible(P)"}]'::jsonb,
    ka,kb,'ontological','eternal',reality,'axiomatic',0);

-- Type rule: is_a(X, integer) → is_a(X, real_number)
INSERT INTO statements
    (predicate_id, object_args, literal_args, belief_alpha, belief_beta,
     interpretation, t_kind, context_id, derivation_type, derivation_depth)
VALUES (p_implies, '{}'::uuid[],
    '[{"pos":0,"type":"string","value":"is_a(X, integer)"},
      {"pos":1,"type":"string","value":"is_a(X, real_number)"}]'::jsonb,
    ka,kb,'ontological','eternal',reality,'axiomatic',0);

-- Type rule: is_a(X, mammal) → is_a(X, animal)
INSERT INTO statements
    (predicate_id, object_args, literal_args, belief_alpha, belief_beta,
     interpretation, t_kind, context_id, derivation_type, derivation_depth)
VALUES (p_implies, '{}'::uuid[],
    '[{"pos":0,"type":"string","value":"is_a(X, mammal)"},
      {"pos":1,"type":"string","value":"is_a(X, animal)"}]'::jsonb,
    ka,kb,'ontological','eternal',reality,'axiomatic',0);

-- Type rule: is_a(X, animal) → is_a(X, organism)
INSERT INTO statements
    (predicate_id, object_args, literal_args, belief_alpha, belief_beta,
     interpretation, t_kind, context_id, derivation_type, derivation_depth)
VALUES (p_implies, '{}'::uuid[],
    '[{"pos":0,"type":"string","value":"is_a(X, animal)"},
      {"pos":1,"type":"string","value":"is_a(X, organism)"}]'::jsonb,
    ka,kb,'ontological','eternal',reality,'axiomatic',0);

-- Mortal rule: is_a(X, person) → mortal(X)
-- NOT eternal — strong empirical generalisation, revisable.
-- alpha=95, beta=5 (mean 0.95). Philosophical edge cases prevent
-- treating this as a logical truth.
INSERT INTO statements
    (predicate_id, object_args, literal_args, belief_alpha, belief_beta,
     interpretation, t_kind, context_id, derivation_type, derivation_depth)
VALUES (p_implies, '{}'::uuid[],
    '[{"pos":0,"type":"string","value":"is_a(X, person)"},
      {"pos":1,"type":"string","value":"mortal(X)"}]'::jsonb,
    95.0, 5.0, 'ontological', 'always', reality, 'axiomatic', 0);

-- Agent rule: is_a(X, person) → capable_of(X, intentional_action)
INSERT INTO statements
    (predicate_id, object_args, literal_args, belief_alpha, belief_beta,
     interpretation, t_kind, context_id, derivation_type, derivation_depth)
VALUES (p_implies, '{}'::uuid[],
    '[{"pos":0,"type":"string","value":"is_a(X, person)"},
      {"pos":1,"type":"string","value":"capable_of(X, intentional_action)"}]'::jsonb,
    90.0, 10.0, 'ontological', 'always', reality, 'axiomatic', 0);

-- Disjoint rule: disjoint_with(A,B) ∧ is_a(X,A) → ¬is_a(X,B)
INSERT INTO statements
    (predicate_id, object_args, literal_args, belief_alpha, belief_beta,
     interpretation, t_kind, context_id, derivation_type, derivation_depth)
VALUES (p_implies, '{}'::uuid[],
    '[{"pos":0,"type":"string","value":"disjoint_with(A,B) ∧ is_a(X,A)"},
      {"pos":1,"type":"string","value":"¬is_a(X,B)"}]'::jsonb,
    ka,kb,'ontological','eternal',reality,'axiomatic',0);

-- ═════════════════════════════════════════════════════════════
-- SECTION 15: Typicality statements (prototype knowledge)
-- Belief < 1.0 by design; typicality is inherently graded.
-- t_kind = 'always' (not eternal: prototypes are revisable).
-- ═════════════════════════════════════════════════════════════

INSERT INTO statements
    (predicate_id, object_args, belief_alpha, belief_beta,
     interpretation, t_kind, context_id, derivation_type, derivation_depth)
VALUES
(p_typical_of, ARRAY[o_person,       o_agent],    90.0,10.0,'ontological','always',reality,'axiomatic',0),
(p_typical_of, ARRAY[o_institution,  o_agent],    60.0,40.0,'ontological','always',reality,'axiomatic',0),
(p_typical_of, ARRAY[o_action,       o_event],    85.0,15.0,'ontological','always',reality,'axiomatic',0),
(p_typical_of, ARRAY[o_process,      o_event],    65.0,35.0,'ontological','always',reality,'axiomatic',0),
(p_typical_of, ARRAY[o_change_event, o_event],    75.0,25.0,'ontological','always',reality,'axiomatic',0),
(p_typical_of, ARRAY[o_region,       o_place],    75.0,25.0,'ontological','always',reality,'axiomatic',0),
(p_typical_of, ARRAY[o_location,     o_place],    70.0,30.0,'ontological','always',reality,'axiomatic',0),
(p_typical_of, ARRAY[o_artifact,     o_phys_obj], 70.0,30.0,'ontological','always',reality,'axiomatic',0),
(p_typical_of, ARRAY[o_rule,         o_norm],     80.0,20.0,'ontological','always',reality,'axiomatic',0),
(p_typical_of, ARRAY[o_word,         o_symbol],   80.0,20.0,'ontological','always',reality,'axiomatic',0)
ON CONFLICT DO NOTHING;

-- ═════════════════════════════════════════════════════════════
-- SECTION 16: Type membership (Beta)
-- Crisp IS-A relationships encoded in type_membership for
-- efficient query without full hierarchy traversal.
-- ═════════════════════════════════════════════════════════════

INSERT INTO type_membership (object_id, type_id, alpha, beta, context_id)
VALUES
(o_person,       o_agent,     ka,    kb,    reality),
(o_person,       o_organism,  ka,    kb,    reality),
(o_institution,  o_agent,     ka,    kb,    reality),
(o_institution,  o_group,     70.0,  30.0,  reality),  -- usually but not always
(o_mammal,       o_animal,    ka,    kb,    reality),
(o_integer,      o_real,      ka,    kb,    reality),
(o_natural,      o_integer,   ka,    kb,    reality),
(o_action,       o_event,     ka,    kb,    reality),
(o_process,      o_event,     ka,    kb,    reality),
(o_change_event, o_event,     ka,    kb,    reality),
(o_artifact,     o_phys_obj,  ka,    kb,    reality),
(o_region,       o_place,     ka,    kb,    reality),
(o_word,         o_symbol,    ka,    kb,    reality),
(o_sentence,     o_symbol,    ka,    kb,    reality),
(o_rule,         o_norm,      ka,    kb,    reality)
ON CONFLICT (object_id, type_id) DO NOTHING;

-- ═════════════════════════════════════════════════════════════
-- SECTION 17: Bulk attestation
-- Link all axiomatic statements to system_kernel.
-- ═════════════════════════════════════════════════════════════

INSERT INTO attestations (statement_id, source_id)
SELECT s.id, sys
FROM statements s
WHERE s.derivation_type = 'axiomatic'
  AND NOT EXISTS (
      SELECT 1 FROM attestations a WHERE a.statement_id = s.id
  );

-- ═════════════════════════════════════════════════════════════
-- SECTION 18: Diagnostic counts
-- ═════════════════════════════════════════════════════════════

RAISE NOTICE 'Basis objects & statements load complete.';
RAISE NOTICE '  entity objects  : %',
    (SELECT count(*) FROM objects WHERE kind = 'entity');
RAISE NOTICE '  context objects : %',
    (SELECT count(*) FROM objects WHERE kind = 'context');
RAISE NOTICE '  axiomatic stmts : %',
    (SELECT count(*) FROM statements WHERE derivation_type = 'axiomatic');
RAISE NOTICE '  subtype_of stmts: %',
    (SELECT count(*) FROM statements s
     WHERE s.predicate_id = stable_uuid('subtype_of','predicate'));
RAISE NOTICE '  disjoint axioms : %',
    (SELECT count(*) FROM statements s
     WHERE s.predicate_id = stable_uuid('disjoint_with','predicate'));
RAISE NOTICE '  type_membership : %',
    (SELECT count(*) FROM type_membership);
RAISE NOTICE '  attestations    : %',
    (SELECT count(*) FROM attestations);

END $$;

COMMIT;

-- ── Verification queries ──────────────────────────────────────

-- Full type hierarchy ordered by parent then child
SELECT
    child.canonical_name  AS child,
    parent.canonical_name AS parent,
    round(sb.belief_mean::numeric, 4) AS belief
FROM statement_belief sb
JOIN statements s   ON s.id  = sb.id
JOIN objects child  ON child.id  = s.object_args[1]
JOIN objects parent ON parent.id = s.object_args[2]
WHERE s.predicate_id = stable_uuid('subtype_of', 'predicate')
ORDER BY parent.canonical_name, child.canonical_name;

-- Disjointness pairs
SELECT
    a.canonical_name AS type_a,
    b.canonical_name AS type_b,
    round(sb.belief_mean::numeric, 4) AS belief
FROM statement_belief sb
JOIN statements s ON s.id = sb.id
JOIN objects a ON a.id = s.object_args[1]
JOIN objects b ON b.id = s.object_args[2]
WHERE s.predicate_id = stable_uuid('disjoint_with', 'predicate')
ORDER BY type_a, type_b;

-- Domain contexts
SELECT canonical_name, display_name
FROM objects
WHERE kind = 'context'
ORDER BY canonical_name;

-- =============================================================
-- MIGRATION NOTE (if upgrading from v3 kernel):
-- The v3 kernel used stable_uuid(name, 'concept') for all type
-- objects and stored them with kind='concept'.  The v0.5 schema
-- drops kind='concept'.  To migrate:
--
--   UPDATE objects
--      SET kind = 'entity'
--    WHERE kind = 'concept';
--
-- UUID collisions will occur where a v3 'concept' object has the
-- same canonical_name as a v0.5 backbone 'entity' object.
-- Resolve by:
--   1. Identifying pairs:
--      SELECT o3.id, o3.canonical_name, o5.id
--      FROM objects o3
--      JOIN objects o5 ON o5.canonical_name = o3.canonical_name
--                     AND o5.kind = 'entity'
--      WHERE o3.kind = 'concept';  -- already migrated above
--   2. Repointing all FKs (object_args, type_membership, etc.)
--      from the old 'concept' UUID to the 'entity' UUID.
--   3. Deleting the now-duplicate 'entity' row with the old UUID.
-- =============================================================

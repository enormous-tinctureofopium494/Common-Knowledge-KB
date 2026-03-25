-- =============================================================
-- Common Knowledge KB — Kernel Objects & Statements  (v0.3)
-- =============================================================
-- Populates the foundational layer of the KB:
--
--   1. Abstract concept objects — the types and categories that
--      basis predicates reference as argument kinds.
--
--   2. Type hierarchy — subtype_of relations forming the ontology
--      skeleton. All eternal, near-certain belief.
--
--   3. Disjointness axioms — pairs of types that share no
--      instances; feeds the conflict detector.
--
--   4. Logical / modal eternal truths — opposite_of, implies,
--      necessary/possible, Boolean primitives.
--
--   5. Domain context objects — named domains for source
--      credibility scoping.
--
--   6. Typicality statements — graded prototype knowledge.
--
--   7. Attestations — bulk-link all axiomatic statements to
--      system_kernel source.
--
-- Changes from v2:
--   • All UUIDs use stable_uuid(name, kind) — deterministic
--     across fresh installs.  No runtime predicate lookups.
--   • arg_types removed from statement INSERTs — now lives on
--     predicates table (schema v3).
--   • type_membership uses alpha/beta columns, not probability.
--   • held_office references removed entirely.
--   • New concept objects added:
--       artifact, role, rule, boundary, attribute,
--       change_event, biological_taxon, information,
--       knowledge_state, goal, norm, relation_type
--   • Disjointness axioms added (Section 12) using disjoint_with.
--   • has_value predicate used for truth-value property statements.
--   • duration is NOT a subtype of time — it is a subtype of
--     quantity (duration measures time, it is not time itself).
--     This was an error in v2.
--   • implies statements with string-literal FOL fragments are
--     kept but explicitly marked as non-queryable documentation.
--
-- What is NOT here:
--   • Named individuals (specific persons, places, events).
--   • Contingent or time-bounded facts.
--   • Anything requiring a source other than system_kernel.
--
-- All statements use:
--   belief_alpha = 1000.0, belief_beta = 0.001  (near-certain)
--   t_kind       = 'eternal'   (unless noted)
--   derivation_type = 'axiomatic'
-- =============================================================

BEGIN;

DO $$
DECLARE
    -- ── Fixed IDs from schema seed ────────────────────────────
    reality  uuid := stable_uuid('reality',       'context');
    sys      uuid := stable_uuid('system_kernel', 'source');

    -- ── Predicate IDs — computed, not looked up at runtime ───
    -- This relies on the same stable_uuid() call used in the
    -- predicate kernel.  No SELECT needed; fails fast if wrong.
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
    ka   double precision := 1000.0;  -- alpha: near-certain
    kb   double precision := 0.001;   -- beta:  near-certain

    -- ── Object IDs — all stable ───────────────────────────────
    -- Top level
    o_entity        uuid := stable_uuid('entity',           'concept');
    o_abstract      uuid := stable_uuid('abstract_thing',   'concept');
    o_physical      uuid := stable_uuid('physical_thing',   'concept');

    -- Animate / social
    o_organism      uuid := stable_uuid('organism',         'concept');
    o_biological_taxon uuid := stable_uuid('biological_taxon','concept');
    o_animal        uuid := stable_uuid('animal',           'concept');
    o_mammal        uuid := stable_uuid('mammal',           'concept');
    o_person        uuid := stable_uuid('person',           'concept');
    o_agent         uuid := stable_uuid('agent',            'concept');
    o_institution   uuid := stable_uuid('institution',      'concept');
    o_group         uuid := stable_uuid('group',            'concept');

    -- Abstract
    o_concept       uuid := stable_uuid('concept_type',     'concept');
    o_property_c    uuid := stable_uuid('property',         'concept');
    o_attribute     uuid := stable_uuid('attribute',        'concept');
    o_relation_c    uuid := stable_uuid('relation',         'concept');
    o_relation_type uuid := stable_uuid('relation_type',    'concept');
    o_proposition   uuid := stable_uuid('proposition',      'concept');
    o_information   uuid := stable_uuid('information',      'concept');
    o_knowledge_st  uuid := stable_uuid('knowledge_state',  'concept');
    o_norm          uuid := stable_uuid('norm',             'concept');
    o_rule          uuid := stable_uuid('rule',             'concept');
    o_goal          uuid := stable_uuid('goal',             'concept');
    o_role_c        uuid := stable_uuid('role',             'concept');

    -- Events / processes
    o_event         uuid := stable_uuid('event_type',       'concept');
    o_process       uuid := stable_uuid('process',          'concept');
    o_state_c       uuid := stable_uuid('state',            'concept');
    o_action        uuid := stable_uuid('action',           'concept');
    o_change_event  uuid := stable_uuid('change_event',     'concept');

    -- Physical subtypes
    o_phys_obj      uuid := stable_uuid('physical_object',  'concept');
    o_artifact      uuid := stable_uuid('artifact',         'concept');
    o_place         uuid := stable_uuid('place',            'concept');
    o_region        uuid := stable_uuid('region',           'concept');
    o_location      uuid := stable_uuid('location',         'concept');
    o_boundary      uuid := stable_uuid('boundary',         'concept');

    -- Quantities and numbers
    o_quantity      uuid := stable_uuid('quantity',         'concept');
    o_number        uuid := stable_uuid('number',           'concept');
    o_real          uuid := stable_uuid('real_number',      'concept');
    o_integer       uuid := stable_uuid('integer',          'concept');
    o_natural       uuid := stable_uuid('natural_number',   'concept');
    o_unit          uuid := stable_uuid('unit_of_measure',  'concept');
    o_measurement   uuid := stable_uuid('measurement',      'concept');

    -- Time
    o_time          uuid := stable_uuid('time',             'concept');
    o_interval_t    uuid := stable_uuid('time_interval',    'concept');
    o_point_t       uuid := stable_uuid('time_point',       'concept');
    o_duration      uuid := stable_uuid('duration',         'concept');

    -- Language / representation
    o_symbol        uuid := stable_uuid('symbol',           'concept');
    o_language      uuid := stable_uuid('language',         'concept');
    o_word          uuid := stable_uuid('word',             'concept');
    o_sentence      uuid := stable_uuid('sentence',         'concept');

    -- Truth values (true/false/unknown already in schema seed as 'concept')
    o_truth_value   uuid := stable_uuid('truth_value',      'concept');
    o_true_val      uuid := stable_uuid('true',             'concept');
    o_false_val     uuid := stable_uuid('false',            'concept');
    o_unknown_val   uuid := stable_uuid('unknown',          'concept');

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
-- SECTION 1: Sanity check — predicates must already be loaded
-- ═════════════════════════════════════════════════════════════
IF NOT EXISTS (SELECT 1 FROM objects WHERE id = p_is_a AND kind = 'predicate') THEN
    RAISE EXCEPTION
        'Basis predicates not found (expected is_a at %).  '
        'Run common_predicates_kernel.sql before this file.',
        p_is_a;
END IF;

-- ═════════════════════════════════════════════════════════════
-- SECTION 2: Top-level concept objects
-- ═════════════════════════════════════════════════════════════

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_entity,'concept','entity','Entity',
 'Anything that exists or can be referred to. Absolute top of the object hierarchy.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_abstract,'concept','abstract_thing','Abstract thing',
 'An entity with no direct physical instantiation: concepts, numbers, propositions, rules.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_physical,'concept','physical_thing','Physical thing',
 'An entity that occupies or is located in physical space and time.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

-- ═════════════════════════════════════════════════════════════
-- SECTION 3: Animate / social concepts
-- ═════════════════════════════════════════════════════════════

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_biological_taxon,'concept','biological_taxon','Biological taxon',
 'A named group in a biological classification system (species, genus, family, …).')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_organism,'concept','organism','Organism',
 'A living entity: plant, animal, fungus, microbe.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_animal,'concept','animal','Animal',
 'A multicellular organism of the kingdom Animalia.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_mammal,'concept','mammal','Mammal',
 'A warm-blooded vertebrate of class Mammalia; nurses young with milk.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_person,'concept','person','Person',
 'A human individual. Subtype of mammal and agent.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_agent,'concept','agent','Agent',
 'An entity capable of intentional action. Persons and institutions are agents.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_institution,'concept','institution','Institution',
 'An organisation, government, company, or structured social entity. A kind of agent.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_group,'concept','group','Group',
 'A collection of entities treated as a unit. Not necessarily an agent.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

-- ═════════════════════════════════════════════════════════════
-- SECTION 4: Abstract concepts
-- ═════════════════════════════════════════════════════════════

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_concept,'concept','concept_type','Concept',
 'An abstract idea, category, or mental representation.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_property_c,'concept','property','Property',
 'An attribute or characteristic that an entity can have; a unary predicate.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_attribute,'concept','attribute','Attribute',
 'A named feature of an entity that takes a value.  '
 'Distinct from property: attributes have values; properties are Boolean.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_relation_c,'concept','relation','Relation',
 'A predicate taking two or more arguments; describes how entities stand to each other.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_relation_type,'concept','relation_type','Relation type',
 'A type of relation in the predicate vocabulary (e.g., subtype_of, causes).')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_proposition,'concept','proposition','Proposition',
 'A statement that is either true or false in some context.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_information,'concept','information','Information',
 'Structured content that can be communicated or encoded.  '
 'Distinct from knowledge: information does not require a knowing agent.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_knowledge_st,'concept','knowledge_state','Knowledge state',
 'The set of propositions an agent takes to be true at a time.  '
 'Argument type for knows() and believes().')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_norm,'concept','norm','Norm',
 'A standard, obligation, or expectation governing behaviour in a context.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_rule,'concept','rule','Rule',
 'A formal or informal prescription specifying what should happen under a condition.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_goal,'concept','goal','Goal',
 'A desired state or outcome that an agent is motivated to bring about.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_role_c,'concept','role','Role',
 'A position, function, or capacity that an entity occupies within a scope.  '
 'Second argument of has_role(entity, role, scope).')
ON CONFLICT (canonical_name,kind) DO NOTHING;

-- ═════════════════════════════════════════════════════════════
-- SECTION 5: Event / process / state concepts
-- ═════════════════════════════════════════════════════════════

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_event,'concept','event_type','Event',
 'A change or occurrence at a time, involving participants.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_change_event,'concept','change_event','Change event',
 'An event in which some property or state transitions from one value to another.  '
 'Core to Event Calculus: initiates() and terminates() apply to change_events.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_process,'concept','process','Process',
 'An extended event with internal temporal structure; a subtype of event.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_state_c,'concept','state','State',
 'A condition that persists over a time interval without requiring ongoing action.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_action,'concept','action','Action',
 'An event intentionally performed by an agent.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

-- ═════════════════════════════════════════════════════════════
-- SECTION 6: Physical / spatial concepts
-- ═════════════════════════════════════════════════════════════

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_phys_obj,'concept','physical_object','Physical object',
 'A bounded physical entity: tool, artifact, natural body.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_artifact,'concept','artifact','Artifact',
 'A physical object made or modified by an agent for a purpose.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_place,'concept','place','Place',
 'A location or region in physical space.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_region,'concept','region','Region',
 'An extended area of space, possibly with administrative or natural boundaries.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_location,'concept','location','Location',
 'A specific point or area used to describe where something is.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_boundary,'concept','boundary','Boundary',
 'The interface or limit between two regions or entities.  '
 'Part of a region without being a region itself.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

-- ═════════════════════════════════════════════════════════════
-- SECTION 7: Quantities and measurement
-- ═════════════════════════════════════════════════════════════

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_quantity,'concept','quantity','Quantity',
 'A measurable or countable amount.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_number,'concept','number','Number',
 'An abstract mathematical quantity.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_real,'concept','real_number','Real number',
 'A number on the continuous number line, including irrationals and transcendentals.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_integer,'concept','integer','Integer',
 'A whole number: …−2, −1, 0, 1, 2…  A subtype of real_number.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_natural,'concept','natural_number','Natural number',
 'A non-negative integer: 0, 1, 2, 3…  Convention here includes 0.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_unit,'concept','unit_of_measure','Unit of measure',
 'A standard quantity used to express a measurement (metre, kilogram, second, …).')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_measurement,'concept','measurement','Measurement',
 'A quantity expressed in a specific unit; a pairing of number and unit.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

-- ═════════════════════════════════════════════════════════════
-- SECTION 8: Time concepts
-- Note: duration is a quantity (it measures time), not a subtype
-- of time.  time_interval and time_point are subtypes of time.
-- ═════════════════════════════════════════════════════════════

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_time,'concept','time','Time',
 'The dimension along which events are ordered; the abstract type for temporal entities.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_interval_t,'concept','time_interval','Time interval',
 'A bounded span of time with a start and an end.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_point_t,'concept','time_point','Time point',
 'An instantaneous moment in time.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_duration,'concept','duration','Duration',
 'The length of a time interval, expressed as a quantity.  '
 'A duration is NOT a time interval — it is a measure of one.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

-- ═════════════════════════════════════════════════════════════
-- SECTION 9: Language and representation
-- ═════════════════════════════════════════════════════════════

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_symbol,'concept','symbol','Symbol',
 'A sign that represents something else by convention.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_language,'concept','language','Language',
 'A system of communication using symbols according to a grammar.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_word,'concept','word','Word',
 'A minimal free-standing linguistic unit in a language.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_sentence,'concept','sentence','Sentence',
 'A grammatical unit expressing a complete thought or proposition.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

-- ═════════════════════════════════════════════════════════════
-- SECTION 10: Truth values
-- true/false/unknown already exist from schema seed; just add
-- truth_value as their supertype.
-- ═════════════════════════════════════════════════════════════

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_truth_value,'concept','truth_value','Truth value',
 'The type whose instances are true, false, and unknown.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

-- ═════════════════════════════════════════════════════════════
-- SECTION 11: Domain context objects
-- kind='context'; registered in the contexts table below.
-- parent = reality (credibility is relative to the real world).
-- ═════════════════════════════════════════════════════════════

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_dom_history,   'context','domain_history',   'History',
 'Historical facts, events, persons, dates.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_dom_science,   'context','domain_science',   'Science (general)',
 'Scientific facts not specific to one discipline.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_dom_math,      'context','domain_mathematics','Mathematics',
 'Mathematical definitions, theorems, structures.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_dom_geography, 'context','domain_geography', 'Geography',
 'Geographical facts: locations, borders, populations.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_dom_biology,   'context','domain_biology',   'Biology',
 'Biological facts: taxonomy, anatomy, physiology, ecology.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_dom_physics,   'context','domain_physics',   'Physics',
 'Physical laws, constants, and phenomena.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_dom_law,       'context','domain_law',       'Law',
 'Legal facts, statutes, decisions — jurisdiction-sensitive.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_dom_language,  'context','domain_linguistics','Linguistics',
 'Facts about language, grammar, and meaning.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_dom_social,    'context','domain_social',    'Social science',
 'Facts about society, culture, economics, politics.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

INSERT INTO objects (id,kind,canonical_name,display_name,description) VALUES
(o_dom_tech,      'context','domain_technology','Technology',
 'Facts about technology, engineering, computing.')
ON CONFLICT (canonical_name,kind) DO NOTHING;

-- Register domain contexts (child-table row required by orphan-guard trigger)
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
-- SECTION 12: Type hierarchy — subtype_of statements
-- All eternal, near-certain (ka / kb).
-- Note: arg_types is on the predicates table; statements do not
-- repeat it.
-- ═════════════════════════════════════════════════════════════

-- ── Top-level splits ──────────────────────────────────────────
INSERT INTO statements
    (predicate_id, object_args, belief_alpha, belief_beta,
     t_kind, context_id, derivation_type, derivation_depth)
VALUES
(p_subtype_of, ARRAY[o_abstract,  o_entity],  ka,kb,'eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_physical,  o_entity],  ka,kb,'eternal',reality,'axiomatic',0);

-- ── Abstract subtypes ─────────────────────────────────────────
INSERT INTO statements
    (predicate_id, object_args, belief_alpha, belief_beta,
     t_kind, context_id, derivation_type, derivation_depth)
VALUES
(p_subtype_of, ARRAY[o_concept,      o_abstract],  ka,kb,'eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_property_c,   o_abstract],  ka,kb,'eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_attribute,    o_property_c],ka,kb,'eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_relation_c,   o_abstract],  ka,kb,'eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_relation_type,o_relation_c],ka,kb,'eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_proposition,  o_abstract],  ka,kb,'eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_information,  o_abstract],  ka,kb,'eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_knowledge_st, o_information],ka,kb,'eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_norm,         o_abstract],  ka,kb,'eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_rule,         o_norm],      ka,kb,'eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_goal,         o_abstract],  ka,kb,'eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_role_c,       o_abstract],  ka,kb,'eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_symbol,       o_abstract],  ka,kb,'eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_language,     o_symbol],    ka,kb,'eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_word,         o_symbol],    ka,kb,'eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_sentence,     o_symbol],    ka,kb,'eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_truth_value,  o_abstract],  ka,kb,'eternal',reality,'axiomatic',0);

-- ── Event / process / state ───────────────────────────────────
INSERT INTO statements
    (predicate_id, object_args, belief_alpha, belief_beta,
     t_kind, context_id, derivation_type, derivation_depth)
VALUES
(p_subtype_of, ARRAY[o_event,        o_abstract],  ka,kb,'eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_change_event, o_event],     ka,kb,'eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_process,      o_event],     ka,kb,'eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_action,       o_event],     ka,kb,'eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_state_c,      o_abstract],  ka,kb,'eternal',reality,'axiomatic',0);

-- ── Physical subtypes ─────────────────────────────────────────
INSERT INTO statements
    (predicate_id, object_args, belief_alpha, belief_beta,
     t_kind, context_id, derivation_type, derivation_depth)
VALUES
(p_subtype_of, ARRAY[o_organism,  o_physical],     ka,kb,'eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_phys_obj,  o_physical],     ka,kb,'eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_artifact,  o_phys_obj],     ka,kb,'eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_place,     o_physical],     ka,kb,'eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_region,    o_place],        ka,kb,'eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_location,  o_place],        ka,kb,'eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_boundary,  o_abstract],     ka,kb,'eternal',reality,'axiomatic',0);

-- ── Animate hierarchy ─────────────────────────────────────────
INSERT INTO statements
    (predicate_id, object_args, belief_alpha, belief_beta,
     t_kind, context_id, derivation_type, derivation_depth)
VALUES
(p_subtype_of, ARRAY[o_biological_taxon, o_concept], ka,kb,'eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_animal,   o_organism],      ka,kb,'eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_mammal,   o_animal],        ka,kb,'eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_person,   o_mammal],        ka,kb,'eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_person,   o_agent],         ka,kb,'eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_agent,    o_entity],        ka,kb,'eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_institution, o_agent],      ka,kb,'eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_group,    o_entity],        ka,kb,'eternal',reality,'axiomatic',0);

-- ── Quantity / number hierarchy ───────────────────────────────
INSERT INTO statements
    (predicate_id, object_args, belief_alpha, belief_beta,
     t_kind, context_id, derivation_type, derivation_depth)
VALUES
(p_subtype_of, ARRAY[o_quantity,   o_abstract],    ka,kb,'eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_number,     o_quantity],    ka,kb,'eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_real,       o_number],      ka,kb,'eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_integer,    o_real],        ka,kb,'eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_natural,    o_integer],     ka,kb,'eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_measurement,o_quantity],    ka,kb,'eternal',reality,'axiomatic',0),
-- duration: a quantity that measures a time interval, not a time itself
(p_subtype_of, ARRAY[o_duration,   o_quantity],    ka,kb,'eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_unit,       o_abstract],    ka,kb,'eternal',reality,'axiomatic',0);

-- ── Time hierarchy ────────────────────────────────────────────
INSERT INTO statements
    (predicate_id, object_args, belief_alpha, belief_beta,
     t_kind, context_id, derivation_type, derivation_depth)
VALUES
(p_subtype_of, ARRAY[o_time,       o_abstract],    ka,kb,'eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_interval_t, o_time],        ka,kb,'eternal',reality,'axiomatic',0),
(p_subtype_of, ARRAY[o_point_t,    o_time],        ka,kb,'eternal',reality,'axiomatic',0);
-- duration is NOT a subtype of time; it is a subtype of quantity (above).

-- ── Truth value membership ────────────────────────────────────
INSERT INTO statements
    (predicate_id, object_args, belief_alpha, belief_beta,
     t_kind, context_id, derivation_type, derivation_depth)
VALUES
(p_is_a, ARRAY[o_true_val,  o_truth_value], ka,kb,'eternal',reality,'axiomatic',0),
(p_is_a, ARRAY[o_false_val, o_truth_value], ka,kb,'eternal',reality,'axiomatic',0),
(p_is_a, ARRAY[o_unknown_val,o_truth_value],ka,kb,'eternal',reality,'axiomatic',0);

-- ═════════════════════════════════════════════════════════════
-- SECTION 13: Disjointness axioms
-- disjoint_with(A, B) means no entity can be both an A and a B.
-- These are essential for type-violation conflict detection.
-- Encoded as eternal, near-certain.
-- ═════════════════════════════════════════════════════════════

INSERT INTO statements
    (predicate_id, object_args, belief_alpha, belief_beta,
     t_kind, context_id, derivation_type, derivation_depth)
VALUES
-- Physical vs abstract: nothing is both
(p_disjoint_with, ARRAY[o_physical,  o_abstract],  ka,kb,'eternal',reality,'axiomatic',0),

-- Time vs physical object: a time interval is not a place
(p_disjoint_with, ARRAY[o_time,      o_phys_obj],  ka,kb,'eternal',reality,'axiomatic',0),

-- Numbers vs organisms: no number is alive
(p_disjoint_with, ARRAY[o_number,    o_organism],  ka,kb,'eternal',reality,'axiomatic',0),

-- Persons vs institutions: a person is not an institution
-- (belief < 1.0: edge cases exist, e.g. a sole trader legally IS the company)
(p_disjoint_with, ARRAY[o_person,    o_institution],900.0,100.0,'eternal',reality,'axiomatic',0),

-- Truth values vs persons: true/false are not people
(p_disjoint_with, ARRAY[o_truth_value, o_person],  ka,kb,'eternal',reality,'axiomatic',0),

-- Truth values vs numbers: true/false are not numbers
-- (belief < 1.0: in Boolean arithmetic true=1, false=0 — valid in context)
(p_disjoint_with, ARRAY[o_truth_value, o_number],  700.0,300.0,'eternal',reality,'axiomatic',0),

-- Places vs numbers: geography and arithmetic don't overlap
(p_disjoint_with, ARRAY[o_place,     o_number],    ka,kb,'eternal',reality,'axiomatic',0),

-- Events vs physical objects: an event is not a thing
(p_disjoint_with, ARRAY[o_event,     o_phys_obj],  ka,kb,'eternal',reality,'axiomatic',0),

-- Propositions vs physical objects
(p_disjoint_with, ARRAY[o_proposition,o_phys_obj], ka,kb,'eternal',reality,'axiomatic',0);

-- ═════════════════════════════════════════════════════════════
-- SECTION 14: Logical and modal eternal statements
-- ═════════════════════════════════════════════════════════════

-- true and false are opposites and distinct
INSERT INTO statements
    (predicate_id, object_args, belief_alpha, belief_beta,
     t_kind, context_id, derivation_type, derivation_depth)
VALUES
(p_opposite_of,   ARRAY[o_true_val,  o_false_val], ka,kb,'eternal',reality,'axiomatic',0),
(p_different_from,ARRAY[o_true_val,  o_false_val], ka,kb,'eternal',reality,'axiomatic',0),
(p_different_from,ARRAY[o_true_val,  o_unknown_val],ka,kb,'eternal',reality,'axiomatic',0),
(p_different_from,ARRAY[o_false_val, o_unknown_val],ka,kb,'eternal',reality,'axiomatic',0);

-- ── FOL rule statements ───────────────────────────────────────
-- These encode inference rules as propositions with string literal args.
-- They are documentation-level: not directly queryable via holds_at(),
-- but readable by the ProbLog compiler and the NL interface.
-- Format: implies(antecedent_FOL_string, consequent_FOL_string)
-- using object_args=[] and two string literal_args at pos 0 and 1.

-- Modal axiom T: necessary(P) → possible(P)
INSERT INTO statements
    (predicate_id, object_args, literal_args,
     belief_alpha, belief_beta, t_kind, context_id,
     derivation_type, derivation_depth)
VALUES (p_implies, ARRAY[]::uuid[],
 '[{"pos":0,"type":"string","value":"necessary(P)"},
   {"pos":1,"type":"string","value":"possible(P)"}]'::jsonb,
 ka,kb,'eternal',reality,'axiomatic',0);

-- Type rule: is_a(X, integer) → is_a(X, real_number)
INSERT INTO statements
    (predicate_id, object_args, literal_args,
     belief_alpha, belief_beta, t_kind, context_id,
     derivation_type, derivation_depth)
VALUES (p_implies, ARRAY[]::uuid[],
 '[{"pos":0,"type":"string","value":"is_a(X, integer)"},
   {"pos":1,"type":"string","value":"is_a(X, real_number)"}]'::jsonb,
 ka,kb,'eternal',reality,'axiomatic',0);

-- Type rule: is_a(X, mammal) → is_a(X, animal)
INSERT INTO statements
    (predicate_id, object_args, literal_args,
     belief_alpha, belief_beta, t_kind, context_id,
     derivation_type, derivation_depth)
VALUES (p_implies, ARRAY[]::uuid[],
 '[{"pos":0,"type":"string","value":"is_a(X, mammal)"},
   {"pos":1,"type":"string","value":"is_a(X, animal)"}]'::jsonb,
 ka,kb,'eternal',reality,'axiomatic',0);

-- Type rule: is_a(X, animal) → is_a(X, organism) [upward closure]
INSERT INTO statements
    (predicate_id, object_args, literal_args,
     belief_alpha, belief_beta, t_kind, context_id,
     derivation_type, derivation_depth)
VALUES (p_implies, ARRAY[]::uuid[],
 '[{"pos":0,"type":"string","value":"is_a(X, animal)"},
   {"pos":1,"type":"string","value":"is_a(X, organism)"}]'::jsonb,
 ka,kb,'eternal',reality,'axiomatic',0);

-- Mortal rule: is_a(X, person) → mortal(X)
-- NOT eternal — a strong empirical generalisation, revisable.
-- alpha=95, beta=5: mean 0.95.  Philosophical edge cases (uploaded minds,
-- hypothetical immortality) prevent this being treated as logical truth.
INSERT INTO statements
    (predicate_id, object_args, literal_args,
     belief_alpha, belief_beta, t_kind, context_id,
     derivation_type, derivation_depth)
VALUES (p_implies, ARRAY[]::uuid[],
 '[{"pos":0,"type":"string","value":"is_a(X, person)"},
   {"pos":1,"type":"string","value":"mortal(X)"}]'::jsonb,
 95.0, 5.0, 'always', reality, 'axiomatic', 0);

-- Agent rule: is_a(X, person) → capable_of(X, intentional_action)
INSERT INTO statements
    (predicate_id, object_args, literal_args,
     belief_alpha, belief_beta, t_kind, context_id,
     derivation_type, derivation_depth)
VALUES (p_implies, ARRAY[]::uuid[],
 '[{"pos":0,"type":"string","value":"is_a(X, person)"},
   {"pos":1,"type":"string","value":"capable_of(X, intentional_action)"}]'::jsonb,
 90.0, 10.0, 'always', reality, 'axiomatic', 0);

-- Disjoint rule: disjoint_with(A,B) ∧ is_a(X,A) → ¬is_a(X,B)
INSERT INTO statements
    (predicate_id, object_args, literal_args,
     belief_alpha, belief_beta, t_kind, context_id,
     derivation_type, derivation_depth)
VALUES (p_implies, ARRAY[]::uuid[],
 '[{"pos":0,"type":"string","value":"disjoint_with(A,B) ∧ is_a(X,A)"},
   {"pos":1,"type":"string","value":"¬is_a(X,B)"}]'::jsonb,
 ka,kb,'eternal',reality,'axiomatic',0);

-- ═════════════════════════════════════════════════════════════
-- SECTION 15: Typicality statements (prototype knowledge)
-- Belief < 1.0 by design; typicality is inherently graded.
-- t_kind = 'always' (not eternal: prototypes are revisable).
-- ═════════════════════════════════════════════════════════════

INSERT INTO statements
    (predicate_id, object_args, belief_alpha, belief_beta,
     t_kind, context_id, derivation_type, derivation_depth)
VALUES
-- Persons are highly typical agents
(p_typical_of, ARRAY[o_person,      o_agent],     90.0,10.0,'always',reality,'axiomatic',0),
-- Institutions are less typical agents (they act, but not like persons)
(p_typical_of, ARRAY[o_institution, o_agent],     60.0,40.0,'always',reality,'axiomatic',0),
-- Actions are the clearest kind of events
(p_typical_of, ARRAY[o_action,      o_event],     85.0,15.0,'always',reality,'axiomatic',0),
-- Processes are typical events but less bounded
(p_typical_of, ARRAY[o_process,     o_event],     65.0,35.0,'always',reality,'axiomatic',0),
-- Change events are typical events (they are what events most often are)
(p_typical_of, ARRAY[o_change_event,o_event],     75.0,25.0,'always',reality,'axiomatic',0),
-- Regions are typical places
(p_typical_of, ARRAY[o_region,      o_place],     75.0,25.0,'always',reality,'axiomatic',0),
-- Locations are typical places (more specific than regions)
(p_typical_of, ARRAY[o_location,    o_place],     70.0,30.0,'always',reality,'axiomatic',0),
-- Artifacts are typical physical objects (for human-centred reasoning)
(p_typical_of, ARRAY[o_artifact,    o_phys_obj],  70.0,30.0,'always',reality,'axiomatic',0),
-- Rules are typical norms
(p_typical_of, ARRAY[o_rule,        o_norm],      80.0,20.0,'always',reality,'axiomatic',0),
-- Words are the most typical symbols in everyday reasoning
(p_typical_of, ARRAY[o_word,        o_symbol],    80.0,20.0,'always',reality,'axiomatic',0);

-- ═════════════════════════════════════════════════════════════
-- SECTION 16: Type membership (Beta version)
-- Crisp IS-A relationships encoded as type_membership for query
-- convenience.  alpha/beta: high = certain membership.
-- ═════════════════════════════════════════════════════════════

INSERT INTO type_membership (object_id, type_id, alpha, beta, context_id)
VALUES
(o_person,      o_agent,       ka, kb, reality),
(o_person,      o_organism,    ka, kb, reality),
(o_institution, o_agent,       ka, kb, reality),
-- institutions are usually but not always groups
(o_institution, o_group,       70.0, 30.0, reality),
(o_mammal,      o_animal,      ka, kb, reality),
(o_integer,     o_real,        ka, kb, reality),
(o_natural,     o_integer,     ka, kb, reality),
(o_action,      o_event,       ka, kb, reality),
(o_process,     o_event,       ka, kb, reality),
(o_change_event,o_event,       ka, kb, reality),
(o_artifact,    o_phys_obj,    ka, kb, reality),
(o_region,      o_place,       ka, kb, reality),
(o_word,        o_symbol,      ka, kb, reality),
(o_sentence,    o_symbol,      ka, kb, reality),
(o_rule,        o_norm,        ka, kb, reality)
ON CONFLICT (object_id, type_id) DO NOTHING;

-- ═════════════════════════════════════════════════════════════
-- SECTION 17: Bulk attestation — link all axiomatic statements
-- to system_kernel source.
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

RAISE NOTICE 'Kernel load complete.';
RAISE NOTICE '  concept objects : %',
    (SELECT count(*) FROM objects WHERE kind = 'concept');
RAISE NOTICE '  context objects : %',
    (SELECT count(*) FROM objects WHERE kind = 'context');
RAISE NOTICE '  axiomatic stmts : %',
    (SELECT count(*) FROM statements WHERE derivation_type = 'axiomatic');
RAISE NOTICE '  disjoint axioms : %',
    (SELECT count(*) FROM statements s
     JOIN objects p ON p.id = s.predicate_id
     WHERE p.canonical_name = 'disjoint_with');
RAISE NOTICE '  attestations    : %',
    (SELECT count(*) FROM attestations);

END $$;

COMMIT;

-- ── Verification queries ──────────────────────────────────────

-- Full type hierarchy ordered by parent then child
SELECT
    child.canonical_name   AS child,
    parent.canonical_name  AS parent,
    round(sb.mean::numeric, 4) AS belief
FROM statement_belief sb
JOIN statements s  ON s.id  = sb.id
JOIN objects child  ON child.id  = s.object_args[1]
JOIN objects parent ON parent.id = s.object_args[2]
WHERE s.predicate_id = stable_uuid('subtype_of', 'predicate')
ORDER BY parent.canonical_name, child.canonical_name;

-- Disjointness pairs
SELECT
    a.canonical_name AS type_a,
    b.canonical_name AS type_b,
    round(sb.mean::numeric, 4) AS belief
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

-- =============================================================
-- Common Knowledge KB — Basis Predicate Kernel  (v0.3)
-- =============================================================
-- 57 basis predicates across 13 groups.
--
-- Changes from v2:
--   • All UUIDs generated via stable_uuid(canonical_name,'predicate')
--     — deterministic across fresh installs, safe to reference from
--     other files without hardcoding hex strings.
--   • held_office REMOVED — domain-specific, not a basis predicate.
--     Replaced by has_role(entity, role, scope) [ternary, Group 6].
--   • Copula split: is_a (instance-of) is kept as a primitive, but
--     its four historically conflated senses are now explicit:
--       – is_a          → classification   (Socrates is_a mortal)
--       – same_as       → identity         (already existed)
--       – has_property  → predication      (already existed)
--       – typical_of    → prototypicality  (already existed, Group 12)
--       – has_role      → role/state       (new, Group 6)
--     DO NOT use is_a to express role, state, or typicality.
--     DO NOT express "X is Y" as is_a without checking which sense
--     of the copula is intended.
--   • Arity annotations: predicates are tagged as intransitive (1),
--     transitive (2), or bitransitive (3).  "Bitransitive" means a
--     third argument is obligatory for full disambiguation; these are
--     marked arity=3.  Where a third argument is useful but optional
--     in practice, arity=2 is kept with a comment.
--       Genuinely ternary (new or promoted):
--         has_role(entity, role, scope)         — replaces held_office
--         causes(cause, effect, mechanism)      — promoted from binary
--         located_in(entity, place, time)       — promoted from binary
--         affiliated_with(entity, org, role)    — promoted from binary
--         transferred_to(thing, source, target) — new
--   • Group 11 (physical/lifecycle) trimmed: born_in / died_in
--     demoted from basis — they are shorthand composites, not
--     primitives.  Replaced by has_role + temporal scope on located_in.
--   • New Group 13: STRUCTURAL / LOGICAL (3 predicates)
--     equivalent_to, disjoint_with, has_value
--   • arg_types array now populated on every predicate (moved from
--     statements to predicates in schema v3).
--
-- Arity vocabulary used in comments:
--   intransitive  (1 arg)  — unary;  e.g. possible(P)
--   transitive    (2 args) — binary; e.g. part_of(X, Y)
--   bitransitive  (3 args) — ternary; third arg disambiguates fully
--
-- On the copula ("to be"):
--   Natural languages conflate identity, classification, predication,
--   role, and exemplification into one verb.  This KB does not.
--   If you find yourself reaching for is_a, ask: which sense?
--     identity?       → same_as
--     instance-of?    → is_a
--     property?       → has_property
--     role/office?    → has_role
--     typical member? → typical_of
--   Conflating these senses is the single most common source of
--   inference errors in large knowledge bases.
-- =============================================================

BEGIN;

DO $$
DECLARE
    sys uuid := stable_uuid('system_kernel', 'source');
    oid uuid;
BEGIN

-- ════════════════════════════════════════════════════════════
-- GROUP 1: TAXONOMIC / TYPE  (5)
-- Predicates about classification and identity.
-- is_a = instance-of only.  See copula note above.
-- ════════════════════════════════════════════════════════════

-- intransitive-ish but treated as transitive:
-- is_a(instance, type) — crisp set membership.
-- NOT for typicality (→ typical_of), roles (→ has_role), or identity (→ same_as).
oid := stable_uuid('is_a', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','is_a','is a',
'x is an instance of type y (crisp classification only).
Do NOT use for role, state, property, typicality, or identity.')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,
  ARRAY['concept','concept']::object_kind[],
  ARRAY['instance','type'],
  ARRAY['object','object'],
  'primitive',
  'x is an instance of y',
  'rdf:type / wikidata:P31',
  true,ARRAY['taxonomic'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;

-- subtype_of(subtype, supertype) — transitive, asymmetric.
oid := stable_uuid('subtype_of', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','subtype_of','subtype of',
'Every instance of x is also an instance of y.')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,
  ARRAY['concept','concept']::object_kind[],
  ARRAY['subtype','supertype'],
  ARRAY['object','object'],
  'subtype_of(X,Y) :- forall Z, is_a(Z,X) -> is_a(Z,Y)',
  'x is a subtype of y',
  'rdfs:subClassOf',
  true,ARRAY['taxonomic'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;

-- has_property(entity, property) — predication sense of the copula.
-- "The apple is red" → has_property(apple, red).
-- Distinct from is_a: properties are not types you instantiate.
oid := stable_uuid('has_property', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','has_property','has property',
'x has property or attribute y (predication sense of copula).
"The sky is blue" → has_property(sky, blue).')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,NULL,
  ARRAY['entity','property'],
  ARRAY['object','object'],
  'primitive',
  'x has property y',
  'conceptnet:HasProperty',
  true,ARRAY['taxonomic'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;

-- same_as(x, y) — identity sense of the copula.
-- "The morning star is the evening star" → same_as(morning_star, evening_star).
oid := stable_uuid('same_as', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','same_as','same as',
'x and y refer to the same real-world entity (identity, not classification).')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,NULL,
  ARRAY['entity','entity'],
  ARRAY['object','object'],
  'primitive; symmetric; same_as(X,Y) -> same_as(Y,X)',
  'x and y are the same entity',
  'owl:sameAs',
  true,ARRAY['taxonomic'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;

-- different_from(x, y) — explicit non-identity.
oid := stable_uuid('different_from', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','different_from','different from',
'x and y are distinct entities.')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,NULL,
  ARRAY['entity','entity'],
  ARRAY['object','object'],
  'different_from(X,Y) :- not same_as(X,Y)',
  'x and y are not the same entity',
  'owl:differentFrom',
  true,ARRAY['taxonomic'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;


-- ════════════════════════════════════════════════════════════
-- GROUP 2: MEREOLOGY  (4)
-- Transitive part-whole relations.
-- ════════════════════════════════════════════════════════════

-- part_of(part, whole) — transitive, asymmetric.
oid := stable_uuid('part_of', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','part_of','part of',
'x is a component or part of y (transitive).')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,NULL,
  ARRAY['part','whole'],
  ARRAY['object','object'],
  'primitive; transitive; asymmetric',
  'x is a part of y',
  'conceptnet:PartOf / wikidata:P361',
  true,ARRAY['mereology','spatial'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;

-- has_part — inverse of part_of.
oid := stable_uuid('has_part', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','has_part','has part',
'x contains y as a component.')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,NULL,
  ARRAY['whole','part'],
  ARRAY['object','object'],
  'has_part(X,Y) :- part_of(Y,X)',
  'x has y as a part',
  'conceptnet:HasA / wikidata:P527',
  true,ARRAY['mereology','spatial'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;

-- member_of(member, group) — set/group membership, not part-whole.
oid := stable_uuid('member_of', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','member_of','member of',
'x is a member of group or set y (not part-whole; no transitivity assumed).')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,NULL,
  ARRAY['member','group'],
  ARRAY['object','object'],
  'primitive',
  'x is a member of y',
  'wikidata:P463',
  true,ARRAY['mereology','social'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;

-- contains — spatial/abstract containment; converse of part_of in spatial sense.
oid := stable_uuid('contains', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','contains','contains',
'x physically or abstractly contains y.')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,NULL,
  ARRAY['container','contained'],
  ARRAY['object','object'],
  'contains(X,Y) :- part_of(Y,X) [spatial sense]',
  'x contains y',
  NULL,
  true,ARRAY['mereology','spatial'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;


-- ════════════════════════════════════════════════════════════
-- GROUP 3: SPATIAL  (4)
-- located_in is promoted to ternary (bitransitive):
--   located_in(entity, place, time) — third arg is a time or
--   temporal context, because location is often time-indexed.
--   When time is not relevant, use arity-2 form with NULL literal.
-- ════════════════════════════════════════════════════════════

-- located_in(entity, place, time) — bitransitive.
-- "Caesar was in Gaul in 58 BCE" → located_in(caesar, gaul, 58bce).
-- At-a-time is part of the predicate's full meaning; without it you
-- assert a timeless location (appropriate only for geographic facts
-- that don't change, e.g. located_in(london, england, NULL)).
oid := stable_uuid('located_in', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','located_in','located in',
'x is situated within or at location y at time z.
Third arg (time) may be NULL for timeless geographic containment.')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,3,NULL,
  ARRAY['entity','place','time'],
  ARRAY['object','object','object'],
  'primitive',
  'x is located in y at time z',
  'conceptnet:AtLocation / wikidata:P131',
  true,ARRAY['spatial'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;

-- adjacent_to — symmetric, no time arg (topology doesn't change).
oid := stable_uuid('adjacent_to', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','adjacent_to','adjacent to',
'x is spatially next to or bordering y (symmetric).')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,NULL,
  ARRAY['entity','entity'],
  ARRAY['object','object'],
  'primitive; symmetric',
  'x is next to or borders y',
  NULL,
  true,ARRAY['spatial'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;

-- origin_of(source, thing) — place or source from which y comes.
oid := stable_uuid('origin_of', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','origin_of','origin of',
'x is the place, source, or cause from which y originates.')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,NULL,
  ARRAY['concept','entity'],
  ARRAY['object','object'],
  'primitive',
  'x is the origin of y',
  'wikidata:P19 generalised',
  true,ARRAY['spatial','causal'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;

-- transferred_to(thing, source, target) — bitransitive.
-- "The painting was moved from the Louvre to the Met."
-- Covers ownership transfer, physical movement, transmission.
-- Requires all three args for the predicate to be non-ambiguous.
oid := stable_uuid('transferred_to', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','transferred_to','transferred to',
'x moved or was transferred from source y to destination z.
Covers physical movement, ownership, transmission of information.')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,3,NULL,
  ARRAY['thing','source','destination'],
  ARRAY['object','object','object'],
  'primitive; bitransitive',
  'x is transferred from y to z',
  'wikidata:P185 generalised',
  true,ARRAY['spatial','causal','social'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;


-- ════════════════════════════════════════════════════════════
-- GROUP 4: TEMPORAL  (5)
-- Allen interval algebra primitives + has_duration.
-- ════════════════════════════════════════════════════════════

oid := stable_uuid('before', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','before','before',
'Event or time x occurs strictly before y (transitive, asymmetric).')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,
  ARRAY['event','event']::object_kind[],
  ARRAY['earlier','later'],
  ARRAY['object','object'],
  'primitive; transitive; asymmetric',
  'x happens strictly before y',
  'allen:before',
  true,ARRAY['temporal'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;

oid := stable_uuid('after', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','after','after',
'Event or time x occurs strictly after y.')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,
  ARRAY['event','event']::object_kind[],
  ARRAY['later','earlier'],
  ARRAY['object','object'],
  'after(X,Y) :- before(Y,X)',
  'x happens strictly after y',
  'allen:after',
  true,ARRAY['temporal'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;

oid := stable_uuid('during', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','during','during',
'Event x occurs entirely within the time span of event y.')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,
  ARRAY['event','event']::object_kind[],
  ARRAY['contained_event','containing_event'],
  ARRAY['object','object'],
  'primitive (Allen interval relation)',
  'x occurs within the span of y',
  'allen:during',
  true,ARRAY['temporal'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;

oid := stable_uuid('simultaneous_with', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','simultaneous_with','simultaneous with',
'Events x and y occur at the same time (symmetric).')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,
  ARRAY['event','event']::object_kind[],
  ARRAY['event_a','event_b'],
  ARRAY['object','object'],
  'primitive; symmetric',
  'x and y happen at the same time',
  'allen:equals',
  true,ARRAY['temporal'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;

oid := stable_uuid('has_duration', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','has_duration','has duration',
'Event or state x lasts for duration y.')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,NULL,
  ARRAY['event_or_state','quantity'],
  ARRAY['object','object'],
  'primitive',
  'x lasts for duration y',
  'wikidata:P2047',
  true,ARRAY['temporal','quantitative'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;


-- ════════════════════════════════════════════════════════════
-- GROUP 5: CAUSAL / FUNCTIONAL  (6)
-- causes is promoted to ternary (bitransitive):
--   causes(cause, effect, mechanism)
-- Mechanism arg is often unknown; use NULL literal.
-- This prevents conflating proximate and distal causation.
-- ════════════════════════════════════════════════════════════

-- causes(cause, effect, mechanism) — bitransitive.
-- "Smoking causes cancer via carcinogenic compounds."
-- mechanism=NULL is common; the slot exists to avoid conflation.
oid := stable_uuid('causes', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','causes','causes',
'x brings about y via mechanism z.
mechanism (z) may be NULL when unknown or irrelevant.')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,3,NULL,
  ARRAY['cause','effect','mechanism'],
  ARRAY['object','object','object'],
  'primitive; bitransitive',
  'x causes y via mechanism z',
  'conceptnet:Causes',
  true,ARRAY['causal'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;

oid := stable_uuid('enables', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','enables','enables',
'x makes y possible without necessarily causing it.')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,NULL,
  ARRAY['enabler','enabled'],
  ARRAY['object','object'],
  'primitive; weaker than causes',
  'x enables y',
  'conceptnet:Enables',
  true,ARRAY['causal'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;

oid := stable_uuid('prevents', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','prevents','prevents',
'x inhibits or blocks y.')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,NULL,
  ARRAY['preventer','prevented'],
  ARRAY['object','object'],
  'primitive',
  'x prevents y',
  'conceptnet:Obstructs',
  true,ARRAY['causal'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;

oid := stable_uuid('used_for', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','used_for','used for',
'x is typically used to accomplish y.')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,NULL,
  ARRAY['tool','purpose'],
  ARRAY['object','object'],
  'primitive',
  'x is used for y',
  'conceptnet:UsedFor',
  true,ARRAY['causal','functional'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;

oid := stable_uuid('capable_of', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','capable_of','capable of',
'x has the capacity or disposition to do y.')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,NULL,
  ARRAY['agent','action'],
  ARRAY['object','object'],
  'primitive',
  'x is capable of y',
  'conceptnet:CapableOf',
  true,ARRAY['causal','social'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;

oid := stable_uuid('motivated_by', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','motivated_by','motivated by',
'Action x is done because of reason or goal y.')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,NULL,
  ARRAY['action','goal'],
  ARRAY['object','object'],
  'primitive',
  'x is motivated by y',
  'conceptnet:MotivatedByGoal',
  true,ARRAY['causal','social'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;


-- ════════════════════════════════════════════════════════════
-- GROUP 6: AGENTIVE / SOCIAL  (6)
-- held_office is REMOVED.  Replaced by has_role (ternary).
-- affiliated_with promoted to ternary.
-- ════════════════════════════════════════════════════════════

-- agent_of(agent, event) — who performed an action.
oid := stable_uuid('agent_of', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','agent_of','agent of',
'x is the intentional agent who performs action or event y.')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,
  ARRAY['person','event']::object_kind[],
  ARRAY['agent','action'],
  ARRAY['object','object'],
  'primitive',
  'x performs y',
  'wikidata:P664',
  true,ARRAY['social'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;

-- created_by(creation, creator) — authorship or production.
oid := stable_uuid('created_by', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','created_by','created by',
'x was made, authored, or produced by agent y.')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,NULL,
  ARRAY['creation','creator'],
  ARRAY['object','object'],
  'primitive',
  'x was created by y',
  'wikidata:P170 / conceptnet:CreatedBy',
  true,ARRAY['social','causal'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;

-- has_role(entity, role, scope) — bitransitive.
-- Replaces held_office and covers all role/office/position facts.
-- scope = the organisation, context, or domain in which the role is held.
-- "Tyler was president of the USA" →
--   has_role(tyler, president, usa) with t_kind=interval, t_start=1841, t_end=1845
-- "She is chair of the committee" →
--   has_role(she, chair, committee) with t_kind=default
-- scope may be NULL for roles with no institutional scope (e.g. "parent").
oid := stable_uuid('has_role', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','has_role','has role',
'x holds role y within scope z (organisation, domain, or context).
Replaces held_office. Scope may be NULL for informal roles.
This is the role/state sense of the copula: "X is president" →
has_role(X, president, [organisation]).')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,3,NULL,
  ARRAY['entity','role','scope'],
  ARRAY['object','object','object'],
  'primitive; bitransitive; scope may be NULL',
  'x holds role y within z',
  'wikidata:P39 generalised',
  true,ARRAY['social'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;

-- affiliated_with(entity, organisation, role) — bitransitive.
-- "Einstein was affiliated with Princeton as a professor."
-- role arg clarifies the nature of affiliation; may be NULL.
oid := stable_uuid('affiliated_with', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','affiliated_with','affiliated with',
'x is associated with organisation y in capacity z.
capacity (z) may be NULL for generic affiliation.')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,3,NULL,
  ARRAY['entity','organisation','capacity'],
  ARRAY['object','object','object'],
  'primitive; bitransitive',
  'x is affiliated with y in capacity z',
  'wikidata:P108 / P463',
  true,ARRAY['social'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;

-- related_to — symmetric, weakest basis predicate; last resort.
oid := stable_uuid('related_to', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','related_to','related to',
'x and y are related (generic, symmetric).
Use a more specific predicate if one applies.')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,NULL,
  ARRAY['entity','entity'],
  ARRAY['object','object'],
  'primitive; symmetric',
  'x and y are related',
  'conceptnet:RelatedTo',
  true,ARRAY['taxonomic'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;

-- opposite_of — symmetric, conceptual antonymy.
oid := stable_uuid('opposite_of', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','opposite_of','opposite of',
'x is the conceptual opposite or antonym of y (symmetric).')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,NULL,
  ARRAY['concept','concept'],
  ARRAY['object','object'],
  'primitive; symmetric',
  'x is the opposite of y',
  'conceptnet:Antonym',
  true,ARRAY['taxonomic','linguistic'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;


-- ════════════════════════════════════════════════════════════
-- GROUP 7: QUANTITATIVE  (3)
-- ════════════════════════════════════════════════════════════

oid := stable_uuid('has_quantity', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','has_quantity','has quantity',
'x has measurable quantity y (population, mass, length, …).')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,NULL,
  ARRAY['entity','quantity'],
  ARRAY['object','object'],
  'primitive',
  'x has quantity y',
  'wikidata:P1082 etc.',
  true,ARRAY['quantitative'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;

oid := stable_uuid('greater_than', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','greater_than','greater than',
'Quantity x is greater than quantity y (asymmetric, transitive).')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,
  ARRAY['quantity','quantity']::object_kind[],
  ARRAY['larger','smaller'],
  ARRAY['object','object'],
  'primitive; asymmetric; transitive',
  'x > y',
  NULL,
  true,ARRAY['quantitative'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;

oid := stable_uuid('approximately_equal', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','approximately_equal','approximately equal',
'x and y are approximately equal in magnitude (symmetric, fuzzy).')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,NULL,
  ARRAY['entity','entity'],
  ARRAY['object','object'],
  'primitive; symmetric; fuzzy',
  'x ≈ y',
  NULL,
  true,ARRAY['quantitative'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;


-- ════════════════════════════════════════════════════════════
-- GROUP 8: EPISTEMIC / MODAL  (5)
-- Attitudes and modalities.  Intransitive predicates (possible,
-- necessary) take one propositional arg.
-- ════════════════════════════════════════════════════════════

-- knows(agent, fact) — veridical; x knows y → y is true.
oid := stable_uuid('knows', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','knows','knows',
'Agent x has knowledge of fact, concept, or entity y (veridical).')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,
  ARRAY['person','concept']::object_kind[],
  ARRAY['knower','known'],
  ARRAY['object','object'],
  'primitive; knows(X,Y) -> true(Y)',
  'x knows y',
  NULL,
  true,ARRAY['epistemic'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;

-- believes(agent, proposition) — non-veridical; belief may be false.
oid := stable_uuid('believes', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','believes','believes',
'Agent x believes y to be true (non-veridical; belief may be false).')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,
  ARRAY['person','concept']::object_kind[],
  ARRAY['believer','believed'],
  ARRAY['object','object'],
  'primitive; distinct from knows; believes(X,Y) does not entail true(Y)',
  'x believes y',
  NULL,
  true,ARRAY['epistemic'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;

oid := stable_uuid('desires', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','desires','desires',
'Agent x wants or desires y.')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,
  ARRAY['person','concept']::object_kind[],
  ARRAY['desirer','desired'],
  ARRAY['object','object'],
  'primitive',
  'x desires y',
  'conceptnet:Desires',
  true,ARRAY['epistemic','social'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;

-- possible(proposition) — intransitive (unary); modal.
oid := stable_uuid('possible', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','possible','possible',
'Proposition x is possible (not necessarily actual). Intransitive (1 arg).')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,1,NULL,
  ARRAY['proposition'],
  ARRAY['object'],
  'primitive; modal',
  'x is possible',
  NULL,
  true,ARRAY['epistemic','modal'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;

-- necessary(proposition) — intransitive (unary); modal.
oid := stable_uuid('necessary', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','necessary','necessary',
'x is necessarily true — could not be otherwise. Intransitive (1 arg).')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,1,NULL,
  ARRAY['proposition'],
  ARRAY['object'],
  'primitive; modal; necessary(X) -> possible(X)',
  'x is necessarily true',
  NULL,
  true,ARRAY['epistemic','modal'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;


-- ════════════════════════════════════════════════════════════
-- GROUP 9: LINGUISTIC / REPRESENTATIONAL  (3)
-- ════════════════════════════════════════════════════════════

oid := stable_uuid('named', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','named','named',
'Entity x has name y in natural language.')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,NULL,
  ARRAY['entity','name'],
  ARRAY['object','object'],
  'primitive',
  'x is named y',
  'rdfs:label / wikidata:P2561',
  true,ARRAY['linguistic'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;

oid := stable_uuid('symbol_for', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','symbol_for','symbol for',
'x is a symbol or representation of y.')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,NULL,
  ARRAY['symbol','concept'],
  ARRAY['object','object'],
  'primitive',
  'x is a symbol of y',
  'conceptnet:SymbolOf',
  true,ARRAY['linguistic'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;

oid := stable_uuid('language_of', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','language_of','language of',
'Language x is spoken, written, or used by y.')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,NULL,
  ARRAY['language','entity'],
  ARRAY['object','object'],
  'primitive',
  'x is the language of y',
  'wikidata:P407',
  true,ARRAY['linguistic','social'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;


-- ════════════════════════════════════════════════════════════
-- GROUP 10: EVENT CALCULUS CORE  (4)
-- Meta-predicates over events and fluents.
-- holds_at is intransitive in a sense: it takes (fluent, time).
-- initiates and terminates are transitive: (event, fluent).
-- happens_at is transitive: (event, time).
-- ════════════════════════════════════════════════════════════

oid := stable_uuid('initiates', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','initiates','initiates',
'Event x causes state/fluent y to begin holding.')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,
  ARRAY['event','concept']::object_kind[],
  ARRAY['event','fluent'],
  ARRAY['object','object'],
  'primitive; event calculus',
  'event x initiates fluent y',
  'ec:Initiates',
  true,ARRAY['temporal','causal'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;

oid := stable_uuid('terminates', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','terminates','terminates',
'Event x causes state/fluent y to stop holding.')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,
  ARRAY['event','concept']::object_kind[],
  ARRAY['event','fluent'],
  ARRAY['object','object'],
  'primitive; event calculus',
  'event x terminates fluent y',
  'ec:Terminates',
  true,ARRAY['temporal','causal'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;

oid := stable_uuid('happens_at', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','happens_at','happens at',
'Event x occurs at time y.')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,
  ARRAY['event','concept']::object_kind[],
  ARRAY['event','time'],
  ARRAY['object','object'],
  'primitive; event calculus',
  'event x happens at time y',
  'ec:HappensAt',
  true,ARRAY['temporal'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;

-- holds_at_ec: Event Calculus fluent query (distinct from holds_at() SQL function).
-- Named holds_at_ec to avoid collision with the SQL function name.
oid := stable_uuid('holds_at_ec', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','holds_at_ec','holds at (EC)',
'State or fluent x is true at time y (Event Calculus meta-predicate).
Named holds_at_ec to avoid collision with the holds_at() SQL function.')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,
  ARRAY['concept','concept']::object_kind[],
  ARRAY['fluent','time'],
  ARRAY['object','object'],
  'derived from initiates/terminates/happens_at chain',
  'fluent x holds at time y',
  'ec:HoldsAt',
  true,ARRAY['temporal'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;


-- ════════════════════════════════════════════════════════════
-- GROUP 11: PHYSICAL / LIFECYCLE  (4)
-- born_in / died_in REMOVED — they are composites of has_role +
-- located_in + temporal scope, not basis primitives.
-- Use:  located_in(person, place, birth_time) + is_a(birth_event)
--    or has_role(person, role, org) with t_start / t_end.
-- ════════════════════════════════════════════════════════════

oid := stable_uuid('made_of', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','made_of','made of',
'x is composed of or constructed from material y.')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,NULL,
  ARRAY['object','material'],
  ARRAY['object','object'],
  'primitive',
  'x is made of y',
  'conceptnet:MadeOf',
  true,ARRAY['physical'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;

oid := stable_uuid('has_state', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','has_state','has state',
'Entity x is in physical or abstract state y.')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,NULL,
  ARRAY['entity','state'],
  ARRAY['object','object'],
  'primitive',
  'x is in state y',
  NULL,
  true,ARRAY['physical'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;

oid := stable_uuid('precondition_of', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','precondition_of','precondition of',
'x must hold before y can occur.')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,NULL,
  ARRAY['condition','event'],
  ARRAY['object','object'],
  'precondition_of(X,Y) :- necessary(X) ∧ before(X,Y)',
  'x is a precondition of y',
  'conceptnet:HasPrerequisite',
  true,ARRAY['causal','temporal'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;

oid := stable_uuid('affects', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','affects','affects',
'x has some effect on y (weaker than causes; no mechanism implied).')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,NULL,
  ARRAY['entity','entity'],
  ARRAY['object','object'],
  'weaker than causes; affects(X,Y) does not assert direction',
  'x affects y',
  'conceptnet:Causes (weak)',
  true,ARRAY['causal'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;


-- ════════════════════════════════════════════════════════════
-- GROUP 12: INFERENTIAL / CORRELATIONAL  (4)
-- ════════════════════════════════════════════════════════════

-- implies(proposition, proposition) — logical or probabilistic entailment.
-- Crisp at P=1; probabilistic at P<1 (encoded in belief_alpha/beta).
-- Distinct from causes: no temporal order, no mechanism.
oid := stable_uuid('implies', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','implies','implies',
'x logically or probabilistically entails y.
Distinct from causes: no temporal order or mechanism required.')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,NULL,
  ARRAY['proposition','proposition'],
  ARRAY['object','object'],
  'primitive; crisp at P=1, probabilistic at P<1',
  'x implies y',
  NULL,
  true,ARRAY['epistemic','causal','modal'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;

-- correlated_with — symmetric statistical association, no causal claim.
oid := stable_uuid('correlated_with', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','correlated_with','correlated with',
'x and y tend to co-occur or vary together (symmetric; no causal claim).')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,NULL,
  ARRAY['entity','entity'],
  ARRAY['object','object'],
  'primitive; symmetric; weaker than causes or implies',
  'x and y are correlated',
  NULL,
  true,ARRAY['causal','quantitative'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;

-- typical_of — prototype-theoretic typicality; graded.
-- "A robin is more typical_of bird than a penguin" — belief encodes degree.
-- This is the exemplification sense of the copula.
oid := stable_uuid('typical_of', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','typical_of','typical of',
'x is a typical or prototypical instance of category y (graded).
Encodes the exemplification sense of the copula ("a robin is a bird").
Belief value encodes typicality degree; belief=1 → as typical as possible.')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,NULL,
  ARRAY['entity','concept'],
  ARRAY['object','object'],
  'primitive; graded; distinct from is_a (crisp) and has_property',
  'x is a typical instance of y',
  'conceptnet:IsA (prototype sense)',
  true,ARRAY['taxonomic'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;

-- occurs_in(event, context_or_location) — complements located_in and during.
oid := stable_uuid('occurs_in', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','occurs_in','occurs in',
'Event x takes place within situation, context, or location y.')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,
  ARRAY['event','concept']::object_kind[],
  ARRAY['event','situation'],
  ARRAY['object','object'],
  'primitive; complements located_in (objects) and during (time)',
  'event x occurs in situation or location y',
  NULL,
  true,ARRAY['temporal','spatial'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;


-- ════════════════════════════════════════════════════════════
-- GROUP 13: STRUCTURAL / LOGICAL  (3)
-- Predicates about logical structure and value assignment.
-- These fill gaps in the basis for ontological reasoning.
-- ════════════════════════════════════════════════════════════

-- equivalent_to(x, y) — definitional equivalence, stronger than same_as.
-- same_as = co-referential (same real-world entity, possibly different descriptions).
-- equivalent_to = same meaning/intension, not just same referent.
-- "renaming(X)" ≡ "aliasing(X)" in a programming context.
oid := stable_uuid('equivalent_to', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','equivalent_to','equivalent to',
'x and y are definitionally or intensionally equivalent.
Stronger than same_as (co-reference); equivalent_to requires
the same meaning, not just the same referent.')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,NULL,
  ARRAY['concept','concept'],
  ARRAY['object','object'],
  'primitive; symmetric; equivalent_to(X,Y) → same_as(X,Y) but not vice versa',
  'x is definitionally equivalent to y',
  'owl:equivalentClass / owl:equivalentProperty',
  true,ARRAY['taxonomic','epistemic'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;

-- disjoint_with(type_a, type_b) — no instance can belong to both types.
-- "integer and person are disjoint" — essential for type-violation conflict detection.
oid := stable_uuid('disjoint_with', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','disjoint_with','disjoint with',
'No entity can simultaneously be an instance of both x and y.
Essential for type-violation conflict detection in the conflicts table.')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,2,
  ARRAY['concept','concept']::object_kind[],
  ARRAY['type_a','type_b'],
  ARRAY['object','object'],
  'disjoint_with(X,Y) :- not exists Z s.t. is_a(Z,X) ∧ is_a(Z,Y)',
  'types x and y share no instances',
  'owl:disjointWith',
  true,ARRAY['taxonomic'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;

-- has_value(entity, attribute, value) — bitransitive.
-- Associates a named attribute with a concrete value.
-- "The speed of light has_value c, 299792458 m/s."
-- Distinct from has_quantity (which takes a quantity object);
-- has_value allows a literal value in the third position.
-- attribute is typically a concept object naming the property.
oid := stable_uuid('has_value', 'predicate');
INSERT INTO objects (id,kind,canonical_name,display_name,description)
VALUES (oid,'predicate','has_value','has value',
'Entity x has attribute y with value z.
Third arg (z) is typically a literal (integer, float, string).
Distinct from has_quantity: has_value names the attribute explicitly.
"Speed of light has_value (speed, 299792458)" [m/s].')
ON CONFLICT (canonical_name,kind) DO NOTHING;
INSERT INTO predicates (id,arity,arg_kinds,arg_labels,arg_types,
  fol_definition,nl_description,source_predicate,is_basis,domains,status,introduced_by)
VALUES (oid,3,NULL,
  ARRAY['entity','attribute','value'],
  ARRAY['object','object','integer'],  -- value is typically a literal
  'primitive; bitransitive; value arg is usually literal_args',
  'x has attribute y with value z',
  'wikidata:P1 generalised',
  true,ARRAY['quantitative','taxonomic'],'confirmed',sys)
ON CONFLICT (id) DO NOTHING;

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
    END                  AS transitivity,
    p.arg_labels,
    p.domains,
    p.source_predicate
FROM predicates p
JOIN objects o ON o.id = p.id
WHERE p.is_basis = true
ORDER BY p.arity, p.domains[1], o.canonical_name;

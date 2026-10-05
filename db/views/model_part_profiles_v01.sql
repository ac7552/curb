-- How often UK inspections find each part worn or failing on a model, compared with an average car the
-- same age. One row per make, model, engine ('*' = all engines), year of first registration and part.
--   hits / fails:                    inspections that recorded the part (fail or advisory / fail only)
--   expected_hits / expected_fails:  what an average car would have had, given this group's ages
--   tests:                           inspections of the group
-- Advisories count because wear (leaks, worn bushes) is mostly recorded as an advisory.
WITH tested AS (
  SELECT
    i.id AS inspection_id,
    v.make_key,
    v.model_key,
    COALESCE(v.engine_key, '') AS engine_key,
    EXTRACT(YEAR FROM v.first_used_on)::int AS build_year,
    LEAST(GREATEST(FLOOR((i.inspected_on - v.first_used_on)::numeric / 365.25), 0), 25)::int AS age
  FROM inspections i
  JOIN vehicles v ON v.id = i.vehicle_id
  WHERE v.first_used_on >= '1995-01-01'
),
parts AS (
  SELECT d.inspection_id, p.defect_category_id, BOOL_OR(d.kind = 'fail') AS failed
  FROM defects d
  JOIN defect_phrases p ON p.id = d.defect_phrase_id
  WHERE p.defect_category_id IS NOT NULL
  GROUP BY 1, 2
),
age_tests AS (
  SELECT age, COUNT(*)::float AS tests FROM tested GROUP BY 1
),
age_rates AS (
  SELECT t.age, pa.defect_category_id,
         COUNT(*) / MAX(a.tests) AS hit_rate,
         COUNT(*) FILTER (WHERE pa.failed) / MAX(a.tests) AS fail_rate
  FROM tested t
  JOIN parts pa USING (inspection_id)
  JOIN age_tests a USING (age)
  GROUP BY 1, 2
),
group_ages AS (
  SELECT make_key, model_key, COALESCE(engine_key, '*') AS engine_key, build_year, age, COUNT(*) AS tests
  FROM tested
  GROUP BY GROUPING SETS ((make_key, model_key, engine_key, build_year, age), (make_key, model_key, build_year, age))
),
group_hits AS (
  SELECT t.make_key, t.model_key, COALESCE(t.engine_key, '*') AS engine_key, t.build_year, pa.defect_category_id,
         COUNT(*)::int AS hits, (COUNT(*) FILTER (WHERE pa.failed))::int AS fails
  FROM tested t
  JOIN parts pa USING (inspection_id)
  GROUP BY GROUPING SETS ((t.make_key, t.model_key, t.engine_key, t.build_year, pa.defect_category_id),
                          (t.make_key, t.model_key, t.build_year, pa.defect_category_id))
),
expected AS (
  SELECT h.make_key, h.model_key, h.engine_key, h.build_year, h.defect_category_id,
         SUM(g.tests * r.hit_rate) AS expected_hits, SUM(g.tests * r.fail_rate) AS expected_fails
  FROM group_hits h
  JOIN group_ages g
    ON g.make_key = h.make_key AND g.model_key = h.model_key AND g.engine_key = h.engine_key AND g.build_year = h.build_year
  JOIN age_rates r ON r.defect_category_id = h.defect_category_id AND r.age = g.age
  GROUP BY 1, 2, 3, 4, 5
),
totals AS (
  SELECT make_key, model_key, engine_key, build_year, SUM(tests)::int AS tests
  FROM group_ages
  GROUP BY 1, 2, 3, 4
)
SELECT h.make_key, h.model_key, h.engine_key, h.build_year, h.defect_category_id,
       t.tests, h.hits, h.fails, e.expected_hits, e.expected_fails
FROM group_hits h
JOIN totals t USING (make_key, model_key, engine_key, build_year)
JOIN expected e USING (make_key, model_key, engine_key, build_year, defect_category_id)

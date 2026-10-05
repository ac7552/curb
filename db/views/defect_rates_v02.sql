-- Failures per component category (advisories aren't counted: they're wear notes, not repairs), per cell of inspection_cells.
-- Refresh inspection_cells first.
WITH tested AS (
  SELECT
    i.id AS inspection_id,
    v.make_key,
    v.model_key,
    COALESCE(v.engine_key, '') AS engine_key,
    LEAST(GREATEST(FLOOR((i.inspected_on - COALESCE(v.first_used_on, make_date(v.model_year, 7, 1)))::numeric / 365.25), 0), 25)::int AS age_years,
    (LEAST(i.mileage, 299999) / 20000)::int AS mileage_band
  FROM inspections i
  JOIN vehicles v ON v.id = i.vehicle_id
  WHERE i.mileage IS NOT NULL
    AND (v.first_used_on IS NOT NULL OR v.model_year IS NOT NULL)
),
failed AS (
  SELECT
    t.make_key, t.model_key, t.engine_key, t.age_years, t.mileage_band,
    p.defect_category_id,
    COUNT(DISTINCT t.inspection_id)::int AS failures
  FROM tested t
  JOIN defects d ON d.inspection_id = t.inspection_id AND d.kind = 'fail'
  JOIN defect_phrases p ON p.id = d.defect_phrase_id
  WHERE p.defect_category_id IS NOT NULL
  GROUP BY 1, 2, 3, 4, 5, 6
)
SELECT f.*, c.tests
FROM failed f
JOIN inspection_cells c
  ON c.make_key = f.make_key
 AND c.model_key = f.model_key
 AND c.engine_key = f.engine_key
 AND c.age_years = f.age_years
 AND c.mileage_band = f.mileage_band

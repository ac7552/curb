-- One row per (model, engine, age, mileage band): how many inspections were done on cars in that cell.
SELECT
  v.make_key,
  v.model_key,
  COALESCE(v.engine_key, '') AS engine_key,
  LEAST(GREATEST(FLOOR((i.inspected_on - COALESCE(v.first_used_on, make_date(v.model_year, 7, 1)))::numeric / 365.25), 0), 25)::int AS age_years,
  (LEAST(i.mileage, 299999) / 20000)::int AS mileage_band,
  COUNT(*)::int AS tests
FROM inspections i
JOIN vehicles v ON v.id = i.vehicle_id
WHERE i.mileage IS NOT NULL
  AND (v.first_used_on IS NOT NULL OR v.model_year IS NOT NULL)
GROUP BY 1, 2, 3, 4, 5

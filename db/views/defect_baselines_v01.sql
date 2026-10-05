-- Each category's rate across every model, per age and mileage band: the p-bar that small samples are pulled toward.
-- Refresh inspection_cells and defect_rates first.
WITH totals AS (
  SELECT age_years, mileage_band, SUM(tests)::int AS tests
  FROM inspection_cells
  GROUP BY 1, 2
),
failures AS (
  SELECT defect_category_id, age_years, mileage_band, SUM(failures)::int AS failures
  FROM defect_rates
  GROUP BY 1, 2, 3
)
SELECT f.defect_category_id, f.age_years, f.mileage_band, f.failures, t.tests
FROM failures f
JOIN totals t USING (age_years, mileage_band)

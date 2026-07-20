-- monthly count of each outcome, by signup month (started_at). Filterable
-- by product group and product slug via the dropdowns on the page.
SELECT
  date_trunc('month', started_at) AS month,
  CASE final_status
    WHEN 'stayed_enabled' THEN 'Stayed enabled'
    WHEN 'disabled_before_expiry' THEN 'Actively cancelled'
    WHEN 'never_enabled' THEN 'No record'
  END AS outcome,
  final_status,
  count(*) AS subscriptions
FROM ${subscription_status}
WHERE product_group LIKE '${inputs.group_filter.value}'
  AND product_slug LIKE '${inputs.slug_filter.value}'
GROUP BY 1, 2, 3
ORDER BY 1

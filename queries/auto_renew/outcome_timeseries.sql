-- monthly outcome counts by signup month, filterable via page dropdowns.
SELECT
  date_trunc('month', started_at) AS month,
  CASE final_status
    WHEN 'stayed_enabled' THEN 'Stayed enabled'
    WHEN 'disabled_before_expiry' THEN 'Actively cancelled'
    WHEN 'no_record' THEN 'No record'
  END AS outcome,
  final_status,
  count(*) AS subscriptions
FROM ${subscription_status}
WHERE product_group LIKE '${inputs.group_filter.value}'
  AND product_slug LIKE '${inputs.slug_filter.value}'
  AND final_status != 'excluded_unreliable'
GROUP BY 1, 2, 3
ORDER BY 1

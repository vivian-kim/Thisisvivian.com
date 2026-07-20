SELECT
  product_group,
  CASE final_status
    WHEN 'stayed_enabled' THEN 'Stayed enabled'
    WHEN 'disabled_before_expiry' THEN 'Actively cancelled'
    WHEN 'never_enabled' THEN 'No record'
  END AS outcome,
  final_status,
  count(*) AS subscriptions,
  round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY product_group), 1) AS pct
FROM ${subscription_status}
WHERE period_months::varchar LIKE '${inputs.plan_filter.value}'
GROUP BY 1, 2, 3
ORDER BY product_group, subscriptions DESC

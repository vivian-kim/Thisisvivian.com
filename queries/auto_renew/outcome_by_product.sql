SELECT
  product_group,
  CASE final_status
    WHEN 'stayed_enabled' THEN 'Stayed enabled'
    WHEN 'disabled_before_expiry' THEN 'Actively cancelled'
    WHEN 'no_record' THEN 'No record'
  END AS outcome,
  final_status,
  count(*) AS subscriptions,
  round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY product_group), 1) / 100.0 AS pct
FROM ${subscription_status}
WHERE final_status != 'excluded_unreliable'
GROUP BY 1, 2, 3
ORDER BY product_group, subscriptions DESC

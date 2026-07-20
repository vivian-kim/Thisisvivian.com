SELECT
  CASE final_status
    WHEN 'stayed_enabled' THEN 'Stayed enabled'
    WHEN 'disabled_before_expiry' THEN 'Actively cancelled'
    WHEN 'no_record' THEN 'No record'
  END AS outcome,
  final_status,
  count(*) AS subscriptions,
  round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
FROM ${subscription_status}
WHERE period_months::varchar LIKE '${inputs.plan_filter.value}' AND final_status != 'excluded_unreliable'
GROUP BY 1, 2
ORDER BY subscriptions DESC

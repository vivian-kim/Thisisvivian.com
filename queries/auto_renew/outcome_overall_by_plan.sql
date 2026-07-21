-- Same as outcome_overall.sql but split by plan length directly, as a
-- stacked series, instead of relying on the plan_filter dropdown.
SELECT
  CASE final_status
    WHEN 'stayed_enabled' THEN 'Stayed enabled'
    WHEN 'disabled_before_expiry' THEN 'Actively cancelled'
    WHEN 'no_record' THEN 'No record'
  END AS outcome,
  final_status,
  period_months::int || ' month' AS plan,
  period_months,
  count(*) AS subscriptions,
  round(100.0 * count(*) / sum(count(*)) OVER (), 1) / 100.0 AS pct
FROM ${subscription_status}
WHERE final_status != 'excluded_unreliable'
GROUP BY 1, 2, 3, 4
ORDER BY subscriptions DESC

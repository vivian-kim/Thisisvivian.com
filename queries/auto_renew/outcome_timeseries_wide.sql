-- Same data as outcome_timeseries.sql, one row per month (columns instead
-- of repeated rows per outcome) for a table that's easier to scan.
SELECT
  date_trunc('month', started_at) AS month,
  count(*) AS subscriptions,
  round(100.0 * sum(CASE WHEN final_status = 'stayed_enabled' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS stayed_pct,
  round(100.0 * sum(CASE WHEN final_status = 'disabled_before_expiry' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS cancelled_pct,
  round(100.0 * sum(CASE WHEN final_status = 'no_record' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS no_record_pct
FROM ${subscription_status}
WHERE product_group LIKE '${inputs.group_filter.value}'
  AND product_slug LIKE '${inputs.slug_filter.value}'
  AND final_status != 'excluded_unreliable'
GROUP BY 1
ORDER BY 1

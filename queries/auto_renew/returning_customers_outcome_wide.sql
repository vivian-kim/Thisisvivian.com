-- Same data as returning_customers_outcome.sql, one row per group.
SELECT
  CASE WHEN n_windows > 1 THEN 'Re-enabled after disabling' ELSE 'Never re-enabled' END AS grp,
  count(*) AS n,
  round(100.0 * sum(CASE WHEN final_status = 'stayed_enabled' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS stayed_pct,
  round(100.0 * sum(CASE WHEN final_status = 'disabled_before_expiry' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS cancelled_pct
FROM ${subscription_status}
WHERE final_status NOT IN ('no_record', 'excluded_unreliable')
GROUP BY 1
ORDER BY grp

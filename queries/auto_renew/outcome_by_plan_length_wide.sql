-- Same data as outcome_by_plan_length.sql, one row per plan length.
SELECT
  period_months || '-month' AS plan,
  period_months,
  count(*) AS subscriptions,
  round(100.0 * sum(CASE WHEN final_status = 'stayed_enabled' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS stayed_pct,
  round(100.0 * sum(CASE WHEN final_status = 'disabled_before_expiry' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS cancelled_pct,
  round(100.0 * sum(CASE WHEN final_status = 'no_record' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS no_record_pct,
  round(median(billings_eur_excl_vat), 2) AS median_price
FROM ${subscription_status}
WHERE final_status != 'excluded_unreliable'
GROUP BY 1, 2
ORDER BY period_months

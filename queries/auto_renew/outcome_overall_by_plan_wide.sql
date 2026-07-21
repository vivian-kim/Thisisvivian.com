-- Same data as outcome_overall_by_plan.sql, one row per plan length, with
-- both absolute counts and within-plan percentages for each outcome.
SELECT
  period_months::int || ' month' AS plan,
  period_months,
  count(*) AS subscriptions,
  sum(CASE WHEN final_status = 'stayed_enabled' THEN 1 ELSE 0 END) AS stayed_n,
  round(100.0 * sum(CASE WHEN final_status = 'stayed_enabled' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS stayed_pct,
  sum(CASE WHEN final_status = 'disabled_before_expiry' THEN 1 ELSE 0 END) AS cancelled_n,
  round(100.0 * sum(CASE WHEN final_status = 'disabled_before_expiry' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS cancelled_pct,
  sum(CASE WHEN final_status = 'no_record' THEN 1 ELSE 0 END) AS no_record_n,
  round(100.0 * sum(CASE WHEN final_status = 'no_record' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS no_record_pct
FROM ${subscription_status}
WHERE final_status != 'excluded_unreliable'
GROUP BY 1, 2
ORDER BY period_months DESC

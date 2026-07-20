-- for 12-month plans, renewal month = signup month a year later, so this
-- answers both "does signup month matter" and "does renewal month matter"
-- in one pass. No date filter here - the tracking-gap caveat is explained
-- in the write-up rather than filtered out of this query.
SELECT
  strftime(ended_at, '%m-%b') AS renewal_month,
  count(*) AS total,
  round(100.0 * sum(CASE WHEN final_status = 'stayed_enabled' THEN 1 ELSE 0 END) / count(*), 1) AS stayed_pct,
  round(100.0 * sum(CASE WHEN final_status = 'disabled_before_expiry' THEN 1 ELSE 0 END) / count(*), 1) AS cancelled_pct,
  round(100.0 * sum(CASE WHEN final_status = 'never_enabled' THEN 1 ELSE 0 END) / count(*), 1) AS no_record_pct
FROM ${subscription_status}
WHERE period_months = 12
GROUP BY 1
ORDER BY 1

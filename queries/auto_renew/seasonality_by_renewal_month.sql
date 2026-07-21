-- renewal_month = ended_at's month, i.e. when the term-end decision
-- happens. NOT all of these subscriptions were actually renewing --
-- "no_record" ones were never confirmed to have auto-renew on at all,
-- so this is the term-end cohort, not a "renewing subscribers" count.
-- For 12-month plans that's the same calendar month as signup, a year
-- later; for 1-month plans it's simply the following month. Toggle via
-- the plan-length dropdown on the page.
SELECT
  strftime(ended_at, '%m-%b') AS renewal_month,
  count(*) AS term_end_subscriptions,
  round(100.0 * sum(CASE WHEN final_status = 'stayed_enabled' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS stayed_pct,
  round(100.0 * sum(CASE WHEN final_status = 'disabled_before_expiry' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS cancelled_pct,
  round(100.0 * sum(CASE WHEN final_status = 'no_record' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS no_record_pct
FROM ${subscription_status}
WHERE period_months = ${inputs.seasonality_plan.value} AND final_status != 'excluded_unreliable'
GROUP BY 1
ORDER BY 1

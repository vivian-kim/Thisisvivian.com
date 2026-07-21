-- The headline stat for this section: revenue actually lost to cancellation
-- vs. everything else (stayed enabled + no record combined). Kept separate
-- from revenue_by_outcome.sql, which breaks all 3 outcomes out individually
-- for the supporting detail table below.
SELECT
  CASE WHEN final_status = 'disabled_before_expiry' THEN '1. Lost to cancellation' ELSE '2. Not lost (stayed enabled + no record)' END AS bucket,
  round(sum(billings_eur_excl_vat), 2) AS revenue_eur,
  round(100.0 * sum(billings_eur_excl_vat) / sum(sum(billings_eur_excl_vat)) OVER (), 1) / 100.0 AS pct_of_total
FROM ${subscription_status}
WHERE final_status != 'excluded_unreliable'
GROUP BY 1
ORDER BY bucket

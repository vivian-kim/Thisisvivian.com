-- Same data as outcome_by_price.sql, one row per price bucket.
SELECT
  CASE
    WHEN billings_eur_excl_vat = 0  THEN '1. Free (€0)'
    WHEN billings_eur_excl_vat < 5  THEN '2. €0.01-5'
    WHEN billings_eur_excl_vat < 10 THEN '3. €5-10'
    WHEN billings_eur_excl_vat < 20 THEN '4. €10-20'
    ELSE '5. €20+'
  END AS price_bucket,
  count(*) AS subscriptions,
  round(100.0 * sum(CASE WHEN final_status = 'stayed_enabled' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS stayed_pct,
  round(100.0 * sum(CASE WHEN final_status = 'disabled_before_expiry' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS cancelled_pct,
  round(100.0 * sum(CASE WHEN final_status = 'no_record' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS no_record_pct
FROM ${subscription_status}
WHERE final_status != 'excluded_unreliable'
GROUP BY 1
ORDER BY price_bucket

SELECT
  CASE
    WHEN billings_eur_excl_vat = 0  THEN '1. Free (€0)'
    WHEN billings_eur_excl_vat < 5  THEN '2. €0.01-5'
    WHEN billings_eur_excl_vat < 10 THEN '3. €5-10'
    WHEN billings_eur_excl_vat < 20 THEN '4. €10-20'
    ELSE '5. €20+'
  END AS price_bucket,
  CASE final_status
    WHEN 'stayed_enabled' THEN 'Stayed enabled'
    WHEN 'disabled_before_expiry' THEN 'Actively cancelled'
    WHEN 'no_record' THEN 'No record'
  END AS outcome,
  final_status,
  count(*) AS subscriptions,
  round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY
    CASE
      WHEN billings_eur_excl_vat = 0  THEN '1. Free (€0)'
      WHEN billings_eur_excl_vat < 5  THEN '2. €0.01-5'
      WHEN billings_eur_excl_vat < 10 THEN '3. €5-10'
      WHEN billings_eur_excl_vat < 20 THEN '4. €10-20'
      ELSE '5. €20+'
    END), 1) / 100.0 AS pct
FROM ${subscription_status}
WHERE period_months::varchar LIKE '${inputs.plan_filter.value}' AND final_status != 'excluded_unreliable'
GROUP BY 1, 2, 3
ORDER BY price_bucket, subscriptions DESC

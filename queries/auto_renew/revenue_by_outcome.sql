SELECT
  CASE final_status
    WHEN 'stayed_enabled' THEN 'Stayed enabled'
    WHEN 'disabled_before_expiry' THEN 'Actively cancelled'
    WHEN 'never_enabled' THEN 'No record'
  END AS outcome,
  final_status,
  count(*) AS subscriptions,
  round(sum(billings_eur_excl_vat), 2) AS revenue_eur
FROM ${subscription_status}
GROUP BY 1, 2
ORDER BY revenue_eur DESC

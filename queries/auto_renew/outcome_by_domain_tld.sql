-- product_group alone hides wide variance across domain TLDs, mostly
-- price-driven but actionable by TLD in a way a price bracket isn't.
SELECT
  product_slug,
  count(*) AS subscriptions,
  round(100.0 * sum(CASE WHEN final_status = 'stayed_enabled' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS stayed_pct,
  round(100.0 * sum(CASE WHEN final_status = 'disabled_before_expiry' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS cancelled_pct,
  round(100.0 * sum(CASE WHEN final_status = 'no_record' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS no_record_pct,
  round(avg(billings_eur_excl_vat), 2) AS avg_price
FROM ${subscription_status}
WHERE product_group = 'domain' AND final_status != 'excluded_unreliable'
GROUP BY 1
ORDER BY subscriptions DESC

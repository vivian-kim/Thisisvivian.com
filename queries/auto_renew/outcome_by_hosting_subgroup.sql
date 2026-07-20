-- "Hosting" isn't one product - shared vs. cloud retain very differently,
-- largely (not entirely) a price effect.
SELECT
  product_sub_group,
  CASE final_status
    WHEN 'stayed_enabled' THEN 'Stayed enabled'
    WHEN 'disabled_before_expiry' THEN 'Actively cancelled'
    WHEN 'no_record' THEN 'No record'
  END AS outcome,
  final_status,
  count(*) AS subscriptions,
  round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY product_sub_group), 1) / 100.0 AS pct
FROM ${subscription_status}
WHERE product_group = 'hosting' AND final_status != 'excluded_unreliable'
GROUP BY 1, 2, 3
ORDER BY product_sub_group, subscriptions DESC

-- product_group alone treats "Hosting" as one bucket - it isn't. Shared and
-- cloud hosting are different products with very different retention.
-- Substantially overlaps with the price->retention story elsewhere in this
-- report (cloud averages ~3x shared's price), but named directly here since
-- "push customers toward cloud hosting" is a concrete lever in a way a
-- price bracket alone isn't.
SELECT
  product_sub_group,
  CASE final_status
    WHEN 'stayed_enabled' THEN 'Stayed enabled'
    WHEN 'disabled_before_expiry' THEN 'Actively cancelled'
    WHEN 'never_enabled' THEN 'No record'
  END AS outcome,
  final_status,
  count(*) AS subscriptions,
  round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY product_sub_group), 1) AS pct
FROM ${subscription_status}
WHERE product_group = 'hosting'
GROUP BY 1, 2, 3
ORDER BY product_sub_group, subscriptions DESC

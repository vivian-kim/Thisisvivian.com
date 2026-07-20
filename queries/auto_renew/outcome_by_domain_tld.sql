-- product_group alone (Domain: 29.1% stayed) hides a wide range across TLDs.
-- Largely tracks price (.xyz is free, .online/.store/.tech sit near
-- EUR 0.27-0.30, .es/.org are priced higher) - mostly the price story
-- wearing a TLD costume, but TLD is something pricing/promo teams can act
-- on directly, unlike a price bracket. domain:.be excluded from the
-- narrative (n=24, too small to trust) but left in this table for reference.
SELECT
  product_slug,
  count(*) AS subscriptions,
  round(100.0 * sum(CASE WHEN final_status = 'stayed_enabled' THEN 1 ELSE 0 END) / count(*), 1) AS stayed_pct,
  round(100.0 * sum(CASE WHEN final_status = 'disabled_before_expiry' THEN 1 ELSE 0 END) / count(*), 1) AS cancelled_pct,
  round(100.0 * sum(CASE WHEN final_status = 'never_enabled' THEN 1 ELSE 0 END) / count(*), 1) AS no_record_pct,
  round(avg(billings_eur_excl_vat), 2) AS avg_price
FROM ${subscription_status}
WHERE product_group = 'domain'
GROUP BY 1
ORDER BY subscriptions DESC

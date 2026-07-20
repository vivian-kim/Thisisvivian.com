-- rate alone can mislead prioritization - a scary cancel % on a tiny
-- product matters less than a modest % on a huge one. This ranks every
-- product_slug by actual euros lost to cancellation, not just its rate.
SELECT
  product_slug,
  count(*) AS subscriptions,
  round(sum(CASE WHEN final_status = 'disabled_before_expiry' THEN billings_eur_excl_vat ELSE 0 END), 2) AS cancelled_revenue,
  round(100.0 * sum(CASE WHEN final_status = 'disabled_before_expiry' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS cancelled_pct
FROM ${subscription_status}
WHERE final_status != 'excluded_unreliable'
GROUP BY 1
ORDER BY cancelled_revenue DESC

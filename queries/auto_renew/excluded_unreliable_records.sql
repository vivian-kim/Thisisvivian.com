-- the 20 subscriptions excluded from every chart, shown here rather than
-- silently dropped - see Data Quality Findings for the two bugs behind this.
SELECT
  subscription_id,
  product_slug,
  exclusion_reason,
  started_at,
  ended_at,
  last_enabled_from,
  last_enabled_to,
  billings_eur_excl_vat
FROM ${subscription_status}
WHERE final_status = 'excluded_unreliable'
ORDER BY exclusion_reason, subscription_id

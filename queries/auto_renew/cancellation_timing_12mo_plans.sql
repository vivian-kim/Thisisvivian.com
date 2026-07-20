SELECT
  CASE
    WHEN days_before_expiry_disabled <= 3  THEN '0-3 days before'
    WHEN days_before_expiry_disabled <= 14 THEN '4-14 days before'
    WHEN days_before_expiry_disabled <= 30 THEN '15-30 days before'
    WHEN days_before_expiry_disabled <= 90 THEN '31-90 days before'
    ELSE '90+ days before'
  END AS bucket,
  min(days_before_expiry_disabled) AS sort_key,
  count(*) AS n,
  round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
FROM ${subscription_status}
WHERE final_status = 'disabled_before_expiry' AND is_clean_window AND period_months = 12
GROUP BY 1
ORDER BY sort_key

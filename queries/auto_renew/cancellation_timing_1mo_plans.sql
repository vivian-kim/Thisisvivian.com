SELECT
  CASE
    WHEN days_before_expiry_disabled <= 3  THEN '0-3 days before'
    WHEN days_before_expiry_disabled <= 7  THEN '4-7 days before'
    WHEN days_before_expiry_disabled <= 14 THEN '8-14 days before'
    ELSE '15-30 days before'
  END AS bucket,
  min(days_before_expiry_disabled) AS sort_key,
  count(*) AS n,
  round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
FROM ${subscription_status}
WHERE final_status = 'disabled_before_expiry' AND is_clean_window AND period_months = 1
GROUP BY 1
ORDER BY sort_key

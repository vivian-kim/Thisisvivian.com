SELECT
  CASE
    WHEN days_to_disable <= 3  THEN '0-3 days'
    WHEN days_to_disable <= 7  THEN '4-7 days'
    WHEN days_to_disable <= 14 THEN '8-14 days'
    WHEN days_to_disable <= 21 THEN '15-21 days'
    ELSE '22-30 days'
  END AS bucket,
  min(days_to_disable) AS sort_key,
  count(*) AS n,
  round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
FROM ${subscription_status}
WHERE final_status = 'disabled_before_expiry' AND is_clean_window AND period_months = 1
GROUP BY 1
ORDER BY sort_key

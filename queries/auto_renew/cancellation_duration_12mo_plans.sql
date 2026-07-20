SELECT
  CASE
    WHEN days_to_disable <= 7   THEN '0-7 days'
    WHEN days_to_disable <= 30  THEN '8-30 days'
    WHEN days_to_disable <= 90  THEN '31-90 days'
    WHEN days_to_disable <= 180 THEN '91-180 days'
    WHEN days_to_disable <= 270 THEN '181-270 days'
    ELSE '271-365 days'
  END AS bucket,
  min(days_to_disable) AS sort_key,
  count(*) AS n,
  round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
FROM ${subscription_status}
WHERE final_status = 'disabled_before_expiry' AND is_clean_window AND period_months = 12
GROUP BY 1
ORDER BY sort_key

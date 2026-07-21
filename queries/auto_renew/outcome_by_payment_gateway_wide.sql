-- Same data as outcome_by_payment_gateway.sql, one row per gateway type.
SELECT
  CASE
    WHEN payment_gateway IN ('coingate','coinpayments') THEN '2. Crypto'
    WHEN payment_gateway IN ('checkout','credorax','paypal') THEN '1. Card / bank'
    WHEN payment_gateway IS NULL THEN '3. No gateway on file'
    ELSE '4. Other'
  END AS gateway_type,
  count(*) AS subscriptions,
  round(100.0 * sum(CASE WHEN final_status = 'stayed_enabled' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS stayed_pct,
  round(100.0 * sum(CASE WHEN final_status = 'disabled_before_expiry' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS cancelled_pct,
  round(100.0 * sum(CASE WHEN final_status = 'no_record' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS no_record_pct
FROM ${subscription_status}
WHERE period_months::varchar LIKE '${inputs.gateway_plan_filter.value}' AND final_status != 'excluded_unreliable'
GROUP BY 1
ORDER BY gateway_type

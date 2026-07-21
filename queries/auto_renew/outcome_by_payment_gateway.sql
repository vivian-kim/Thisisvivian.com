SELECT
  CASE
    WHEN payment_gateway IN ('coingate','coinpayments') THEN '2. Crypto'
    WHEN payment_gateway IN ('checkout','credorax','paypal') THEN '1. Card / bank'
    WHEN payment_gateway IS NULL THEN '3. No gateway on file'
    ELSE '4. Other'
  END AS gateway_type,
  CASE final_status
    WHEN 'stayed_enabled' THEN 'Stayed enabled'
    WHEN 'disabled_before_expiry' THEN 'Actively cancelled'
    WHEN 'no_record' THEN 'No record'
  END AS outcome,
  final_status,
  count(*) AS subscriptions,
  round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY
    CASE
      WHEN payment_gateway IN ('coingate','coinpayments') THEN '2. Crypto'
      WHEN payment_gateway IN ('checkout','credorax','paypal') THEN '1. Card / bank'
      WHEN payment_gateway IS NULL THEN '3. No gateway on file'
      ELSE '4. Other'
    END), 1) / 100.0 AS pct
FROM ${subscription_status}
WHERE period_months::varchar LIKE '${inputs.gateway_plan_filter.value}' AND final_status != 'excluded_unreliable'
GROUP BY 1, 2, 3
ORDER BY gateway_type, subscriptions DESC

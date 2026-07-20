SELECT
  CASE WHEN n_windows > 1 THEN 'Toggled more than once' ELSE 'Never toggled back' END AS grp,
  CASE final_status
    WHEN 'stayed_enabled' THEN 'Stayed enabled'
    WHEN 'disabled_before_expiry' THEN 'Actively cancelled'
  END AS outcome,
  final_status,
  count(*) AS n,
  round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY
    CASE WHEN n_windows > 1 THEN 'Toggled more than once' ELSE 'Never toggled back' END), 1) AS pct
FROM ${subscription_status}
WHERE final_status NOT IN ('no_record', 'excluded_unreliable')
GROUP BY 1, 2, 3
ORDER BY grp, n DESC

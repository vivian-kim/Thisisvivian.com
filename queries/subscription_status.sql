-- Master classification query - every other query builds on this instead
-- of re-deriving final_status, so outcomes stay consistent everywhere.
WITH true_rows AS (
    SELECT *,
        count(*) OVER (PARTITION BY subscription_id) AS n_windows
    FROM ${subscriptions}
    WHERE is_auto_renew = true
),
last_window AS (
    -- keep only each subscription's most recent enabled window (some
    -- toggled auto-renew off/on more than once; we only want where they
    -- ended up, and need exactly 1 row per subscription downstream)
    SELECT *,
        row_number() OVER (PARTITION BY subscription_id ORDER BY ar_valid_from DESC) AS rn
    FROM true_rows
    QUALIFY rn = 1
),
no_record_rows AS (
    SELECT *, 1 AS n_windows
    FROM ${subscriptions}
    WHERE is_auto_renew IS NULL
),
final_group AS (
    SELECT
        subscription_id, payment_gateway, product_group, product_sub_group,
        product_slug, period_months, started_at, ended_at, billings_eur_excl_vat,
        n_windows,
        ar_valid_from AS last_enabled_from,
        ar_valid_to   AS last_enabled_to,
        -- 20 rows have broken dates (2 distinct bugs, see Data Quality
        -- Findings) and are excluded rather than misclassified
        CASE
            WHEN (ar_valid_from IS NOT NULL AND ar_valid_to IS NOT NULL AND ar_valid_from > ar_valid_to)
                 OR (ar_valid_to IS NOT NULL AND ar_valid_to < started_at)
                 THEN 'excluded_unreliable'
            WHEN ar_valid_to IS NULL THEN 'no_record'
            WHEN ar_valid_to >= ended_at THEN 'stayed_enabled'
            ELSE 'disabled_before_expiry'
        END AS final_status,
        CASE
            WHEN ar_valid_from IS NOT NULL AND ar_valid_to IS NOT NULL AND ar_valid_from > ar_valid_to THEN 'es_batch_bug'
            WHEN ar_valid_to IS NOT NULL AND ar_valid_to < started_at THEN 'window_predates_start'
        END AS exclusion_reason,
        CASE WHEN ar_valid_to IS NOT NULL AND ar_valid_to < ended_at AND ar_valid_to >= started_at
             AND NOT (ar_valid_from IS NOT NULL AND ar_valid_from > ar_valid_to)
             THEN date_diff('day', started_at, ar_valid_to) END AS days_to_disable,
        CASE WHEN ar_valid_to IS NOT NULL AND ar_valid_to < ended_at AND ar_valid_to >= started_at
             AND NOT (ar_valid_from IS NOT NULL AND ar_valid_from > ar_valid_to)
             THEN date_diff('day', ar_valid_to, ended_at) END AS days_before_expiry_disabled,
        (ar_valid_to IS NOT NULL AND ar_valid_to >= started_at) OR ar_valid_to IS NULL AS is_clean_window
    FROM last_window
)
SELECT * FROM final_group
UNION ALL
SELECT
    subscription_id, payment_gateway, product_group, product_sub_group,
    product_slug, period_months, started_at, ended_at, billings_eur_excl_vat,
    n_windows, NULL, NULL, 'no_record', NULL, NULL, NULL, true
FROM no_record_rows

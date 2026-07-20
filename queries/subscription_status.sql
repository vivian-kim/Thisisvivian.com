-- Master classification query. Every other query in this project that needs
-- final_status builds on top of this one instead of re-deriving it, so the
-- three outcome definitions stay identical everywhere they're used.
WITH true_rows AS (
    SELECT *,
        count(*) OVER (PARTITION BY subscription_id) AS n_windows
    FROM ${subscriptions}
    WHERE is_auto_renew = true
),
last_window AS (
    -- rn = 1 keeps only each subscription's MOST RECENT enabled window.
    -- For the 365 subscriptions that toggled auto-renew off and back on
    -- more than once, we only care about where they ended up, not their
    -- full toggle history - without this filter, one subscription with
    -- 5 toggles would appear as 5 separate rows instead of 1, breaking
    -- the one-row-per-subscription guarantee every downstream query relies
    -- on (validated: 34,411 rows out = 34,411 unique subscription_ids in).
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
        CASE
            WHEN ar_valid_to IS NULL THEN 'never_enabled'
            WHEN ar_valid_to >= ended_at THEN 'stayed_enabled'
            ELSE 'disabled_before_expiry'
        END AS final_status,
        CASE WHEN ar_valid_to IS NOT NULL AND ar_valid_to < ended_at
             THEN date_diff('day', started_at, ar_valid_to) END AS days_to_disable,
        CASE WHEN ar_valid_to IS NOT NULL AND ar_valid_to < ended_at
             THEN date_diff('day', ar_valid_to, ended_at) END AS days_before_expiry_disabled,
        -- flags the 3 known-broken rows where the enable window predates
        -- started_at entirely - see Data Quality Findings in the write-up
        (ar_valid_to IS NOT NULL AND ar_valid_to >= started_at) OR ar_valid_to IS NULL AS is_clean_window
    FROM last_window
)
SELECT * FROM final_group
UNION ALL
SELECT
    subscription_id, payment_gateway, product_group, product_sub_group,
    product_slug, period_months, started_at, ended_at, billings_eur_excl_vat,
    n_windows, NULL, NULL, 'never_enabled', NULL, NULL, true
FROM no_record_rows

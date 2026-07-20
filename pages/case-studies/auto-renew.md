---
title: Auto-Renew Dynamics Analysis
---

A subscription-based hosting/domain provider needed to understand **when users tend to enable or disable their auto-renew**. The goal was to understand behavioral patterns and provide actionable insights and suggestions to improve the auto-renew rate, for non-technical stakeholders on the product team.

Key questions included:

- When do customers tend to enable or disable auto-renew?
- Is the bigger problem activation (never turning it on) or retention (turning it off later)?
- Which segments — product, plan length, price, payment method — have the healthiest auto-renew rates?

## Executive Summary

**Of the outcomes we can directly observe, active cancellation is the largest single group** — 37.4% of all subscriptions have a logged auto-renew ON event followed by a logged OFF event before their term ended. A further 26.0% have no auto-renew activation on record at all; the data doesn't let us determine whether that means an instant cancel or something else, so it's tracked as its own distinct category throughout, not folded into "cancelled" or "will renew" (see Assumptions & Limitations for why, and for a known data-tracking issue that inflates this category for older subscriptions specifically).

- **36.6%** of subscriptions stayed enabled through to their renewal date
- **37.4%** actively cancelled auto-renew before their term ended — a directly observed, logged event, worth **€45,786 (40.6% of all revenue tracked)**
- **26.0%** have no auto-renew activation on record — kept separate, cause not confirmed
- **€28,054** of that cancelled revenue sits in the single highest-leverage window: 12-month plans cancelled within 30 days of renewal — see Revenue at Risk below for a rough recovery-scenario estimate
- **53.3%** of 12-month cancellations happen within 30 days of the renewal date — the real signal (a blended figure across both plan lengths would be misleading, since a 1-month plan's entire term IS 30 days, making "within 30 days" trivially ~100% and meaningless for that group — see the Timing section)
- **12-month plans cancel at 2.75x the rate of 1-month plans** (39.1% vs 14.2%), despite starting with auto-renew on slightly *more* reliably
- **Retention rises steadily with price, no reversals** — from 33.0% at free up to 73.4% at €20+, more than doubling across the price range
- **Crypto-paid subscriptions almost never auto-renew (95.2% no record)** — a technical/platform constraint, not customer behavior
- A **data-tracking gap** for subscriptions purchased before March 2022 was identified — it inflates the "no record" rate for that period specifically, but those subscriptions are still included in every figure below (see Assumptions & Limitations)

## Data Schema

**Subscriptions table** (34,783 rows, 34,411 unique `subscription_id`)

| Column | Data Type | Description |
|---|---|---|
| subscription_id | INTEGER | ID of the subscription |
| payment_gateway | STRING | Payment gateway used (Checkout / Credorax / PayPal / crypto / etc.) |
| product_group | STRING | Broadest product category (domain / hosting / mail) |
| product_sub_group | STRING | Subset of product group |
| product_slug | STRING | Detailed product name |
| period_months | INTEGER | Plan duration in months |
| started_at | DATE | Subscription start date |
| ended_at | DATE | Subscription end date |
| is_auto_renew | BOOLEAN | TRUE if auto-renew is on |
| ar_valid_from | DATE | Date auto-renew was enabled |
| ar_valid_to | DATE | Date auto-renew was disabled |
| billings_eur_excl_vat | DECIMAL | Billed amount in EUR, excl. VAT |

**Important structural note:** this table is a *status-change log*, not one row per subscription. A subscription only gets more than one row if the customer toggled auto-renew off and back on more than once during the term (365 of 34,411 subscriptions do this — see the dedicated "Returning Customers" section below). All analysis below first collapses this into one final outcome per subscription.

## Assumptions and Limitations

**Data-tracking gap, pre-March 2022 — included, not excluded, but flagged.** Subscriptions purchased before March 2022 show a "no record" rate as high as 68% in some months, vs. a stable ~11-16% from March 2022 onward. No behavioral explanation fits a swing that large tied purely to purchase month — this looks like a logging/rollout gap in the `ar_valid_from`/`ar_valid_to` tracking mechanism, not real customer behavior. Rather than dropping these subscriptions, **every figure in this report includes the full dataset (34,411 subscriptions)** — the older cohort is simply more likely to land in the "no record" bucket than it should. Anywhere the "no record" share looks elevated, purchase-date mix is a likely contributor worth checking before concluding it's a behavioral finding.

**"No activation on record" treated as its own category, not merged into "cancelled":** for 26.0% of subscriptions, there is no enable event logged at all (no `ar_valid_from`/`ar_valid_to`). Given the record-keeping is *usually* (not *always*) on-by-default, this could mean the customer opted out essentially instantly, or it could mean this segment genuinely never had auto-renew set — both are consistent with the data. A same-day toggle test confirmed the system *can* log instant on/off pairs (142 real examples), which weakens but doesn't rule out the "too fast to log" theory; an hourly-level toggle can't be tested since dates, not timestamps, are the only granularity available. Kept as a separate, clearly-labeled category rather than assumed either way.

**Why the background info doesn't resolve this on its own — the "usually vs. never" gap.** The stated policy has two parts: auto-renew is *usually* on by default, and it's *never* disabled automatically absent user action. Read together, it's tempting to conclude "no record" must mean an instant user cancel — if a subscription really did start on, only a user action could turn it off, so a blank result would have to be that action happening too fast to log. But the logic only holds *if* the subscription started on in the first place, and "usually" is precisely the word that leaves room for exceptions to that default — subscriptions where the on-by-default step simply didn't apply. The "never auto-disabled" guarantee has nothing to say about that population, because it only describes what happens to something that was already enabled. Two direct tests were run against the stronger of the two readings (instant cancel): same-day toggles are proven to log correctly (142 real examples, ruling out "too fast to log" as a blanket explanation), and the group isn't disproportionately free/no-payment (ruling out a simple product-exemption story). Both came back "not disproven, but not confirmed either" — which is why this report doesn't pick a side, rather than a gap in reasoning.

**No customer/account-level ID.** Only `subscription_id` is available — there's no way to link multiple subscriptions to the same customer. All rates in this analysis are subscription-level, not customer-level; a customer with several subscriptions is counted once per subscription, and cross-product customer behavior (e.g. "does this person keep hosting on but cancel their domain?") can't be observed.

**No order-type / checkout-flow field.** Can't distinguish an original purchase from a renewal-generated continuation of the same underlying service, and can't confirm whether a declined-at-checkout auto-renew checkbox exists as a product feature.

**Nationality/gender-style demographic segmentation isn't available in this dataset** — segmentation here is limited to product, plan length, price, and payment gateway.

## Auto-Renew Outcomes by Segment

Every table below groups by `final_status`, which is derived from the raw columns as shown here. This base query is what every "SQL query used" snippet in this section is built on top of:

```sql
CREATE OR REPLACE TABLE sub_status AS

-- STEP 1: one row per enabled (ON) window per subscription
WITH true_rows AS (
    SELECT *
    FROM read_csv_auto('file.csv')
    WHERE is_auto_renew = true
),

-- STEP 2: keep only each subscription's MOST RECENT enabled window
last_window AS (
    SELECT *,
        row_number() OVER (PARTITION BY subscription_id ORDER BY ar_valid_from DESC) AS rn
    FROM true_rows
    QUALIFY rn = 1
),

-- STEP 3: subscriptions with NO is_auto_renew = true row at all
--         (no ON event, no OFF event, nothing logged)
no_record_rows AS (
    SELECT *
    FROM read_csv_auto('file.csv')
    WHERE is_auto_renew IS NULL
),

-- STEP 4: the classification step - this is what final_status means.
--         Applied to last_window only; no_record_rows are always 'never_enabled'
--         since they have no ar_valid_to to evaluate.
final_group AS (
    SELECT
        subscription_id, product_group, period_months, payment_gateway,
        billings_eur_excl_vat, started_at, ended_at, ar_valid_from, ar_valid_to,
        CASE
            WHEN ar_valid_to IS NULL THEN 'never_enabled'
            -- ON window's end date reaches (or passes) the subscription's own
            -- end date = auto-renew was still active when the term expired
            WHEN ar_valid_to >= ended_at THEN 'stayed_enabled'
            -- ON window ended BEFORE the subscription's own end date =
            -- a real, logged cancel event that happened ahead of expiry
            ELSE 'disabled_before_expiry'
        END AS final_status
    FROM last_window
)

SELECT * FROM final_group
UNION ALL
SELECT
    subscription_id, product_group, period_months, payment_gateway,
    billings_eur_excl_vat, started_at, ended_at,
    NULL, NULL, 'never_enabled'
FROM no_record_rows;
```

The three outcome labels used throughout this report map to `final_status` as: **"No activation on record"** = `never_enabled`, **"Actively cancelled before expiry"** = `disabled_before_expiry`, **"Stayed enabled"** = `stayed_enabled`.

**Edge case worth addressing directly: could a still-active, in-progress subscription (one that hasn't reached its renewal date yet) get miscounted as `never_enabled`?** The `ar_valid_to IS NULL` check only runs on rows already filtered to `is_auto_renew = true`, so this would only be a problem if an enabled-but-not-yet-renewed subscription could have a null `ar_valid_to`. Checked directly: **zero of the 25,838 enabled rows have a null `ar_valid_to`** — it's always populated, either with a real disable date or with the subscription's own `ended_at` as a placeholder for "still on, scheduled to stay on through expiry." Separately confirmed there are no in-progress subscriptions in this dataset at all: the latest `ended_at` (2023-12-31) and the latest `ar_valid_to` (2023-12-31) are identical, and every subscription's term falls fully within the data's date range. This is a closed, fully historical export, not a live snapshot with subscriptions still mid-term.

**Validated before use:** every subscription in the raw file lands in exactly one of the three segments, with no gaps and no duplicates.

| Check | Result |
|---|---|
| `sub_status` row count | 34,411 |
| Unique subscription_ids in raw file | 34,411 — matches exactly |
| Subscriptions appearing more than once | 0 |
| Subscriptions missing from `sub_status` entirely | 0 |
| Rows with a `final_status` outside the 3 labels | 0 |
| The 3 segments sum back to the total | 34,411 — matches |

**Consistency rule:** every segment breakdown in this report — by product, plan length, price, or payment gateway — is grouped off of this same `sub_status` table, not a separately re-derived classification. That's what keeps the three segment definitions identical everywhere they're used in this document.

### Overall

| Outcome | Subscriptions | % |
|---|---|---|
| Actively cancelled before expiry | 12,879 | 37.4% |
| Stayed enabled (will renew) | 12,587 | 36.6% |
| No activation on record | 8,945 | 26.0% |

<details>
<summary>SQL query used for the overall status split (self-contained, runnable on its own)</summary>

```sql
WITH true_rows AS (
    SELECT * FROM read_csv_auto('file.csv') WHERE is_auto_renew = true
),
last_window AS (
    SELECT *,
        row_number() OVER (PARTITION BY subscription_id ORDER BY ar_valid_from DESC) AS rn
    FROM true_rows
    QUALIFY rn = 1
),
no_record_rows AS (
    SELECT * FROM read_csv_auto('file.csv') WHERE is_auto_renew IS NULL
),
final_group AS (
    SELECT
        subscription_id, product_group, period_months, payment_gateway,
        billings_eur_excl_vat, started_at, ended_at, ar_valid_from, ar_valid_to,
        CASE
            WHEN ar_valid_to IS NULL THEN 'never_enabled'
            WHEN ar_valid_to >= ended_at THEN 'stayed_enabled'
            ELSE 'disabled_before_expiry'
        END AS final_status
    FROM last_window
),
sub_status AS (
    SELECT * FROM final_group
    UNION ALL
    SELECT
        subscription_id, product_group, period_months, payment_gateway,
        billings_eur_excl_vat, started_at, ended_at,
        NULL, NULL, 'never_enabled'
    FROM no_record_rows
)
SELECT final_status, count(*) AS n,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
FROM sub_status
GROUP BY 1 ORDER BY n DESC;
```
</details>

**Interpretation:** active cancellation and staying enabled are almost tied as the two largest outcomes, with "no record" a close third. Note the no-record share here (26.0%) is higher than it would be with only reliable-tracking data — see the Assumptions note on the pre-March-2022 gap.

### Revenue at Risk

Percentages alone don't say how much money is actually on the line. The billed amount for each subscription's *current* term (`billings_eur_excl_vat`) is used here as a reasonable stand-in for what the *next* term would bill at, assuming similar pricing on renewal.

| Outcome | Subscriptions | Revenue | Avg. per subscription |
|---|---|---|---|
| Stayed enabled (will renew) | 12,587 | €52,434.61 | €4.17 |
| **Actively cancelled before expiry** | **12,879** | **€45,786.22** | €3.56 |
| No activation on record | 8,945 | €14,434.93 | €1.61 |
| **Total** | **34,411** | **€112,655.76** | — |

**€45,786 — 40.6% of all revenue tracked in this dataset — is tied to subscriptions that actively cancelled auto-renew.** Narrowing to just the group the top recommendation targets (12-month plans that cancelled): **12,560 subscriptions, €44,999 in revenue.** Of that, **€28,054 (6,689 subscriptions) is tied to cancellations that happened in the final 30 days before renewal** — the highest-leverage save window identified in the Timing section above.

**A rough, illustrative recovery scenario** (for calibrating expected impact, not a forecast): if a save flow targeted at that 30-day window recovered just **10%** of those 6,689 subscriptions, that's roughly **669 saved subscriptions and €2,805 in retained annual revenue** — recurring each year those customers keep renewing. At a **20%** recovery rate, that doubles to **~€5,610/year**. These are back-of-envelope numbers meant to size the opportunity, not a committed projection — the real recovery rate depends entirely on what the save flow actually offers.

<details>
<summary>SQL query used for the revenue breakdown (self-contained, runnable on its own)</summary>

```sql
WITH true_rows AS (
    SELECT * FROM read_csv_auto('file.csv') WHERE is_auto_renew = true
),
last_window AS (
    SELECT *,
        row_number() OVER (PARTITION BY subscription_id ORDER BY ar_valid_from DESC) AS rn
    FROM true_rows
    QUALIFY rn = 1
),
final_group AS (
    SELECT
        subscription_id, billings_eur_excl_vat, period_months, started_at, ended_at, ar_valid_to,
        CASE
            WHEN ar_valid_to IS NULL THEN 'never_enabled'
            WHEN ar_valid_to >= ended_at THEN 'stayed_enabled'
            ELSE 'disabled_before_expiry'
        END AS final_status,
        CASE WHEN ar_valid_to IS NOT NULL AND ar_valid_to < ended_at
             THEN date_diff('day', ar_valid_to, ended_at) END AS days_before_expiry_disabled
    FROM last_window
),
sub_status AS (
    SELECT * FROM final_group
    UNION ALL
    SELECT subscription_id, billings_eur_excl_vat, period_months, started_at, ended_at,
           NULL, 'never_enabled', NULL
    FROM read_csv_auto('file.csv') WHERE is_auto_renew IS NULL
)
-- overall revenue by outcome
SELECT final_status, count(*) AS n, round(sum(billings_eur_excl_vat), 2) AS revenue
FROM sub_status GROUP BY 1 ORDER BY revenue DESC;

-- revenue tied to the highest-leverage save window (12-month, cancelled within 30 days of renewal)
SELECT count(*) AS n, round(sum(billings_eur_excl_vat), 2) AS revenue
FROM sub_status
WHERE final_status = 'disabled_before_expiry' AND period_months = 12 AND days_before_expiry_disabled <= 30;
```
</details>

### By Product Group

| Product | Subscriptions | Stayed enabled | Cancelled | No record |
|---|---|---|---|---|
| Domain | 19,001 | 29.1% | 33.4% | 37.5% |
| Hosting | 14,444 | 45.8% | 44.3% | 9.9% |
| Mail | 966 | 45.9% | 13.8% | 40.4% |

<details>
<summary>SQL query used for the product group breakdown (self-contained, runnable on its own)</summary>

```sql
WITH true_rows AS (
    SELECT * FROM read_csv_auto('file.csv') WHERE is_auto_renew = true
),
last_window AS (
    SELECT *,
        row_number() OVER (PARTITION BY subscription_id ORDER BY ar_valid_from DESC) AS rn
    FROM true_rows
    QUALIFY rn = 1
),
no_record_rows AS (
    SELECT * FROM read_csv_auto('file.csv') WHERE is_auto_renew IS NULL
),
final_group AS (
    SELECT
        subscription_id, product_group, period_months, payment_gateway,
        billings_eur_excl_vat, started_at, ended_at, ar_valid_from, ar_valid_to,
        CASE
            WHEN ar_valid_to IS NULL THEN 'never_enabled'
            WHEN ar_valid_to >= ended_at THEN 'stayed_enabled'
            ELSE 'disabled_before_expiry'
        END AS final_status
    FROM last_window
),
sub_status AS (
    SELECT * FROM final_group
    UNION ALL
    SELECT
        subscription_id, product_group, period_months, payment_gateway,
        billings_eur_excl_vat, started_at, ended_at,
        NULL, NULL, 'never_enabled'
    FROM no_record_rows
)
SELECT product_group, final_status, count(*) AS n,
       round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY product_group), 1) AS pct
FROM sub_status
GROUP BY 1, 2 ORDER BY 1, n DESC;
```
</details>

**Hosting has both the best retention and the lowest no-record rate of any product** — 45.8% stay enabled, only 9.9% have no record. **Domain and mail both show high no-record shares (37.5% and 40.4%)** — domains skew heavily toward the pre-March-2022 cohort (many are cheap, early, high-volume purchases), so its no-record number is likely inflated by the tracking gap; mail's smaller sample (966) makes it harder to say the same with confidence, so it's flagged as a lead rather than a settled finding.

### By Plan Length

| Plan | Subscriptions | Stayed enabled | Cancelled | No record |
|---|---|---|---|---|
| 1-month | 2,253 | 57.8% | 14.2% | 28.1% |
| 12-month | 32,158 | 35.1% | 39.1% | 25.9% |

<details>
<summary>SQL query used for the plan length breakdown (self-contained, runnable on its own)</summary>

```sql
WITH true_rows AS (
    SELECT * FROM read_csv_auto('file.csv') WHERE is_auto_renew = true
),
last_window AS (
    SELECT *,
        row_number() OVER (PARTITION BY subscription_id ORDER BY ar_valid_from DESC) AS rn
    FROM true_rows
    QUALIFY rn = 1
),
no_record_rows AS (
    SELECT * FROM read_csv_auto('file.csv') WHERE is_auto_renew IS NULL
),
final_group AS (
    SELECT
        subscription_id, product_group, period_months, payment_gateway,
        billings_eur_excl_vat, started_at, ended_at, ar_valid_from, ar_valid_to,
        CASE
            WHEN ar_valid_to IS NULL THEN 'never_enabled'
            WHEN ar_valid_to >= ended_at THEN 'stayed_enabled'
            ELSE 'disabled_before_expiry'
        END AS final_status
    FROM last_window
),
sub_status AS (
    SELECT * FROM final_group
    UNION ALL
    SELECT
        subscription_id, product_group, period_months, payment_gateway,
        billings_eur_excl_vat, started_at, ended_at,
        NULL, NULL, 'never_enabled'
    FROM no_record_rows
)
SELECT period_months, final_status, count(*) AS n,
       round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY period_months), 1) AS pct
FROM sub_status
GROUP BY 1, 2 ORDER BY 1, n DESC;
```
</details>

**Annual plans activate auto-renew about as reliably as monthly plans (25.9% vs 28.1% no-record — actually slightly better) but get cancelled at 2.75x the rate afterward.** Since 93.5% of the full dataset is 12-month plans, this single pattern describes what happens to the overwhelming majority of the customer base. The large upfront lump-sum renewal charge is the most likely trigger — see the Timing section below for how sharply this concentrates near the renewal date.

### By Price Range

**Bracket choice, checked against the real data first:** rather than round-number cuts, the boundaries below follow where the actual price distribution clusters and thins out. 95.4% of all subscriptions are under €10 (prices bunch hard around specific SKU price points — €0, €5.73, €0.27, etc.), then the tail thins fast past €20 (only 504 subscriptions total above that, too sparse to split further). The old €0.01-2 / €2-5 split was tested first and rejected — it cut through the middle of that main cluster and produced a non-monotonic, hard-to-explain result (the €2-5 bucket outperformed €5-10, which didn't make sense). The scheme below removes that artifact.

| Price | Subscriptions | Stayed enabled | Cancelled | No record |
|---|---|---|---|---|
| Free (€0) | 5,854 | 33.0% | 30.0% | 37.0% |
| €0.01 – 5 | 17,316 | 33.6% | 32.7% | 33.7% |
| €5 – 10 | 9,675 | 39.7% | 52.1% | 8.2% |
| €10 – 20 | 1,062 | 58.5% | 29.9% | 11.6% |
| €20+ | 504 | **73.4%** | 19.0% | 7.5% |

<details>
<summary>SQL query used for the price range breakdown (self-contained, runnable on its own)</summary>

```sql
WITH true_rows AS (
    SELECT * FROM read_csv_auto('file.csv') WHERE is_auto_renew = true
),
last_window AS (
    SELECT *,
        row_number() OVER (PARTITION BY subscription_id ORDER BY ar_valid_from DESC) AS rn
    FROM true_rows
    QUALIFY rn = 1
),
no_record_rows AS (
    SELECT * FROM read_csv_auto('file.csv') WHERE is_auto_renew IS NULL
),
final_group AS (
    SELECT
        subscription_id, product_group, period_months, payment_gateway,
        billings_eur_excl_vat, started_at, ended_at, ar_valid_from, ar_valid_to,
        CASE
            WHEN ar_valid_to IS NULL THEN 'never_enabled'
            WHEN ar_valid_to >= ended_at THEN 'stayed_enabled'
            ELSE 'disabled_before_expiry'
        END AS final_status
    FROM last_window
),
sub_status AS (
    SELECT * FROM final_group
    UNION ALL
    SELECT
        subscription_id, product_group, period_months, payment_gateway,
        billings_eur_excl_vat, started_at, ended_at,
        NULL, NULL, 'never_enabled'
    FROM no_record_rows
)
SELECT
  CASE
    WHEN billings_eur_excl_vat = 0 THEN '1_free'
    WHEN billings_eur_excl_vat < 5 THEN '2_0.01-5'
    WHEN billings_eur_excl_vat < 10 THEN '3_5-10'
    WHEN billings_eur_excl_vat < 20 THEN '4_10-20'
    ELSE '5_20+'
  END AS price_bucket,
  final_status, count(*) AS n,
  round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY price_bucket), 1) AS pct
FROM sub_status
GROUP BY 1, 2 ORDER BY 1, 2;
```
</details>

**Retention rises steadily and cleanly with price — no reversals, every bracket up is a bracket better.** Stayed-enabled climbs from 33.0% (free) to 73.4% (€20+), more than doubling. The cheapest brackets (free and €0.01-5, together over two-thirds of the dataset) also show the highest no-record rates — consistent with these buckets being dominated by cheap domains, which also skew toward the pre-March-2022 tracking-gap cohort. A separate correlation check (price as a continuous value vs. "stayed enabled") found a real but modest relationship (+0.098 across the whole range) — the bracket view makes the effect much easier to see than the correlation coefficient alone suggests, because the relationship is concentrated at the high end rather than spread evenly.

**Checked the €20+ bucket for outliers before trusting it** (max price in the dataset is €109.41, and n=504 is small enough that one extreme value could skew it): 494 of the 504 sit in a tight €20-40 range (retention **74.0%**), only 16 sit above €40 (retention 53.3%, sample too small to trust on its own). The outliers don't inflate the headline 73.4% figure — if anything they pull it down slightly, since the €20-40 core alone retains even better than the blended number suggests.

### By Payment Gateway Type

**Coverage check first:** Card/bank and crypto alone don't add up to 100% of subscriptions — they're 85.1% of the 34,411 subscriptions used throughout this report (28,207 + 1,074, same subscription-level basis as every other table here). The remaining ~15% splits into two distinct groups, added below rather than left out, since a reader would otherwise reasonably assume the two shown rows were the whole picture.

| Gateway type | Subscriptions | Stayed enabled | Cancelled | No record |
|---|---|---|---|---|
| Card / bank | 28,207 | 38.8% | 39.9% | 21.3% |
| Crypto | 1,074 | 2.0% | 2.9% | **95.2%** |
| No gateway on file | 5,022 | 31.8% | 31.5% | 36.7% |
| Other (balance, dlocal, ProcessOut, Braintree, etc.) | 108 | 18.5% | 16.7% | **64.8%** |

**Two more real patterns, not just a rounding gap to patch over:**
- **"No gateway on file" (5,022 subscriptions, 14.6%)** — not a small edge case, and its no-record rate (36.7%) is meaningfully higher than card/bank's (21.3%). Makes sense directionally: no stored payment method plausibly limits whether auto-renew can be meaningfully turned on, similar to the free-domain delayed-activation pattern found elsewhere in this analysis — though this group also includes real paid transactions, so it isn't fully explained by that alone.
- **"Other" gateways (108 subscriptions, mostly `balance` and a handful of alternate processors) have the second-highest no-record rate in the whole table (64.8%)** — but the sample is small enough (108) that this should be read as a lead, not a settled pattern.

<details>
<summary>SQL query used for the payment gateway breakdown (self-contained, runnable on its own)</summary>

```sql
WITH true_rows AS (
    SELECT * FROM read_csv_auto('file.csv') WHERE is_auto_renew = true
),
last_window AS (
    SELECT *,
        row_number() OVER (PARTITION BY subscription_id ORDER BY ar_valid_from DESC) AS rn
    FROM true_rows
    QUALIFY rn = 1
),
no_record_rows AS (
    SELECT * FROM read_csv_auto('file.csv') WHERE is_auto_renew IS NULL
),
final_group AS (
    SELECT
        subscription_id, product_group, period_months, payment_gateway,
        billings_eur_excl_vat, started_at, ended_at, ar_valid_from, ar_valid_to,
        CASE
            WHEN ar_valid_to IS NULL THEN 'never_enabled'
            WHEN ar_valid_to >= ended_at THEN 'stayed_enabled'
            ELSE 'disabled_before_expiry'
        END AS final_status
    FROM last_window
),
sub_status AS (
    SELECT * FROM final_group
    UNION ALL
    SELECT
        subscription_id, product_group, period_months, payment_gateway,
        billings_eur_excl_vat, started_at, ended_at,
        NULL, NULL, 'never_enabled'
    FROM no_record_rows
)
SELECT
  CASE WHEN payment_gateway IN ('coingate','coinpayments') THEN 'crypto'
       WHEN payment_gateway IN ('checkout','credorax','paypal') THEN 'card_or_bank'
       WHEN payment_gateway IS NULL THEN 'no_gateway_on_file'
       ELSE 'other' END AS gateway_type,
  final_status, count(*) AS n,
  round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY
    CASE WHEN payment_gateway IN ('coingate','coinpayments') THEN 'crypto'
         WHEN payment_gateway IN ('checkout','credorax','paypal') THEN 'card_or_bank'
         WHEN payment_gateway IS NULL THEN 'no_gateway_on_file'
         ELSE 'other' END), 1) AS pct
FROM sub_status
GROUP BY 1, 2 ORDER BY 1, n DESC;

-- coverage check: confirm all 4 groups sum to the full dataset
SELECT
  CASE WHEN payment_gateway IN ('coingate','coinpayments') THEN 'crypto'
       WHEN payment_gateway IN ('checkout','credorax','paypal') THEN 'card_or_bank'
       WHEN payment_gateway IS NULL THEN 'no_gateway_on_file'
       ELSE 'other' END AS gateway_type,
  count(*) AS n
FROM sub_status GROUP BY 1;
```
</details>

**Crypto is very likely a technical constraint, not a behavioral signal** — crypto payments generally can't be stored for automatic re-billing the way a card can. This pattern is stable regardless of the tracking-gap issue (crypto gateways are a small, distinct population). Recommend excluding crypto from auto-renew health metrics going forward, and reporting it as a separate "renewability by payment method" line instead.

## Timing and Duration of Cancellation

Two related questions, both only about the "actively cancelled" group (12,879 subscriptions) — this group is unaffected by the no-record ambiguity, since every one of these has a directly observed ON event and OFF event. **Both are split by plan length**, since "30 days before renewal" or "days kept on" mean very different things for a 30-day term vs. a 365-day term — a blended figure across both plan lengths would be misleading (a 1-month plan is nearly guaranteed to fall "within 30 days of renewal" simply because the whole term is that short).

### How close to the renewal date did the cancellation happen?

**1-month plans** (n=316; excludes 3 subscriptions with a data error — see Data Quality Findings)

| Timing | Count | % |
|---|---|---|
| 0-3 days before renewal | 29 | 9.2% |
| 4-7 days before | 15 | 4.7% |
| 8-14 days before | 125 | 39.6% |
| 15-30 days before | 147 | 46.5% |

These 4 buckets cover the entire possible range (0-30 days) and necessarily sum to 100% — every single 1-month cancellation is, trivially, "within 30 days of renewal," because the whole term only lasts 30 days. That's exactly why this framing is meaningless here: there's no room for a "last-minute vs. not" distinction to exist in a window this short. The 15-30 day bucket being the largest single bucket (46.5%) is a real observation; "within 30 days" as a category is not.

**12-month plans** (n=12,560)

| Timing | Count | % |
|---|---|---|
| 0-3 days before renewal | 1,470 | 11.7% |
| 4-14 days before | 1,930 | 15.4% |
| 15-30 days before | 3,289 | 26.2% |
| 31-90 days before | 2,007 | 16.0% |
| 90+ days before | 3,864 | 30.8% |
| **≤30 days combined** | **6,689** | **53.3%** |

This is the real signal: over half of all annual-plan cancellations happen in the final 30 days before renewal — a plausible reaction to renewal-reminder emails or notifications.

### How long did the customer keep auto-renew on before cancelling?

**1-month plans** (max possible: 30 days, n=316)

| Duration kept on | Count | % |
|---|---|---|
| 0-3 days | 44 | 13.9% |
| 4-7 days | 24 | 7.6% |
| 8-14 days | 73 | 23.1% |
| 15-21 days | 125 | 39.6% |
| 22-30 days | 50 | 15.8% |

Mean: 14.3 days · Median: 16.0 days — roughly the halfway point of the term, fairly spread out.

**12-month plans** (max possible: 364 days, n=12,560)

| Duration kept on | Count | % |
|---|---|---|
| 0-7 days | 652 | 5.2% |
| 8-30 days | 609 | 4.8% |
| 31-90 days | 685 | 5.5% |
| 91-180 days | 831 | 6.6% |
| 181-270 days | 1,011 | 8.0% |
| **271-365 days** | **8,772** | **69.8%** |

Mean: 270.5 days · Median: 336.0 days — heavily back-loaded to the final quarter of the year.

<details>
<summary>SQL query used for the timing and duration analysis (self-contained, runnable on its own)</summary>

Both queries need `days_to_disable` and `days_before_expiry_disabled`, which the base `sub_status` CTE used elsewhere in this doc doesn't compute — this version's `final_group` step includes them, since only `disabled_before_expiry` subscriptions need these values.

```sql
-- timing before renewal, split by plan length
WITH true_rows AS (
    SELECT * FROM read_csv_auto('file.csv') WHERE is_auto_renew = true
),
last_window AS (
    SELECT *,
        row_number() OVER (PARTITION BY subscription_id ORDER BY ar_valid_from DESC) AS rn
    FROM true_rows
    QUALIFY rn = 1
),
no_record_rows AS (
    SELECT * FROM read_csv_auto('file.csv') WHERE is_auto_renew IS NULL
),
final_group AS (
    SELECT
        subscription_id, product_group, period_months, payment_gateway,
        billings_eur_excl_vat, started_at, ended_at, ar_valid_from, ar_valid_to,
        CASE
            WHEN ar_valid_to IS NULL THEN 'never_enabled'
            WHEN ar_valid_to >= ended_at THEN 'stayed_enabled'
            ELSE 'disabled_before_expiry'
        END AS final_status,
        CASE WHEN ar_valid_to IS NOT NULL AND ar_valid_to < ended_at
             THEN date_diff('day', started_at, ar_valid_to) END AS days_to_disable,
        CASE WHEN ar_valid_to IS NOT NULL AND ar_valid_to < ended_at
             THEN date_diff('day', ar_valid_to, ended_at) END AS days_before_expiry_disabled
    FROM last_window
),
sub_status AS (
    SELECT * FROM final_group
    UNION ALL
    SELECT
        subscription_id, product_group, period_months, payment_gateway,
        billings_eur_excl_vat, started_at, ended_at,
        NULL, NULL, 'never_enabled', NULL, NULL
    FROM no_record_rows
)
SELECT period_months,
  CASE
    WHEN days_before_expiry_disabled <= 3  THEN '0-3'
    WHEN days_before_expiry_disabled <= 14 THEN '4-14'
    WHEN days_before_expiry_disabled <= 30 THEN '15-30'
    WHEN days_before_expiry_disabled <= 90 THEN '31-90'
    ELSE '90+'
  END AS bucket, count(*) AS n,
  round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY period_months), 1) AS pct
FROM sub_status
WHERE final_status = 'disabled_before_expiry'
GROUP BY 1, 2 ORDER BY 1, 2;


-- duration kept on before cancelling, split by plan length
-- (same sub_status CTE definition as above, repeated since each
--  statement needs its own WITH clause)
WITH true_rows AS (
    SELECT * FROM read_csv_auto('file.csv') WHERE is_auto_renew = true
),
last_window AS (
    SELECT *,
        row_number() OVER (PARTITION BY subscription_id ORDER BY ar_valid_from DESC) AS rn
    FROM true_rows
    QUALIFY rn = 1
),
no_record_rows AS (
    SELECT * FROM read_csv_auto('file.csv') WHERE is_auto_renew IS NULL
),
final_group AS (
    SELECT
        subscription_id, product_group, period_months, payment_gateway,
        billings_eur_excl_vat, started_at, ended_at, ar_valid_from, ar_valid_to,
        CASE
            WHEN ar_valid_to IS NULL THEN 'never_enabled'
            WHEN ar_valid_to >= ended_at THEN 'stayed_enabled'
            ELSE 'disabled_before_expiry'
        END AS final_status,
        CASE WHEN ar_valid_to IS NOT NULL AND ar_valid_to < ended_at
             THEN date_diff('day', started_at, ar_valid_to) END AS days_to_disable,
        CASE WHEN ar_valid_to IS NOT NULL AND ar_valid_to < ended_at
             THEN date_diff('day', ar_valid_to, ended_at) END AS days_before_expiry_disabled
    FROM last_window
),
sub_status AS (
    SELECT * FROM final_group
    UNION ALL
    SELECT
        subscription_id, product_group, period_months, payment_gateway,
        billings_eur_excl_vat, started_at, ended_at,
        NULL, NULL, 'never_enabled', NULL, NULL
    FROM no_record_rows
)
SELECT period_months,
  CASE
    WHEN days_to_disable <= 7 THEN '0-7'
    WHEN days_to_disable <= 30 THEN '8-30'
    WHEN days_to_disable <= 90 THEN '31-90'
    WHEN days_to_disable <= 180 THEN '91-180'
    WHEN days_to_disable <= 270 THEN '181-270'
    ELSE '271-365'
  END AS bucket, count(*) AS n,
  round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY period_months), 1) AS pct
FROM sub_status
WHERE final_status = 'disabled_before_expiry' AND days_to_disable >= 0
GROUP BY 1, 2 ORDER BY 1, 2;
```
</details>

**The two plan types tell genuinely different stories once separated properly.** Monthly cancellations are fairly spread out across the term. Annual cancellations are massively concentrated in the final 3 months (69.8% of them by duration-kept-on, 53.3% by proximity-to-renewal) — both views agree the trigger is specifically the size and timing of the annual renewal charge, not a general late-term pattern.

*(Note: 3 subscriptions with an impossible negative duration — their logged auto-renew windows predate the subscription's own start date — were excluded from both the timing and duration tables above as a data error. This is what accounts for the 1-month group's count dropping from 319 total cancelled subscriptions to 316 in both tables. See Data Quality Findings below for the full detail on this bug.)*

## Returning Customers: Subscriptions That Toggled Auto-Renew More Than Once

Everything above uses each subscription's *most recent* enable window to determine its outcome (see the `QUALIFY rn = 1` step in the base query). That discards a small but distinct group worth looking at on its own: subscriptions where the customer switched auto-renew off, then back on, one or more times — effectively cancelling and reconsidering within the same term.

| Number of ON windows | Subscriptions |
|---|---|
| 1 (never toggled back) | 34,046 |
| 2 | 361 |
| 3 | 2 |
| 4 | 1 |
| 5 | 1 |
| **Total that toggled more than once** | **365** (1.1% of all subscriptions) |

**These "returners" end up far more likely to stay enabled than everyone else:**

| Group | Stayed enabled | Cancelled |
|---|---|---|
| Toggled only once (never came back) | 49.1% | 50.9% |
| **Toggled more than once (came back at least once)** | **68.5%** | 31.5% |

<details>
<summary>SQL query used for the returning-customer analysis (self-contained, runnable on its own)</summary>

```sql
WITH true_rows AS (
    SELECT *,
        count(*) OVER (PARTITION BY subscription_id) AS n_windows
    FROM read_csv_auto('file.csv')
    WHERE is_auto_renew = true
),
last_window AS (
    SELECT *,
        row_number() OVER (PARTITION BY subscription_id ORDER BY ar_valid_from DESC) AS rn
    FROM true_rows
    QUALIFY rn = 1
),
final_group AS (
    SELECT
        subscription_id, product_group, period_months, n_windows,
        CASE
            WHEN ar_valid_to IS NULL THEN 'never_enabled'
            WHEN ar_valid_to >= ended_at THEN 'stayed_enabled'
            ELSE 'disabled_before_expiry'
        END AS final_status
    FROM last_window
)
-- distribution of toggle counts
SELECT n_windows, count(*) AS n FROM final_group GROUP BY 1 ORDER BY 1;

-- outcome by toggle-back status (re-run the CTEs above, then:)
-- SELECT
--   CASE WHEN n_windows > 1 THEN 'toggled_multiple_times' ELSE 'single_window' END AS grp,
--   final_status, count(*) AS n,
--   round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY
--     CASE WHEN n_windows > 1 THEN 'toggled_multiple_times' ELSE 'single_window' END), 1) AS pct
-- FROM final_group
-- GROUP BY 1, 2 ORDER BY 1, 2;
```
</details>

**Who toggles back, proportionally (not just raw counts):**

| Segment | Total | Toggled more than once | Rate |
|---|---|---|---|
| 12-month plans | 32,158 | 359 | **1.12%** |
| 1-month plans | 2,253 | 6 | 0.27% |
| Domain | 19,001 | 249 | **1.31%** |
| Hosting | 14,444 | 114 | 0.79% |
| Mail | 966 | 2 | 0.21% |

12-month plans toggle back at over 4x the rate of monthly plans, even after adjusting for the fact that there are far more of them — this isn't just a volume effect. Domain leads among products.

**Why this matters:** these customers already showed intent to cancel once, then changed their mind — something brought them back (a reminder, a discount, reconsidering the value). At 68.5% eventual retention, more than double the single-toggle group's rate, whatever prompted the re-enable is worth understanding, since it may point to a cheap, repeatable save tactic that's already working on a small scale and could potentially be applied more broadly to the much larger group that cancels and never reconsiders.

## Seasonality

**Important limit up front:** the reliable cohort only spans March–December 2022 — 10 months, not multiple full years. That's enough to describe *this year's* pattern but not enough to prove it repeats annually. Treat this as a real, measured pattern worth watching, not a confirmed seasonal law.

For 12-month plans, the renewal date falls in the same calendar month as the original purchase, one year later — so purchase-month and renewal-month seasonality are the same question. Grouping by that month reveals real swings:

| Signup / renewal month | Subscriptions | Stayed enabled | Cancelled |
|---|---|---|---|
| March | 1,368 | **55.4%** | 44.6% |
| April | 1,315 | 45.5% | 54.5% |
| May | 1,389 | 40.5% | 59.5% |
| June | 1,463 | 34.4% | 65.6% |
| **July** | 1,422 | **33.3%** | 66.7% |
| August | 1,228 | 37.6% | 62.4% |
| September | 1,151 | 52.1% | 47.9% |
| October | 1,390 | 39.4% | 60.6% |
| **November** | 2,241 | **33.6%** | 66.4% |
| December | 1,833 | 37.3% | 62.7% |

<details>
<summary>SQL query used for the seasonality analysis (self-contained, runnable on its own)</summary>

```sql
WITH true_rows AS (
    SELECT * FROM read_csv_auto('file.csv') WHERE is_auto_renew = true
),
last_window AS (
    SELECT *,
        row_number() OVER (PARTITION BY subscription_id ORDER BY ar_valid_from DESC) AS rn
    FROM true_rows
    QUALIFY rn = 1
),
final_group AS (
    SELECT
        subscription_id, period_months, started_at, ended_at,
        CASE
            WHEN ar_valid_to IS NULL THEN 'never_enabled'
            WHEN ar_valid_to >= ended_at THEN 'stayed_enabled'
            ELSE 'disabled_before_expiry'
        END AS final_status
    FROM last_window
)
SELECT strftime(ended_at, '%m-%b') AS renewal_month, count(*) AS total,
  round(100.0 * sum(CASE WHEN final_status = 'stayed_enabled' THEN 1 ELSE 0 END) / count(*), 1) AS stayed_pct,
  round(100.0 * sum(CASE WHEN final_status = 'disabled_before_expiry' THEN 1 ELSE 0 END) / count(*), 1) AS cancelled_pct
FROM final_group
WHERE started_at >= '2022-03-01' AND period_months = 12 AND final_status != 'never_enabled'
GROUP BY 1 ORDER BY 1;
```
</details>

**Two things stand out:**

1. **November is both the highest-volume signup month (2,241 — 55-95% above the ~1,200-1,460 baseline of other months) and one of the two worst-retaining cohorts (33.6% stayed).** November signups line up with Black Friday, and the pattern fits: promotional, discount-driven signups tend to attract more price-sensitive customers who are less likely to still want the service — or the same price — a year later. This means the single biggest acquisition month is also disproportionately contributing to the churn problem described throughout this report.
2. **March and September are the strongest cohorts (55.4% and 52.1% stayed)** — no obvious promotional driver behind either, which makes them a useful contrast: whatever's different about customers acquired then (less discount-driven, more deliberate?) is worth understanding as a model for the weaker months, though this data alone can't say why.

June/July also underperforms (33-38% stayed) without an obvious promotional explanation — flagged as a real pattern, not yet an explained one.

## Data Quality Findings

Four distinct issues surfaced during analysis, kept separate from the behavioral findings above since none of them changed the core conclusions but all are worth reporting to the data/engineering team.

**Tracking gap, pre-March 2022.** See Assumptions & Limitations above — a likely rollout gap in the `ar_valid_from`/`ar_valid_to` logging mechanism, not a product or customer issue. Included in all figures, not excluded, but inflates "no record" for that period.

**18 broken records, isolated to `.es` domains.** These rows have `ar_valid_from` *after* `ar_valid_to` — a logically impossible order. All 18 are `domain:.es`, 61% are free/promotional domains, and several share identical `ar_valid_from` dates across unrelated subscriptions (e.g. four different subscriptions all show `2023-03-15`). This pattern points to a batch job writing an incorrect run-date into old, already-closed subscription records rather than any real customer action — recommended as a direct bug report.

**3 broken records, a separate bug, isolated to monthly `hosting:hostinger_premium`.** These rows have a logged auto-renew window that predates the subscription's own start date entirely (e.g. a subscription starting 2022-08-03 with its window running 2022-07-03 to 2022-07-20 — three weeks before it existed). Distinct signature from the `.es` bug above: chronological order within the window is valid (`ar_valid_from < ar_valid_to`), just the whole window sits before `started_at`. All 3 are 1-month plans, all priced at exactly the same €2.4456, across 3 different payment gateways — the identical price across unrelated transactions suggests these may be linked to a specific historical pricing tier or a migration artifact, not independent customer actions. Excluded from the timing and duration tables above.

**~1,900 delayed-activation records.** Auto-renew turns on some time after `started_at` rather than immediately. About 29% of this group is a 0-1 day gap (likely date-rounding noise, not a real delay). The remaining, more meaningful delays (8 days to several months) are concentrated in free/promotional domains with no payment gateway on file — consistent with "auto-renew can't meaningfully activate until a real payment method is attached," which for some customers happens weeks after claiming a free domain.

**5 unexpected free (€0) hosting/mail records.** Hosting and mail are otherwise almost never free (0-0.2% of records). 2 of the 5 were paid via internal account balance (plausible comp/credit). The other 3 were paid via real card gateways, with 2 of the 3 starting on 2022-11-24 — Black Friday — suggesting a promotional campaign, though a pricing bug can't be ruled out from this data alone.

**Additional checks that came back clean, stated explicitly rather than left assumed:**
- `period_months` has only 2 values in the entire dataset (1 and 12) — confirmed exhaustive, no 3/6-month plans silently dropped (2,259 + 32,524 = 34,783, the exact row count).
- Term length matches `period_months` in every row: 1-month terms run 28-31 actual days (normal calendar variation), 12-month terms run exactly 365 days, always — no plan-change events or truncated/extended terms hiding in the data.
- `product_group`, `product_sub_group`, `product_slug`, and `billings_eur_excl_vat` have zero nulls. `payment_gateway` has 5,079 nulls, already accounted for throughout (shown as "(none)" rather than silently dropped from any table).

## Conclusions and Recommendations

**Build a save flow for the 15-30 day pre-renewal window, targeted at 12-month plans specifically.** This is the single biggest, most universal lever available: 39.1% of annual subscriptions actively cancel, over half of those cancellations happen in the final 30 days, and the pattern holds consistently across domain and hosting alike. €28,054 in current-term revenue sits in this exact window (6,689 subscriptions) — recovering even 10% of them is a rough but real ~€2,805/year, recurring annually for every customer retained. A targeted intervention here — a "keep your price locked in" nudge, a small loyalty discount, or clearer messaging about what happens at expiry — reaches the widest population of any single fix. (Note: don't apply this same "30 days" framing to monthly plans — it doesn't mean the same thing there.)

**Soften the annual renewal "sticker shock."** Annual plans get cancelled at 2.75x the rate of monthly plans despite activating just as reliably at purchase — the large upfront charge is the likely trigger. Consider an early reminder with the exact amount and date, or an installment option for the annual renewal.

**Investigate the domain and mail no-record rates, but confirm the tracking-gap contribution first.** Both products show elevated "no record" shares (37.5% and 40.4%). Before treating this as a product/flow issue, check how much of each is explained by purchase-date mix (domains and mail skew toward the less-reliable pre-March-2022 cohort) — hosting, which skews more recent, has a much lower no-record rate (9.9%) and may simply be a cleaner-tracked product rather than a behaviorally different one.

**Exclude crypto payments from auto-renew health metrics.** Crypto-paid subscriptions are very likely technically incapable of auto-renewing rather than behaviorally opting out — blending them into the main metric understates the real renewability of payment methods that can actually renew.

**Fix the underlying tracking gap and the `.es` domain batch-job bug.** Both are reported above as concrete, isolated engineering issues, separate from the behavioral recommendations — worth fixing before any future auto-renew reporting relies on this pipeline again.

**Give the November (Black Friday) cohort a dedicated retention plan.** It's the single largest signup month by a wide margin and one of the two worst-retaining (33.6% stayed) — €6,076 in revenue tied to its 1,488 cancelled subscriptions alone. This is a case where the acquisition channel that brings in the most customers is also disproportionately fueling the churn problem — the pre-renewal save flow (recommendation #1) is likely most valuable if targeted at this cohort specifically. Worth confirming this repeats in future years before treating it as a permanent seasonal rule, since the current data only covers one year.

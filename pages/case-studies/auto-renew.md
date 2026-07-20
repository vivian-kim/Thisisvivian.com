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
- **37.4%** actively cancelled auto-renew before their term ended — a directly observed, logged event
- **26.0%** have no auto-renew activation on record — kept separate, cause not confirmed
- **54.3%** of active cancellations happen within 30 days of the renewal date — but this figure is dominated by 12-month plans; for those specifically it's 53.3%, while for 1-month plans it's 95.9% (nearly meaningless on its own, since the entire term is only 30 days — see the Timing section)
- **12-month plans cancel at 2.75x the rate of 1-month plans** (39.1% vs 14.2%), despite starting with auto-renew on slightly *more* reliably
- The **highest-price tier (€10+) retains far better** than everything else (63.3% stay enabled vs 26-49% elsewhere)
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

**Important structural note:** this table is a *status-change log*, not one row per subscription. A subscription only gets more than one row if the customer toggled auto-renew off and back on more than once during the term (372 of 34,411 subscriptions do this). All analysis below first collapses this into one final outcome per subscription.

## Assumptions and Limitations

**Data-tracking gap, pre-March 2022 — included, not excluded, but flagged.** Subscriptions purchased before March 2022 show a "no record" rate as high as 68% in some months, vs. a stable ~11-16% from March 2022 onward. No behavioral explanation fits a swing that large tied purely to purchase month — this looks like a logging/rollout gap in the `ar_valid_from`/`ar_valid_to` tracking mechanism, not real customer behavior. Rather than dropping these subscriptions, **every figure in this report includes the full dataset (34,411 subscriptions)** — the older cohort is simply more likely to land in the "no record" bucket than it should. Anywhere the "no record" share looks elevated, purchase-date mix is a likely contributor worth checking before concluding it's a behavioral finding.

**"No activation on record" treated as its own category, not merged into "cancelled":** for 26.0% of subscriptions, there is no enable event logged at all (no `ar_valid_from`/`ar_valid_to`). Given the record-keeping is *usually* (not *always*) on-by-default, this could mean the customer opted out essentially instantly, or it could mean this segment genuinely never had auto-renew set — both are consistent with the data. A same-day toggle test confirmed the system *can* log instant on/off pairs (142 real examples), which weakens but doesn't rule out the "too fast to log" theory; an hourly-level toggle can't be tested since dates, not timestamps, are the only granularity available. Kept as a separate, clearly-labeled category rather than assumed either way.

**No customer/account-level ID.** Only `subscription_id` is available — there's no way to link multiple subscriptions to the same customer. All rates in this analysis are subscription-level, not customer-level; a customer with several subscriptions is counted once per subscription, and cross-product customer behavior (e.g. "does this person keep hosting on but cancel their domain?") can't be observed.

**No order-type / checkout-flow field.** Can't distinguish an original purchase from a renewal-generated continuation of the same underlying service, and can't confirm whether a declined-at-checkout auto-renew checkbox exists as a product feature.

**Nationality/gender-style demographic segmentation isn't available in this dataset** — segmentation here is limited to product, plan length, price, and payment gateway.

## Auto-Renew Outcomes by Segment

Every table below groups by `final_status`, which is derived from the raw columns as shown here. This base query is what every "SQL query used" snippet in this section is built on top of:

```sql
CREATE OR REPLACE TABLE sub_status AS
WITH true_rows AS (
    -- one row per enabled window; keep only each subscription's most recent one
    SELECT *,
        row_number() OVER (PARTITION BY subscription_id ORDER BY ar_valid_from DESC) AS rn
    FROM read_csv_auto('file.csv')
    WHERE is_auto_renew = true
),
last_window AS (
    SELECT * FROM true_rows WHERE rn = 1
)
SELECT
    subscription_id, product_group, period_months, payment_gateway,
    billings_eur_excl_vat, started_at, ended_at,
    ar_valid_from, ar_valid_to,
    CASE
        -- no ON event was ever logged for this subscription
        WHEN ar_valid_to IS NULL THEN 'never_enabled'
        -- the ON window's end date reaches (or passes) the subscription's own end date
        -- = auto-renew was still active when the term expired
        WHEN ar_valid_to >= ended_at THEN 'stayed_enabled'
        -- the ON window ended BEFORE the subscription's own end date
        -- = a real, logged cancel event that happened ahead of expiry
        ELSE 'disabled_before_expiry'
    END AS final_status
FROM last_window
UNION ALL
-- subscriptions with no is_auto_renew = true row at all: no ON event, no OFF event, nothing logged
SELECT
    subscription_id, product_group, period_months, payment_gateway,
    billings_eur_excl_vat, started_at, ended_at,
    NULL, NULL, 'never_enabled'
FROM read_csv_auto('file.csv')
WHERE is_auto_renew IS NULL;
```

The three outcome labels used throughout this report map to `final_status` as: **"No activation on record"** = `never_enabled`, **"Actively cancelled before expiry"** = `disabled_before_expiry`, **"Stayed enabled"** = `stayed_enabled`.

### Overall

| Outcome | Subscriptions | % |
|---|---|---|
| Actively cancelled before expiry | 12,879 | 37.4% |
| Stayed enabled (will renew) | 12,587 | 36.6% |
| No activation on record | 8,945 | 26.0% |

<details>
<summary>SQL query used for the overall status split</summary>

```sql
SELECT final_status, count(*) AS n,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
FROM sub_status
GROUP BY 1 ORDER BY n DESC;
```
</details>

**Interpretation:** active cancellation and staying enabled are almost tied as the two largest outcomes, with "no record" a close third. Note the no-record share here (26.0%) is higher than it would be with only reliable-tracking data — see the Assumptions note on the pre-March-2022 gap.

### By Product Group

| Product | Subscriptions | Stayed enabled | Cancelled | No record |
|---|---|---|---|---|
| Domain | 19,001 | 29.1% | 33.4% | 37.5% |
| Hosting | 14,444 | 45.8% | 44.3% | 9.9% |
| Mail | 966 | 45.9% | 13.8% | 40.4% |

<details>
<summary>SQL query used for the product group breakdown</summary>

```sql
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
<summary>SQL query used for the plan length breakdown</summary>

```sql
SELECT period_months, final_status, count(*) AS n,
       round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY period_months), 1) AS pct
FROM sub_status
GROUP BY 1, 2 ORDER BY 1, n DESC;
```
</details>

**Annual plans activate auto-renew about as reliably as monthly plans (25.9% vs 28.1% no-record — actually slightly better) but get cancelled at 2.75x the rate afterward.** Since 93.5% of the full dataset is 12-month plans, this single pattern describes what happens to the overwhelming majority of the customer base. The large upfront lump-sum renewal charge is the most likely trigger — see the Timing section below for how sharply this concentrates near the renewal date.

### By Price Range

| Price | Subscriptions | Stayed enabled | Cancelled | No record |
|---|---|---|---|---|
| Free (€0) | 5,854 | 33.0% | 30.0% | 37.0% |
| €0.01 – 2 | 12,599 | 28.0% | 34.4% | 37.6% |
| €2 – 5 | 4,717 | 48.5% | 28.3% | 23.1% |
| €5 – 10 | 9,675 | 39.7% | 52.1% | 8.2% |
| €10+ | 1,566 | **63.3%** | 26.4% | 10.3% |

<details>
<summary>SQL query used for the price range breakdown</summary>

```sql
SELECT
  CASE
    WHEN billings_eur_excl_vat = 0 THEN '1_free'
    WHEN billings_eur_excl_vat <= 2 THEN '2_0.01-2'
    WHEN billings_eur_excl_vat <= 5 THEN '3_2-5'
    WHEN billings_eur_excl_vat <= 10 THEN '4_5-10'
    ELSE '5_10+'
  END AS price_bucket,
  final_status, count(*) AS n,
  round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY price_bucket), 1) AS pct
FROM sub_status
GROUP BY 1, 2 ORDER BY 1, 2;
```
</details>

**The €10+ tier retains dramatically better than every other bracket.** The cheapest brackets (free and €0.01-2, which together are over half the dataset) show the highest no-record rates too — consistent with these buckets being dominated by cheap domains, which also skew toward the pre-March-2022 cohort. A separate correlation check (price as a continuous value vs. "stayed enabled") found a real but weak relationship (+0.098) — price is a contributing factor, not a primary driver.

### By Payment Gateway Type

| Gateway type | Subscriptions | Stayed enabled | Cancelled | No record |
|---|---|---|---|---|
| Card / bank | 28,207 | 38.8% | 39.9% | 21.3% |
| Crypto | 1,074 | 2.0% | 2.9% | **95.2%** |

<details>
<summary>SQL query used for the payment gateway breakdown</summary>

```sql
SELECT
  CASE WHEN payment_gateway IN ('coingate','coinpayments') THEN 'crypto'
       WHEN payment_gateway IN ('checkout','credorax','paypal') THEN 'card_or_bank'
       ELSE 'other' END AS gateway_type,
  final_status, count(*) AS n,
  round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY
    CASE WHEN payment_gateway IN ('coingate','coinpayments') THEN 'crypto'
         WHEN payment_gateway IN ('checkout','credorax','paypal') THEN 'card_or_bank'
         ELSE 'other' END), 1) AS pct
FROM sub_status
GROUP BY 1, 2 ORDER BY 1, n DESC;
```
</details>

**Crypto is very likely a technical constraint, not a behavioral signal** — crypto payments generally can't be stored for automatic re-billing the way a card can. This pattern is stable regardless of the tracking-gap issue (crypto gateways are a small, distinct population). Recommend excluding crypto from auto-renew health metrics going forward, and reporting it as a separate "renewability by payment method" line instead.

## Timing and Duration of Cancellation

Two related questions, both only about the "actively cancelled" group (12,879 subscriptions) — this group is unaffected by the no-record ambiguity, since every one of these has a directly observed ON event and OFF event. **Both are split by plan length**, since "30 days before renewal" or "days kept on" mean very different things for a 30-day term vs. a 365-day term — a blended figure across both plan lengths would be misleading (a 1-month plan is nearly guaranteed to fall "within 30 days of renewal" simply because the whole term is that short).

### How close to the renewal date did the cancellation happen?

**1-month plans** (n=319)

| Timing | Count | % |
|---|---|---|
| 0-3 days before renewal | 29 | 9.1% |
| 4-7 days before | 15 | 4.7% |
| 8-14 days before | 125 | 39.2% |
| 15-30 days before | 150 | 47.0% |

95.9% fall "within 30 days of renewal" — but since the entire term is only 30 days, this number is close to meaningless as a "last-minute" signal. It just describes when in a short window the cancel happened, not proximity to a looming charge.

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
<summary>SQL query used for the timing and duration analysis</summary>

```sql
-- timing before renewal, split by plan length
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

*(Note: one subscription with an impossible negative duration — its logged auto-renew window predates the subscription's own start date — was excluded from the duration analysis as a data error, consistent with the other isolated data-quality issues below.)*

## Data Quality Findings

Four distinct issues surfaced during analysis, kept separate from the behavioral findings above since none of them changed the core conclusions but all are worth reporting to the data/engineering team.

**Tracking gap, pre-March 2022.** See Assumptions & Limitations above — a likely rollout gap in the `ar_valid_from`/`ar_valid_to` logging mechanism, not a product or customer issue. Included in all figures, not excluded, but inflates "no record" for that period.

**18 broken records, isolated to `.es` domains.** These rows have `ar_valid_from` *after* `ar_valid_to` — a logically impossible order. All 18 are `domain:.es`, 61% are free/promotional domains, and several share identical `ar_valid_from` dates across unrelated subscriptions (e.g. four different subscriptions all show `2023-03-15`). This pattern points to a batch job writing an incorrect run-date into old, already-closed subscription records rather than any real customer action — recommended as a direct bug report.

**~1,900 delayed-activation records.** Auto-renew turns on some time after `started_at` rather than immediately. About 29% of this group is a 0-1 day gap (likely date-rounding noise, not a real delay). The remaining, more meaningful delays (8 days to several months) are concentrated in free/promotional domains with no payment gateway on file — consistent with "auto-renew can't meaningfully activate until a real payment method is attached," which for some customers happens weeks after claiming a free domain.

**5 unexpected free (€0) hosting/mail records.** Hosting and mail are otherwise almost never free (0-0.2% of records). 2 of the 5 were paid via internal account balance (plausible comp/credit). The other 3 were paid via real card gateways, with 2 of the 3 starting on 2022-11-24 — Black Friday — suggesting a promotional campaign, though a pricing bug can't be ruled out from this data alone.

## Conclusions and Recommendations

**Build a save flow for the 15-30 day pre-renewal window, targeted at 12-month plans specifically.** This is the single biggest, most universal lever available: 39.1% of annual subscriptions actively cancel, over half of those cancellations happen in the final 30 days, and the pattern holds consistently across domain and hosting alike. A targeted intervention here — a "keep your price locked in" nudge, a small loyalty discount, or clearer messaging about what happens at expiry — reaches the widest population of any single fix. (Note: don't apply this same "30 days" framing to monthly plans — it doesn't mean the same thing there.)

**Soften the annual renewal "sticker shock."** Annual plans get cancelled at 2.75x the rate of monthly plans despite activating just as reliably at purchase — the large upfront charge is the likely trigger. Consider an early reminder with the exact amount and date, or an installment option for the annual renewal.

**Investigate the domain and mail no-record rates, but confirm the tracking-gap contribution first.** Both products show elevated "no record" shares (37.5% and 40.4%). Before treating this as a product/flow issue, check how much of each is explained by purchase-date mix (domains and mail skew toward the less-reliable pre-March-2022 cohort) — hosting, which skews more recent, has a much lower no-record rate (9.9%) and may simply be a cleaner-tracked product rather than a behaviorally different one.

**Exclude crypto payments from auto-renew health metrics.** Crypto-paid subscriptions are very likely technically incapable of auto-renewing rather than behaviorally opting out — blending them into the main metric understates the real renewability of payment methods that can actually renew.

**Fix the underlying tracking gap and the `.es` domain batch-job bug.** Both are reported above as concrete, isolated engineering issues, separate from the behavioral recommendations — worth fixing before any future auto-renew reporting relies on this pipeline again.

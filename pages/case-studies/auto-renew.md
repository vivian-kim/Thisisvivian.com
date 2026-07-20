---
title: Auto-Renew Dynamics Analysis
---

A subscription-based hosting/domain provider needed to understand **when users tend to enable or disable their auto-renew**. The goal was to understand behavioral patterns and provide actionable insights and suggestions to improve the auto-renew rate, for non-technical stakeholders on the product team.

Key questions included:

- When do customers tend to enable or disable auto-renew?
- Is the bigger problem activation (never turning it on) or retention (turning it off later)?
- Which segments — product, plan length, price, payment method — have the healthiest auto-renew rates?

## Executive Summary

**This is a retention problem, not an activation problem.** Once a data-tracking gap in the early cohort is corrected for, half of all subscriptions actively cancel auto-renew before it would charge them again — most of that cancellation clusters in the final 30 days before renewal.

- Only **37.2%** of subscriptions are on track to actually auto-renew
- **50.1%** actively cancel auto-renew before their term ends
- **53.9%** of those cancellations happen within 30 days of the renewal date
- **12-month plans cancel at 4.4x the rate of 1-month plans** (52.8% vs 12.1%), despite activating auto-renew just as reliably at purchase
- The **highest-price tier (€10+) retains far better** than everything else (73.9% stay enabled vs 19-47% elsewhere)
- **Crypto-paid subscriptions almost never auto-renew (94.9%)** — a technical/platform constraint, not customer behavior
- A **data-tracking gap** for subscriptions purchased before March 2022 was found and excluded from all headline figures (see Assumptions & Limitations)

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

**Tracking-gap cohort excluded from headline figures:** subscriptions purchased before March 2022 show a "never activated" rate as high as 68% in some months, vs. a stable ~13% from March 2022 onward. No behavioral explanation fits a 6x swing tied to purchase month — this is treated as a logging/rollout gap, not real customer behavior. All headline numbers use only the March 2022+ cohort (17,989 subscriptions, still >50% of the dataset). Full-dataset figures are available in the accompanying SQL file for reference.

**"No activation on record" treated as its own category, not merged into "cancelled":** for ~13% of subscriptions, there is no enable event logged at all (no `ar_valid_from`/`ar_valid_to`). Given the record-keeping is *usually* (not *always*) on-by-default, this could mean the customer opted out essentially instantly, or it could mean this segment genuinely never had auto-renew set — both are consistent with the data. A same-day toggle test confirmed the system *can* log instant on/off pairs (142 real examples), which weakens but doesn't rule out the "too fast to log" theory; an hourly-level toggle can't be tested since dates, not timestamps, are the only granularity available. Kept as a separate, clearly-labeled category rather than assumed either way.

**No customer/account-level ID.** Only `subscription_id` is available — there's no way to link multiple subscriptions to the same customer. All rates in this analysis are subscription-level, not customer-level; a customer with several subscriptions is counted once per subscription, and cross-product customer behavior (e.g. "does this person keep hosting on but cancel their domain?") can't be observed.

**No order-type / checkout-flow field.** Can't distinguish an original purchase from a renewal-generated continuation of the same underlying service, and can't confirm whether a declined-at-checkout auto-renew checkbox exists as a product feature.

**Nationality/gender-style demographic segmentation isn't available in this dataset** — segmentation here is limited to product, plan length, price, and payment gateway.

## Auto-Renew Outcomes by Segment

### Overall

| Outcome | Subscriptions | % |
|---|---|---|
| Will auto-renew | 6,683 | 37.2% |
| Actively cancelled before expiry | 9,005 | 50.1% |
| No activation on record | 2,301 | 12.8% |

<details>
<summary>SQL query used for the overall status split</summary>

```sql
SELECT final_status, count(*) AS n,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
FROM sub_status_clean
GROUP BY 1 ORDER BY n DESC;
```
</details>

**Interpretation:** the majority outcome across the whole dataset is active cancellation, not passive non-adoption — 4 out of every 5 "won't renew" subscriptions had auto-renew turned on at some point before the customer chose to disable it.

### By Product Group

| Product | Subscriptions | Will renew | Cancelled | No record |
|---|---|---|---|---|
| Domain | 9,105 | 33.6% | 51.9% | 14.5% |
| Hosting | 8,111 | 39.4% | 51.2% | 9.4% |
| Mail | 773 | 55.6% | 16.8% | 27.6% |

<details>
<summary>SQL query used for the product group breakdown</summary>

```sql
SELECT product_group, final_status, count(*) AS n,
       round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY product_group), 1) AS pct
FROM sub_status_clean
GROUP BY 1, 2 ORDER BY 1, n DESC;
```
</details>

**Domain and hosting cancel at almost identical rates (~51-52%)** — the active-cancellation problem is universal across the two largest product lines, not specific to one. **Mail stands out with the highest "no record" rate (27.6%, ~1 in 4)** — a large enough gap from the ~9-15% baseline elsewhere to be worth checking the mail signup flow specifically, though its smaller sample size (773) means this reads as a lead, not a settled finding.

### By Plan Length

| Plan | Subscriptions | Will renew | Cancelled | No record |
|---|---|---|---|---|
| 1-month | 1,204 | 61.6% | 12.1% | 26.2% |
| 12-month | 16,785 | 35.4% | 52.8% | 11.8% |

<details>
<summary>SQL query used for the plan length breakdown</summary>

```sql
SELECT period_months, final_status, count(*) AS n,
       round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY period_months), 1) AS pct
FROM sub_status_clean
GROUP BY 1, 2 ORDER BY 1, n DESC;
```
</details>

**Annual plans activate auto-renew just as reliably as monthly plans** (11.8% no-record vs 26.2% — actually *better*) **but get cancelled at 4.4x the rate afterward.** Since 93.5% of the full dataset is 12-month plans, this single pattern describes what happens to almost the entire customer base. The large upfront lump-sum renewal charge is the most likely trigger.

### By Price Range

| Price | Subscriptions | Will renew | Cancelled | No record |
|---|---|---|---|---|
| Free (€0) | 3,187 | 42.4% | 46.4% | 11.2% |
| €0.01 – 2 | 5,782 | 31.1% | 52.9% | 16.0% |
| €2 – 5 | 1,593 | 47.3% | 27.1% | 25.6% |
| €5 – 10 | 6,918 | 34.8% | 57.0% | 8.3% |
| €10+ | 509 | **73.9%** | 19.1% | 7.1% |

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
FROM sub_status_clean
GROUP BY 1, 2 ORDER BY 1, 2;
```
</details>

**The €10+ tier retains dramatically better than every other bracket** — nearly double the next-best segment. Cheap, near-free items (€0.01-2, the highest-volume bucket at 5,782 subscriptions) cancel the most. Higher price appears to correlate with a more invested, committed customer.

### By Payment Gateway Type

| Gateway type | Subscriptions | Will renew | Cancelled | No record |
|---|---|---|---|---|
| Card / bank | 14,180 | 37.6% | 53.0% | 9.4% |
| Crypto | 628 | 2.1% | 3.0% | **94.9%** |

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
FROM sub_status_clean
GROUP BY 1, 2 ORDER BY 1, n DESC;
```
</details>

**Crypto is very likely a technical constraint, not a behavioral signal** — crypto payments generally can't be stored for automatic re-billing the way a card can. Recommend excluding crypto from auto-renew health metrics going forward, and reporting it as a separate "renewability by payment method" line instead.

## Timing of Cancellation

Among subscriptions that actively cancelled before their term ended, timing relative to the renewal date:

| Timing | Cancellations | % |
|---|---|---|
| 0-3 days before renewal | 1,426 | 15.8% |
| 4-14 days before | 1,206 | 13.4% |
| 15-30 days before | 2,223 | 24.7% |
| 31-90 days before | 1,607 | 17.8% |
| 90+ days before | 2,543 | 28.2% |
| **≤30 days combined** | **4,855** | **53.9%** |

<details>
<summary>SQL query used for the cancellation timing analysis</summary>

```sql
SELECT
  CASE
    WHEN days_before_expiry_disabled <= 3  THEN '1_0-3'
    WHEN days_before_expiry_disabled <= 14 THEN '2_4-14'
    WHEN days_before_expiry_disabled <= 30 THEN '3_15-30'
    WHEN days_before_expiry_disabled <= 90 THEN '4_31-90'
    ELSE '5_90+'
  END AS bucket, count(*) AS n,
  round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
FROM sub_status_clean
WHERE final_status = 'disabled_before_expiry'
GROUP BY 1 ORDER BY 1;
```
</details>

**Over half of all cancellations happen in the final 30 days before renewal** — almost certainly a reaction to renewal-reminder emails or notifications, not a random-time decision. This is the single most concentrated, addressable moment in the entire customer journey.

### Cancellation Duration, by Plan Length

A related but distinct question: not "how close to renewal" but "how long did the customer keep auto-renew on before switching it off," measured from the start of the subscription. Split by plan length, since a 1-month plan and a 12-month plan have very different possible durations.

**1-month plans** (max possible: 30 days, n=145)

| Duration kept on | Count | % |
|---|---|---|
| 0-3 days | 17 | 11.7% |
| 4-7 days | 10 | 6.9% |
| 8-14 days | 32 | 22.1% |
| 15-21 days | 54 | 37.2% |
| 22-30 days | 32 | 22.1% |

Mean: 15.5 days · Median: 17 days — roughly the halfway point of the term, fairly spread out.

**12-month plans** (max possible: 364 days, n=8,859)

| Duration kept on | Count | % |
|---|---|---|
| 0-7 days | 339 | 3.8% |
| 8-30 days | 363 | 4.1% |
| 31-90 days | 453 | 5.1% |
| 91-180 days | 592 | 6.7% |
| 181-270 days | 740 | 8.4% |
| **271-365 days** | **6,372** | **71.9%** |

Mean: 278 days · Median: 337 days — heavily back-loaded to the final quarter of the year.

<details>
<summary>SQL query used for the cancellation duration analysis</summary>

```sql
SELECT
  period_months,
  CASE
    WHEN days_to_disable <= 7 THEN '0-7 days'
    WHEN days_to_disable <= 30 THEN '8-30 days'
    WHEN days_to_disable <= 90 THEN '31-90 days'
    WHEN days_to_disable <= 180 THEN '91-180 days'
    WHEN days_to_disable <= 270 THEN '181-270 days'
    ELSE '271-365 days'
  END AS cancellation_duration,
  count(*) AS n,
  round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY period_months), 1) AS pct
FROM sub_status_clean
WHERE final_status = 'disabled_before_expiry' AND days_to_disable >= 0
GROUP BY 1, 2 ORDER BY 1, 2;
```
</details>

**The two plan types tell genuinely different stories once separated.** Monthly cancellations are fairly spread out across the term — no sharp late spike. Annual cancellations are massively concentrated in the final 3 months (71.9% of them), right before the renewal charge. This strengthens the "annual sticker shock" theory: it isn't a general late-term pattern, it's specific to the size of the annual charge — the monthly plan, with its own much smaller renewal amount, doesn't show the same last-minute concentration.

*(Note: one subscription with an impossible negative duration — its logged auto-renew window predates the subscription's own start date — was excluded from this analysis as a data error, consistent with the other isolated data-quality issues below.)*

## Data Quality Findings

Three distinct issues surfaced during analysis, kept separate from the behavioral findings above since none of them changed the core conclusions but all are worth reporting to the data/engineering team.

**Tracking gap, pre-March 2022.** See Assumptions & Limitations above — a likely rollout gap in the `ar_valid_from`/`ar_valid_to` logging mechanism, not a product or customer issue.

**18 broken records, isolated to `.es` domains.** These rows have `ar_valid_from` *after* `ar_valid_to` — a logically impossible order. All 18 are `domain:.es`, 61% are free/promotional domains, and several share identical `ar_valid_from` dates across unrelated subscriptions (e.g. four different subscriptions all show `2023-03-15`). This pattern points to a batch job writing an incorrect run-date into old, already-closed subscription records rather than any real customer action — recommended as a direct bug report.

**~1,900 delayed-activation records.** Auto-renew turns on some time after `started_at` rather than immediately. About 29% of this group is a 0-1 day gap (likely date-rounding noise, not a real delay). The remaining, more meaningful delays (8 days to several months) are concentrated in free/promotional domains with no payment gateway on file — consistent with "auto-renew can't meaningfully activate until a real payment method is attached," which for some customers happens weeks after claiming a free domain.

**5 unexpected free (€0) hosting/mail records.** Hosting and mail are otherwise almost never free (0-0.2% of records). 2 of the 5 were paid via internal account balance (plausible comp/credit). The other 3 were paid via real card gateways, with 2 of the 3 starting on 2022-11-24 — Black Friday — suggesting a promotional campaign, though a pricing bug can't be ruled out from this data alone.

## Conclusions and Recommendations

**Build a save flow for the 15-30 day pre-renewal window.** This is the single biggest, most universal lever available: half of all subscriptions actively cancel, over half of those cancellations happen in the final 30 days, and the pattern holds consistently across domain and hosting alike. A targeted intervention here — a "keep your price locked in" nudge, a small loyalty discount, or clearer messaging about what happens at expiry — reaches the widest population of any single fix.

**Soften the annual renewal "sticker shock."** Annual plans get cancelled at 4.4x the rate of monthly plans despite activating just as reliably at purchase — the large upfront charge is the likely trigger. Consider an early reminder with the exact amount and date, or an installment option for the annual renewal.

**Investigate mail's low activation rate with more data.** Mail has the highest "no activation on record" rate (27.6%) of the three products — worth a direct check of the mail signup flow's auto-renew default, though the smaller sample size means this should be verified before acting on it.

**Exclude crypto payments from auto-renew health metrics.** Crypto-paid subscriptions are very likely technically incapable of auto-renewing rather than behaviorally opting out — blending them into the main metric understates the real renewability of payment methods that can actually renew.

**Fix the underlying tracking gap and the `.es` domain batch-job bug.** Both are reported above as concrete, isolated engineering issues, separate from the behavioral recommendations — worth fixing before any future auto-renew reporting relies on this pipeline again.

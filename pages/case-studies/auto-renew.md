---
title: Auto-Renew Dynamics Analysis
<<<<<<< HEAD
=======
queries:
  - subscriptions.sql
  - subscription_status.sql
  - auto_renew/outcome_overall.sql
  - auto_renew/revenue_by_outcome.sql
  - auto_renew/outcome_by_product.sql
  - auto_renew/outcome_by_hosting_subgroup.sql
  - auto_renew/outcome_by_domain_tld.sql
  - auto_renew/outcome_by_plan_length.sql
  - auto_renew/outcome_by_price.sql
  - auto_renew/outcome_by_payment_gateway.sql
  - auto_renew/cancellation_timing_1mo_plans.sql
  - auto_renew/cancellation_timing_12mo_plans.sql
  - auto_renew/cancellation_duration_1mo_plans.sql
  - auto_renew/cancellation_duration_12mo_plans.sql
  - auto_renew/returning_customers_outcome.sql
  - auto_renew/seasonality_by_renewal_month.sql
  - auto_renew/distinct_product_groups.sql
  - auto_renew/distinct_product_slugs.sql
  - auto_renew/outcome_timeseries.sql
>>>>>>> update-auto-renew-case-study
---

A subscription-based hosting/domain provider needed to understand **when users tend to enable or disable their auto-renew**. The goal was to understand behavioral patterns and provide actionable insights and suggestions to improve the auto-renew rate, for non-technical stakeholders on the product team.

Key questions included:
<<<<<<< HEAD

=======
>>>>>>> update-auto-renew-case-study
- When do customers tend to enable or disable auto-renew?
- Is the bigger problem activation (never turning it on) or retention (turning it off later)?
- Which segments — product, plan length, price, payment method — have the healthiest auto-renew rates?

<<<<<<< HEAD
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
=======
---

# Executive Summary

## Headline
- Only **37.4%** of subscriptions are actively cancelled, **36.6%** stay enabled, **26.0%** have no activation on record
- **€45,786 (40.6% of all revenue tracked)** is tied to subscriptions that actively cancelled auto-renew
- **53.3%** of 12-month cancellations happen within 30 days of the renewal date

## Plan Length & Price
- 12-month plans cancel at **2.75x** the rate of 1-month plans, despite activating just as reliably at purchase
- Retention rises steadily with price — no reversals, from 33.0% (free) to 73.4% (€20+)

## Payment & Timing
- Crypto-paid subscriptions almost never auto-renew (95.2% no record) — a technical constraint, not a behavioral one
- November (Black Friday) is both the highest-volume signup month and one of the worst-retaining

---

# Data Schema

## Subscriptions table
<table class="markdown text-left"><thead class="markdown"><tr class="markdown"><th class="markdown"><strong class="markdown">Column</strong></th> <th class="markdown"><strong class="markdown">Data Type</strong></th> <th class="markdown"><strong class="markdown">Description</strong></th></tr></thead> <tbody class="markdown"><tr class="markdown"><td class="markdown">subscription_id</td> <td class="markdown">INTEGER</td> <td class="markdown">ID of the subscription</td></tr> <tr class="markdown"><td class="markdown">payment_gateway</td> <td class="markdown">STRING</td> <td class="markdown">Payment gateway used (Checkout / Credorax / PayPal / crypto / etc.)</td></tr> <tr class="markdown"><td class="markdown">product_group</td> <td class="markdown">STRING</td> <td class="markdown">Broadest product category (domain / hosting / mail)</td></tr> <tr class="markdown"><td class="markdown">product_sub_group</td> <td class="markdown">STRING</td> <td class="markdown">Subset of product group</td></tr> <tr class="markdown"><td class="markdown">product_slug</td> <td class="markdown">STRING</td> <td class="markdown">Detailed product name</td></tr> <tr class="markdown"><td class="markdown">period_months</td> <td class="markdown">INTEGER</td> <td class="markdown">Plan duration in months</td></tr> <tr class="markdown"><td class="markdown">started_at</td> <td class="markdown">DATE</td> <td class="markdown">Subscription start date</td></tr> <tr class="markdown"><td class="markdown">ended_at</td> <td class="markdown">DATE</td> <td class="markdown">Subscription end date</td></tr> <tr class="markdown"><td class="markdown">is_auto_renew</td> <td class="markdown">BOOLEAN</td> <td class="markdown">TRUE if auto-renew is on</td></tr> <tr class="markdown"><td class="markdown">ar_valid_from</td> <td class="markdown">DATE</td> <td class="markdown">Date auto-renew was enabled</td></tr> <tr class="markdown"><td class="markdown">ar_valid_to</td> <td class="markdown">DATE</td> <td class="markdown">Date auto-renew was disabled</td></tr> <tr class="markdown"><td class="markdown">billings_eur_excl_vat</td> <td class="markdown">DECIMAL</td> <td class="markdown">Billed amount in EUR, excl. VAT</td></tr></tbody></table>

**Important structural note:** this table is a *status-change log*, not one row per subscription. A subscription only gets more than one row if the customer toggled auto-renew off and back on more than once during the term (365 of 34,411 subscriptions do this — see Returning Customers below).

---

# Assumptions and Limitations

- **Data-tracking gap, pre-March 2022 — included, not excluded, but flagged.** Subscriptions purchased before March 2022 show a "no record" rate as high as 68% in some months, vs. a stable ~11-16% from March 2022 onward. Treated as a logging/rollout gap, not real customer behavior. Every figure in this report includes the full dataset (34,411 subscriptions) — the older cohort is simply more likely to land in the "no record" bucket than it should.
- **"No activation on record" treated as its own category, not merged into "cancelled."** For 26.0% of subscriptions, there is no enable event logged at all. Given the record-keeping is *usually* — not *always* — on-by-default, this could mean the customer opted out essentially instantly, or that this segment genuinely never had auto-renew set. The "never disabled without user action" policy only resolves this *if* the subscription started on in the first place — and "usually" is exactly the word that leaves room for exceptions to that default. Two direct tests were run against the "instant cancel" reading: same-day toggles are proven to log correctly (142 real examples, ruling out "too fast to log" as a blanket explanation), and the group isn't disproportionately free/no-payment (ruling out a simple product-exemption story). Both came back "not disproven, but not confirmed either" — kept as a separate, neutral category rather than assumed either way.
- **No customer/account-level ID.** Only `subscription_id` is available — a customer with several subscriptions is counted once per subscription; cross-product customer behavior can't be observed.
- **No order-type / checkout-flow field.** Can't distinguish an original purchase from a renewal-generated continuation, and can't confirm whether a declined-at-checkout auto-renew checkbox exists as a product feature.

---

# Auto-Renew Outcomes by Segment

Every chart below is built on one classification query (`subscription_status.sql`) that collapses the raw status-change log into one final outcome per subscription:

<Details title="Base classification query (subscription_status.sql) — every chart in this report is grouped off of this">

```sql
WITH true_rows AS (
    SELECT *, count(*) OVER (PARTITION BY subscription_id) AS n_windows
    FROM ${subscriptions}
    WHERE is_auto_renew = true
),
last_window AS (
    SELECT *,
        row_number() OVER (PARTITION BY subscription_id ORDER BY ar_valid_from DESC) AS rn
    FROM true_rows
    QUALIFY rn = 1
),
no_record_rows AS (
    SELECT *, 1 AS n_windows FROM ${subscriptions} WHERE is_auto_renew IS NULL
),
final_group AS (
    SELECT
        subscription_id, payment_gateway, product_group, product_sub_group,
        product_slug, period_months, started_at, ended_at, billings_eur_excl_vat,
        n_windows, ar_valid_from AS last_enabled_from, ar_valid_to AS last_enabled_to,
        CASE
            WHEN ar_valid_to IS NULL THEN 'never_enabled'
            WHEN ar_valid_to >= ended_at THEN 'stayed_enabled'
            ELSE 'disabled_before_expiry'
        END AS final_status,
        CASE WHEN ar_valid_to IS NOT NULL AND ar_valid_to < ended_at
             THEN date_diff('day', started_at, ar_valid_to) END AS days_to_disable,
        CASE WHEN ar_valid_to IS NOT NULL AND ar_valid_to < ended_at
             THEN date_diff('day', ar_valid_to, ended_at) END AS days_before_expiry_disabled,
        (ar_valid_to IS NOT NULL AND ar_valid_to >= started_at) OR ar_valid_to IS NULL AS is_clean_window
    FROM last_window
)
SELECT * FROM final_group
UNION ALL
SELECT subscription_id, payment_gateway, product_group, product_sub_group,
    product_slug, period_months, started_at, ended_at, billings_eur_excl_vat,
    n_windows, NULL, NULL, 'never_enabled', NULL, NULL, true
FROM no_record_rows
```

</Details>

**Validated before use:** every subscription lands in exactly one of the three segments, with no gaps or duplicates (34,411 = 34,411, checked against the raw file's unique subscription count).

**Filter the Overall, Product, Price, and Gateway charts below by plan length** — this is the single factor that changes almost every finding in this report, so it's worth exploring interactively rather than only as static tables:

<Dropdown name=plan_filter>
    <DropdownOption value=% valueLabel="All plans"/>
    <DropdownOption value=1 valueLabel="1-month only"/>
    <DropdownOption value=12 valueLabel="12-month only"/>
</Dropdown>

## Overall

<BarChart
    data={auto_renew_outcome_overall}
    x=outcome
    y=subscriptions
    y2SeriesType=line
    y2=pct
    y2Fmt=pct1
    chartAreaHeight=300
/>

<DataTable data={auto_renew_outcome_overall}>
  <Column id=outcome />
  <Column id=subscriptions />
  <Column id=pct fmt=pct1 title="% of total" />
</DataTable>

Active cancellation and staying enabled are almost tied as the two largest outcomes, with "no record" a close third.

## Revenue at Risk

<BarChart
    data={auto_renew_revenue_by_outcome}
    x=outcome
    y=revenue_eur
    yFmt='€#,##0'
    chartAreaHeight=300
/>

<DataTable data={auto_renew_revenue_by_outcome}>
  <Column id=outcome />
  <Column id=subscriptions />
  <Column id=revenue_eur fmt='€#,##0' title="Revenue" />
</DataTable>

**€45,786 — 40.6% of all revenue tracked — is tied to subscriptions that actively cancelled auto-renew.** Of that, €28,054 (6,689 subscriptions) sits in the highest-leverage window: 12-month plans cancelled within 30 days of renewal. A rough illustrative scenario: recovering 10% of those is ~€2,805/year in retained revenue, recurring for every customer kept — a sizing exercise, not a forecast.

## By Product Group

<Heatmap
    data={auto_renew_outcome_by_product}
    x=product_group
    y=outcome
    value=pct
    valueFmt=pct1
/>

<DataTable data={auto_renew_outcome_by_product}>
  <Column id=product_group />
  <Column id=outcome />
  <Column id=subscriptions />
  <Column id=pct fmt=pct1 />
</DataTable>

**Hosting has both the best retention and the lowest no-record rate of any product.** Domain and mail both show high no-record shares. Verified the tracking-gap claim directly rather than leaving it as a hand-wave: for `domain:.es` specifically, no-record sits at **50.6%** for subscriptions purchased before March 2022, vs. **9.2%** after — an 82% relative drop, confirming the gap is real and large, not a rounding artifact. Mail's smaller sample still makes it a lead rather than a settled finding.

### Hosting Isn't One Product: Shared vs. Cloud

`product_group` treats all of hosting as one bucket. It isn't — shared and cloud hosting are different products with very different retention:

<Heatmap
    data={auto_renew_outcome_by_hosting_subgroup}
    x=product_sub_group
    y=outcome
    value=pct
    valueFmt=pct1
/>

<DataTable data={auto_renew_outcome_by_hosting_subgroup}>
  <Column id=product_sub_group title="Sub-group" />
  <Column id=outcome />
  <Column id=subscriptions />
  <Column id=pct fmt=pct1 />
</DataTable>

**Cloud hosting retains nearly 19 points better than shared (64.2% vs. 45.4%)**, with 282 subscriptions vs. shared's 14,162. Honest caveat: this substantially overlaps with the price→retention relationship already covered — cloud averages €18.30 vs. shared's €6.35. Still worth naming directly, though: "push more customers toward cloud hosting" is a concrete, actionable lever in a way "higher price bracket" alone isn't.

**Plausible reasons beyond price, though none of these can be fully verified from this data:**
- **Customer type likely differs.** Cloud hosting is typically bought by developers, agencies, or businesses running something with an actual operational dependency — not someone testing a hobby project. That's a stickier customer by nature, independent of price.
- **Switching costs are probably higher.** Migrating a cloud setup (DNS, deployments, configs) takes more effort than abandoning shared hosting, so even a dissatisfied customer has more friction to actually leave.
- **The price confound can't be cleanly separated from these** with the columns available here — there's no field indicating business vs. personal use, which would be the real test of "cloud loyalty" vs. "price loyalty."

### Domain TLDs Vary Enormously Too

Same issue, one level down — "Domain" (29.1% stayed) hides a wide range across TLDs:

<DataTable data={auto_renew_outcome_by_domain_tld}>
  <Column id=product_slug title="TLD" />
  <Column id=subscriptions />
  <Column id=stayed_pct fmt=pct1 title="Stayed" />
  <Column id=cancelled_pct fmt=pct1 title="Cancelled" />
  <Column id=no_record_pct fmt=pct1 title="No record" />
  <Column id=avg_price fmt='€#,##0.00' title="Avg. price" />
</DataTable>

**`.shop` actively cancels at 55.9%** — worse than any other segment in this entire report, including the 12-month/annual-plan headline finding. Largely tracks price again (`.xyz` is free, `.online`/`.store`/`.tech` sit near €0.27-0.30, `.es`/`.org` are priced higher and retain better) — mostly the price story wearing a TLD costume. Still worth surfacing by name: TLD is something a pricing or promo team can act on directly. (`domain:.be` at 66.7% stayed is directional only — n=24, too small to trust on its own.)

**Dug deeper into `.shop` specifically, since it's the single worst-performing segment in the report.** Two things line up:
- **Seasonal concentration:** 218 of 410 `.shop` signups (53.2%) landed in Aug-Nov 2022, peaking in November at 67 — the same Black Friday window already flagged as a weak cohort elsewhere in this report. `.shop` being an e-commerce-branded TLD makes it a natural fit for holiday promotional campaigns.
- **A real promo-to-full-price cliff:** 395 of 410 `.shop` subscriptions (96.3%) cluster at €0-0.76, with a small separate group of 15 (3.7%) jumping to €5.55-7.99 — roughly a 10-20x price increase at renewal. Compare `.es` (a better-retaining TLD), whose pricing sits in a tight, modest €1.68-1.92 band with no such cliff.

**The likely mechanism: `.shop` domains were disproportionately sold as steep first-year promotional deals, probably timed to Black Friday, and the auto-renew charge represents a dramatically larger jump than other TLDs see** — a sharper, TLD-specific version of the "sticker shock" pattern this report already documents for annual plans generally. The `.shop` pattern is consistent with promotional first-year pricing followed by a steep renewal jump, based on price distribution and signup timing — but the dataset has no explicit promo flag to confirm this directly; it's an inference from price and timing, not a directly labeled variable.

## By Plan Length

<Heatmap
    data={auto_renew_outcome_by_plan_length}
    x=plan
    y=outcome
    value=pct
    valueFmt=pct1
/>

<DataTable data={auto_renew_outcome_by_plan_length}>
  <Column id=plan />
  <Column id=outcome />
  <Column id=subscriptions />
  <Column id=pct fmt=pct1 />
</DataTable>

**Annual plans activate auto-renew about as reliably as monthly plans but get cancelled at 2.75x the rate afterward.** Since 93.5% of the full dataset is 12-month plans, this single pattern describes what happens to the overwhelming majority of the customer base. The large upfront lump-sum renewal charge is the most likely trigger.

## By Price Range

Boundaries were checked against the real data before picking them: 95.4% of subscriptions are under €10 (prices cluster hard at specific SKU points), and the tail thins fast past €20 (only 504 subscriptions above that). An earlier €0.01-2/€2-5 split was tested and rejected — it produced a non-monotonic result that didn't make sense.

<Heatmap
    data={auto_renew_outcome_by_price}
    x=price_bucket
    y=outcome
    value=pct
    valueFmt=pct1
/>

<DataTable data={auto_renew_outcome_by_price}>
  <Column id=price_bucket title="Price" />
  <Column id=outcome />
  <Column id=subscriptions />
  <Column id=pct fmt=pct1 />
</DataTable>

**Retention rises steadily and cleanly with price — no reversals.** Stayed-enabled climbs from 33.0% (free) to 73.4% (€20+), more than doubling. Checked the €20+ bucket for outliers (max price €109.41): 494 of 504 sit in a tight €20-40 range at 74.0% retention, only 16 sit above €40 at 53.3% (too small to trust alone) — the outliers don't inflate the headline figure, if anything they pull it down slightly.

## By Payment Gateway Type

Card/bank and crypto alone don't cover 100% of subscriptions — they're 85.1% of the 34,411 total. The remaining ~15% splits into two distinct groups, shown below rather than left out.

<Heatmap
    data={auto_renew_outcome_by_payment_gateway}
    x=gateway_type
    y=outcome
    value=pct
    valueFmt=pct1
/>

<DataTable data={auto_renew_outcome_by_payment_gateway}>
  <Column id=gateway_type title="Gateway type" />
  <Column id=outcome />
  <Column id=subscriptions />
  <Column id=pct fmt=pct1 />
</DataTable>

**Crypto is very likely a technical constraint, not a behavioral signal** — crypto payments generally can't be stored for automatic re-billing the way a card can. "No gateway on file" (14.6% of subscriptions) has a meaningfully elevated no-record rate too, plausibly for a similar reason.

---

# Timing and Duration of Cancellation

Two related questions, both split by plan length since "30 days before renewal" or "days kept on" mean very different things for a 30-day term vs. a 365-day term.

## How close to the renewal date did the cancellation happen?

**1-month plans** (n=316; excludes 3 subscriptions with a data error — see Data Quality Findings)

<BarChart data={auto_renew_cancellation_timing_1mo_plans} x=bucket y=n sort=false chartAreaHeight=250 />

These 4 buckets cover the entire possible range (0-30 days) and sum to 100% — every 1-month cancellation is trivially "within 30 days," since the whole term only lasts 30 days. That's exactly why this framing is meaningless here.

**12-month plans** (n=12,560)

<BarChart data={auto_renew_cancellation_timing_12mo_plans} x=bucket y=n sort=false chartAreaHeight=250 />

**53.3% of annual-plan cancellations happen within 30 days of renewal** — a plausible reaction to renewal-reminder emails or notifications. This is the real signal.

## How long did the customer keep auto-renew on before cancelling?

**1-month plans** (max possible: 30 days, n=316)

<BarChart data={auto_renew_cancellation_duration_1mo_plans} x=bucket y=n sort=false chartAreaHeight=250 />

Mean: 14.3 days · Median: 16.0 days — roughly the halfway point of the term, fairly spread out.

**12-month plans** (max possible: 364 days, n=12,560)

<BarChart data={auto_renew_cancellation_duration_12mo_plans} x=bucket y=n sort=false chartAreaHeight=250 />

Mean: 270.5 days · Median: 336.0 days — heavily back-loaded to the final quarter of the year. **69.8% of annual cancellations happen in the final 3 months of the term.** Both views agree: the trigger is specifically the size and timing of the annual renewal charge, not a general late-term pattern.

---

# Returning Customers: Toggled Auto-Renew More Than Once

365 of 34,411 subscriptions (1.1%) toggled auto-renew off and back on at least once during their term — everything above uses only their *most recent* window, discarding this history. Looked at on its own:

<Heatmap
    data={auto_renew_returning_customers_outcome}
    x=grp
    y=outcome
    value=pct
    valueFmt=pct1
/>

<DataTable data={auto_renew_returning_customers_outcome}>
  <Column id=grp title="Group" />
  <Column id=outcome />
  <Column id=n title="Subscriptions" />
  <Column id=pct fmt=pct1 />
</DataTable>

**Returners end up far more likely to stay enabled (68.5%) than everyone else (49.1%).** 12-month plans toggle back at over 4x the rate of monthly plans, even after adjusting for volume — domain leads among products. These customers already showed intent to cancel once, then changed their mind; whatever prompted the re-enable is worth understanding, since it may be a cheap, repeatable save tactic.

---

# Seasonality

For 12-month plans, the renewal date falls in the same calendar month as the original purchase, a year later — so this answers both "does signup month matter" and "does renewal month matter" in one pass. Full dataset, all months, all three outcomes — no date filter applied here.

<BarChart
    data={auto_renew_seasonality_by_renewal_month}
    x=renewal_month
    y=total
    y2SeriesType=line
    y2=stayed_pct
    y2Fmt=pct1
    sort=false
    chartAreaHeight=350
/>

<DataTable data={auto_renew_seasonality_by_renewal_month}>
  <Column id=renewal_month title="Month" />
  <Column id=total />
  <Column id=stayed_pct fmt=pct1 title="Stayed enabled" />
  <Column id=cancelled_pct fmt=pct1 title="Cancelled" />
  <Column id=no_record_pct fmt=pct1 title="No record" />
</DataTable>

**November is both the highest-volume renewal month (4,159) and one of the worst-retaining (30.6% stayed, 46.0% cancelled)** — plausibly tied to Black Friday driving price-sensitive signups. **January and February stand out for a different reason: no-record sits at 38.1% and 34.7%**, well above every other month (15-29% elsewhere) — worth checking against the tracking-gap timing before reading this as a real January/February effect, since these two months draw more heavily from the earlier, less-reliable cohort.

---

# Explore: Outcome Over Time

An open-ended view for digging into any product or TLD directly — pick a product group, then optionally narrow to a specific slug (e.g. a single domain TLD), and watch how the three outcomes trend by signup month.

<Dropdown data={auto_renew_distinct_product_groups} name=group_filter value=product_group>
    <DropdownOption value="%" valueLabel="All product groups"/>
</Dropdown>

<Dropdown data={auto_renew_distinct_product_slugs} name=slug_filter value=product_slug>
    <DropdownOption value="%" valueLabel="All slugs in this group"/>
</Dropdown>

<LineChart
    data={auto_renew_outcome_timeseries}
    x=month
    y=subscriptions
    series=outcome
    chartAreaHeight=350
/>

<DataTable data={auto_renew_outcome_timeseries}>
  <Column id=month />
  <Column id=outcome />
  <Column id=subscriptions />
</DataTable>

The slug dropdown updates to only show slugs belonging to the currently selected product group — switch to "domain" and it narrows to TLDs; switch to "hosting" and it narrows to shared/cloud slugs.

---

# Data Quality Findings

Five distinct issues surfaced during analysis, kept separate from the behavioral findings above since none of them changed the core conclusions but all are worth reporting to the data/engineering team.

- **Tracking gap, pre-March 2022.** A likely rollout gap in the `ar_valid_from`/`ar_valid_to` logging mechanism, not a product or customer issue. Included in all figures, not excluded, but inflates "no record" for that period.
- **18 broken records, isolated to `.es` domains.** `ar_valid_from` after `ar_valid_to` — a logically impossible order. All 18 are `domain:.es`, 61% free/promotional, several sharing identical dates across unrelated subscriptions — points to a batch job writing bad dates into old, closed records.
- **3 broken records, a separate bug, isolated to monthly `hosting:hostinger_premium`.** The logged auto-renew window predates the subscription's own start date entirely. All 3 are 1-month plans priced at exactly the same €2.4456 across 3 different gateways — the identical price suggests a shared root cause, not 3 independent customer actions. Excluded from the timing/duration analysis above.
- **~1,900 delayed-activation records.** Auto-renew turns on some time after `started_at`. ~29% is a 0-1 day gap (rounding noise); the rest concentrates in free domains with no payment gateway on file, consistent with "can't activate until a real payment method is attached."
- **5 unexpected free (€0) hosting/mail records.** 2 via internal balance (plausible comp), 3 via real card gateways, 2 of those starting on Black Friday 2022 — plausibly a promo, though a pricing bug can't be ruled out.

**Additional checks that came back clean:** `period_months` has only 2 values (1 and 12), confirmed exhaustive. Term length matches `period_months` in every row (1-month: 28-31 actual days; 12-month: exactly 365, always). `product_group`, `product_sub_group`, `product_slug`, `billings_eur_excl_vat` have zero nulls; `payment_gateway`'s 5,079 nulls are already accounted for in the gateway breakdown above.

---

# Conclusions and Recommendations

1. **Build a save flow for the 15-30 day pre-renewal window, targeted at 12-month plans.** The single biggest lever: 39.1% of annual subscriptions actively cancel, over half within the final 30 days. €28,054 in current-term revenue sits in this exact window — recovering even 10% is a rough ~€2,805/year, recurring.
2. **Soften the annual renewal "sticker shock."** Annual plans cancel at 2.75x the rate of monthly despite activating just as reliably — the large upfront charge is the likely trigger. Consider an early reminder with the exact amount, or an installment option.
3. **Investigate domain and mail no-record rates, but confirm the tracking-gap contribution first.** Both skew toward the less-reliable pre-March-2022 cohort — hosting, which skews more recent, has a much lower no-record rate and may just be more cleanly tracked.
4. **Exclude crypto from auto-renew health metrics.** Very likely a technical constraint, not behavior — blending it in understates the real renewability of payment methods that can actually renew.
5. **Give the November (Black Friday) cohort a dedicated retention plan.** Largest signup month and one of the worst-retaining — €6,076 tied to its cancelled subscriptions. Worth confirming this repeats in future years before treating it as permanent.
6. **Fix the underlying tracking gap and the two isolated data-quality bugs** (`.es` domain batch job, `hosting_premium` window-predates-start) before any future auto-renew reporting relies on this pipeline again.
>>>>>>> update-auto-renew-case-study

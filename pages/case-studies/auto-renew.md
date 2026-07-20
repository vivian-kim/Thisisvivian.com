---
title: Auto-Renew Dynamics Analysis
queries:
  - subscriptions.sql
  - subscription_status.sql
  - auto_renew/outcome_overall.sql
  - auto_renew/revenue_by_outcome.sql
  - auto_renew/outcome_by_product.sql
  - auto_renew/outcome_by_hosting_subgroup.sql
  - auto_renew/outcome_by_domain_tld.sql
  - auto_renew/excluded_unreliable_records.sql
  - auto_renew/cancelled_revenue_by_product.sql
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
---

A subscription-based hosting/domain provider needed to understand **when users tend to enable or disable their auto-renew**. The goal was to understand behavioral patterns and provide actionable insights and suggestions to improve the auto-renew rate, for non-technical stakeholders on the product team.

**The story in one line:** most subscriptions aren't failing to activate auto-renew — they're activating it, then actively cancelling later, usually right before the big annual charge would hit.

Key questions included:
- When do customers tend to enable or disable auto-renew?
- Is the bigger problem activation (never turning it on) or retention (turning it off later)?
- Which segments — product, plan length, price, payment method — have the healthiest auto-renew rates?

---

## Jump to
- [Executive Summary](#executive-summary)
- [Conclusions and Recommendations](#conclusions-and-recommendations)
- [Data Schema](#data-schema)
- [Assumptions and Limitations](#assumptions-and-limitations)
- [Auto-Renew Outcomes by Segment](#auto-renew-outcomes-by-segment)
- [Timing and Duration of Cancellation](#timing-and-duration-of-cancellation)
- [Returning Customers](#returning-customers-toggled-auto-renew-more-than-once)
- [Seasonality](#seasonality)
- [Explore: Outcome Over Time](#explore-outcome-over-time)
- [Appendix: Data Quality Findings](#appendix-data-quality-findings)

---

# Executive Summary

## Headline
- Only **37.4%** of subscriptions are actively cancelled, **36.6%** stay enabled, **26.0%** have no activation on record
- **€45,779 (40.6% of all revenue tracked)** is tied to subscriptions that actively cancelled auto-renew
- **53.3%** of 12-month cancellations happen within 30 days of the renewal date

## Plan Length & Price
- 12-month plans cancel at **2.79x** the rate of 1-month plans, despite activating just as reliably at purchase
- Retention rises steadily with price — no reversals, from 33.0% (free) to 73.4% (€20+)

## Payment & Timing
- Crypto-paid subscriptions almost never auto-renew (95.2% no record) — we don't know why; a plausible assumption is a technical/platform constraint, but the data can't confirm that
- November is both the highest-volume signup month and one of the worst-retaining — the Black Friday link is a plausible, timing-based inference, not confirmed by any promotional data

## Product & Domain Detail
- **Cloud hosting retains 19 points better than shared hosting** (64.2% vs. 45.4%) — a concrete lever (push customers toward cloud), though it overlaps with the price story
- **`.shop` is the single worst-performing segment in the entire report** (55.9% cancel) — a steep first-year price followed by a 10-20x renewal jump, with signups concentrated near Black Friday; no promo data exists to confirm the cause
- Domain, hosting, and mail all show meaningfully different "no record" rates (37.5% / 9.9% / 40.4%) — worth checking against the tracking gap before treating as a behavioral finding

## Returning Customers
- The 1.1% of subscriptions that toggled auto-renew off and back on **retain far better than everyone else** (68.5% vs. 49.1%) — a small population, but a strong signal that re-engagement works

---

# Conclusions and Recommendations

1. **Build a save flow for the 15-30 day pre-renewal window, targeted at 12-month `hosting:hostinger_premium` customers specifically.** This is the single biggest lever by both count and revenue: 39.1% of annual subscriptions actively cancel, over half within the final 30 days, and `hosting:hostinger_premium` alone accounts for 85.2% of all cancelled revenue (€38,998) — far more than its cancel rate alone would suggest. €28,054 in current-term revenue sits in the 30-day window across all products — recovering even 10% is a rough ~€2,805/year, recurring.
2. **Soften the annual renewal "sticker shock."** Annual plans cancel at 2.79x the rate of monthly despite activating just as reliably — the large upfront charge is the likely trigger. Consider an early reminder with the exact amount, or an installment option.
3. **Investigate domain and mail no-record rates, but confirm the tracking-gap contribution first.** Both skew toward the less-reliable pre-March-2022 cohort — hosting, which skews more recent, has a much lower no-record rate and may just be more cleanly tracked.
4. **Get confirmation on whether crypto's near-100% no-record rate is a technical limitation or something else.** We don't know the cause — no field in this data explains it. One assumption worth testing is a platform constraint (crypto generally can't be stored for automatic re-billing), but that's a guess, not a finding. Worth a direct question to whoever owns the payment integration before treating it as settled and excluding crypto from auto-renew health metrics on that basis.
5. **Give the November cohort a dedicated retention plan, but confirm the Black Friday explanation first.** November is the largest signup month and one of the worst-retaining — €6,076 tied to its cancelled subscriptions. This report has no actual promotional/campaign data — the Black Friday link is an assumption based on timing alone (November volume spike + calendar proximity), not a confirmed cause. Worth confirming with whoever ran marketing that year, and confirming the pattern repeats in future years, before treating it as permanent.
6. **Resolve the "no record" ambiguity with the data owner.** The single biggest open question in this whole analysis: does a blank `is_auto_renew` mean the customer declined instantly, or that auto-renew was never applicable to that record? Two specific, answerable questions would settle it — see Assumptions & Limitations. Until answered, the 26.0% "no record" segment should stay reported separately, not folded into "cancelled" or "will renew."
7. **Fix the underlying tracking gap and the two isolated data-quality bugs** (`.es` domain batch job, `hosting_premium` window-predates-start) before any future auto-renew reporting relies on this pipeline again.

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
    -- rn = 1 keeps only each subscription's MOST RECENT enabled window -
    -- see the comment in subscription_status.sql for why
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
            -- 2 known-broken groups (20 subscriptions total), pulled into
            -- their own category rather than silently misclassified -
            -- see Data Quality Findings for the full reasoning
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
SELECT subscription_id, payment_gateway, product_group, product_sub_group,
    product_slug, period_months, started_at, ended_at, billings_eur_excl_vat,
    n_windows, NULL, NULL, 'no_record', NULL, NULL, NULL, true
FROM no_record_rows
```

</Details>

**Validated before use:** every subscription lands in exactly one of the three main segments, plus a 4th, tiny "excluded — unreliable record" bucket held out of every chart in this report — no gaps, no double-counting (34,411 = 12,876 + 12,570 + 8,945 + 20, checked against the raw file's unique subscription count). See Data Quality Findings for what the 20 excluded records are and why.

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
    labels=true
    labelPosition=center
    chartAreaHeight=300
/>

<DataTable data={auto_renew_outcome_overall}>
  <Column id=outcome />
  <Column id=subscriptions />
  <Column id=pct fmt=pct1 title="% of total" />
</DataTable>

<Details title="SQL query used for Overall">

```sql
SELECT
  CASE final_status
    WHEN 'stayed_enabled' THEN 'Stayed enabled'
    WHEN 'disabled_before_expiry' THEN 'Actively cancelled'
    WHEN 'no_record' THEN 'No record'
  END AS outcome,
  final_status,
  count(*) AS subscriptions,
  round(100.0 * count(*) / sum(count(*)) OVER (), 1) / 100.0 AS pct
FROM ${subscription_status}
WHERE period_months::varchar LIKE '${inputs.plan_filter.value}'
GROUP BY 1, 2
ORDER BY subscriptions DESC
```

</Details>

Active cancellation and staying enabled are almost tied as the two largest outcomes, with "no record" a close third.

## Revenue at Risk

<BarChart
    data={auto_renew_revenue_by_outcome}
    x=outcome
    y=revenue_eur
    yFmt='€#,##0'
    labels=true
    labelPosition=center
    labelFmt='€#,##0'
    chartAreaHeight=300
/>

<DataTable data={auto_renew_revenue_by_outcome}>
  <Column id=outcome />
  <Column id=subscriptions />
  <Column id=revenue_eur fmt='€#,##0' title="Revenue" />
</DataTable>

<Details title="SQL query used for Revenue at Risk">

```sql
SELECT
  CASE final_status
    WHEN 'stayed_enabled' THEN 'Stayed enabled'
    WHEN 'disabled_before_expiry' THEN 'Actively cancelled'
    WHEN 'no_record' THEN 'No record'
  END AS outcome,
  final_status,
  count(*) AS subscriptions,
  round(sum(billings_eur_excl_vat), 2) AS revenue_eur
FROM ${subscription_status}
GROUP BY 1, 2
ORDER BY revenue_eur DESC
```

</Details>

**€45,779 — 40.6% of all revenue tracked — is tied to subscriptions that actively cancelled auto-renew.** Of that, €28,054 (6,689 subscriptions) sits in the highest-leverage window: 12-month plans cancelled within 30 days of renewal. A rough illustrative scenario: recovering 10% of those is ~€2,805/year in retained revenue, recurring for every customer kept — a sizing exercise, not a forecast.

### Which Product Actually Loses the Most Money — Rate vs. Revenue

Every breakdown above shows cancel *rates*. Rate alone can mislead prioritization: a scary-looking percentage on a tiny product matters less than a modest one on a huge product. Ranked by actual euros lost instead:

<BarChart
    data={auto_renew_cancelled_revenue_by_product}
    x=product_slug
    y=cancelled_revenue
    yFmt='€#,##0'
    labels=true
    labelPosition=center
    labelFmt='€#,##0'
    chartAreaHeight=350
/>

<DataTable data={auto_renew_cancelled_revenue_by_product}>
  <Column id=product_slug title="Product" />
  <Column id=subscriptions />
  <Column id=cancelled_revenue fmt='€#,##0.00' title="Cancelled revenue" />
  <Column id=cancelled_pct fmt=pct1 title="Cancel rate" />
</DataTable>

<Details title="SQL query used for Rate vs. Revenue">

```sql
SELECT
  product_slug,
  count(*) AS subscriptions,
  round(sum(CASE WHEN final_status = 'disabled_before_expiry' THEN billings_eur_excl_vat ELSE 0 END), 2) AS cancelled_revenue,
  round(100.0 * sum(CASE WHEN final_status = 'disabled_before_expiry' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS cancelled_pct
FROM ${subscription_status}
WHERE final_status != 'excluded_unreliable'
GROUP BY 1
ORDER BY cancelled_revenue DESC
```

</Details>

**`hosting:hostinger_premium` alone accounts for €38,998 — 85.2% of all cancelled revenue in this entire report**, despite a cancel rate (44.6%) that's unremarkable next to `.shop`'s 55.9%. And that's exactly the point: **`.shop`, the segment with the single scariest cancel rate anywhere in this report, contributes only €94 — 0.2% of cancelled revenue.** By rate, `.shop` looks like the fire to put out; by revenue, it's a rounding error next to hosting. `domain:.es` is a distant second at €2,818 (6.2%). **If prioritizing by actual dollars recovered, the save-flow effort (recommendation #1) should be built for `hosting:hostinger_premium` customers first — everything else is secondary.**

<Details title="Segment Deep-Dive: Product, Plan, Price, Payment">

Cancel *rate* by product, plan length, price, and payment method — supporting detail behind the Overall and Revenue at Risk charts above. Worth reading if you want to know *where* the cancellations concentrate, not just how many there are.

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

<Details title="SQL query used for By Product Group">

```sql
SELECT
  product_group,
  CASE final_status
    WHEN 'stayed_enabled' THEN 'Stayed enabled'
    WHEN 'disabled_before_expiry' THEN 'Actively cancelled'
    WHEN 'no_record' THEN 'No record'
  END AS outcome,
  final_status,
  count(*) AS subscriptions,
  round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY product_group), 1) / 100.0 AS pct
FROM ${subscription_status}
WHERE period_months::varchar LIKE '${inputs.plan_filter.value}'
GROUP BY 1, 2, 3
ORDER BY product_group, subscriptions DESC
```

</Details>

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

<Details title="SQL query used for Hosting: Shared vs. Cloud">

```sql
SELECT
  product_sub_group,
  CASE final_status
    WHEN 'stayed_enabled' THEN 'Stayed enabled'
    WHEN 'disabled_before_expiry' THEN 'Actively cancelled'
    WHEN 'no_record' THEN 'No record'
  END AS outcome,
  final_status,
  count(*) AS subscriptions,
  round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY product_sub_group), 1) / 100.0 AS pct
FROM ${subscription_status}
WHERE product_group = 'hosting'
GROUP BY 1, 2, 3
ORDER BY product_sub_group, subscriptions DESC
```

</Details>

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

<Details title="SQL query used for Domain TLD Variance">

```sql
SELECT
  product_slug,
  count(*) AS subscriptions,
  round(100.0 * sum(CASE WHEN final_status = 'stayed_enabled' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS stayed_pct,
  round(100.0 * sum(CASE WHEN final_status = 'disabled_before_expiry' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS cancelled_pct,
  round(100.0 * sum(CASE WHEN final_status = 'no_record' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS no_record_pct,
  round(avg(billings_eur_excl_vat), 2) AS avg_price
FROM ${subscription_status}
WHERE product_group = 'domain'
GROUP BY 1
ORDER BY subscriptions DESC
```

</Details>

**`.shop` actively cancels at 55.9%** — worse than any other segment in this entire report, including the 12-month/annual-plan headline finding. Largely tracks price again (`.xyz` is free, `.online`/`.store`/`.tech` sit near €0.27-0.30, `.es`/`.org` are priced higher and retain better) — mostly the price story wearing a TLD costume. Still worth surfacing by name: TLD is something a pricing or promo team can act on directly. (`domain:.be` at 66.7% stayed is directional only — n=24, too small to trust on its own.)

**Dug deeper into `.shop` specifically, since it's the single worst-performing segment in the report.** Two things line up:
- **Seasonal concentration:** 218 of 410 `.shop` signups (53.2%) landed in Aug-Nov 2022, peaking in November at 67 — the same Black Friday window already flagged as a weak cohort elsewhere in this report. No campaign or promo data exists in this dataset to confirm why, but the timing overlap is real and worth noting.
- **A real first-year-to-renewal price cliff:** 395 of 410 `.shop` subscriptions (96.3%) cluster at €0-0.76, with a small separate group of 15 (3.7%) jumping to €5.55-7.99 — roughly a 10-20x price increase at renewal. Compare `.es` (a better-retaining TLD), whose pricing sits in a tight, modest €1.68-1.92 band with no such cliff.

**What this is consistent with, stated carefully: `.shop` domains were sold at a steep first-year price relative to their renewal price, with signups concentrated near Black Friday, and the auto-renew charge represents a dramatically larger jump than other TLDs see** — a sharper, TLD-specific version of the "sticker shock" pattern this report already documents for annual plans generally. This is an inference from price distribution and signup timing alone — the dataset has no promo flag, campaign field, or list-price field to confirm whether this was an actual promotion, a standard low first-year rate, or something else entirely.

**Checked whether mail has sub-segments too, for consistency — it doesn't.** Unlike hosting (shared/cloud) and domain (10 TLDs), mail has exactly one `product_sub_group` and exactly one `product_slug` (`hostinger_mail:pro`). Nothing further to break down; the gap is closed by there being nothing there.

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

<Details title="SQL query used for By Plan Length">

```sql
SELECT
  period_months || '-month' AS plan,
  period_months,
  CASE final_status
    WHEN 'stayed_enabled' THEN 'Stayed enabled'
    WHEN 'disabled_before_expiry' THEN 'Actively cancelled'
    WHEN 'no_record' THEN 'No record'
  END AS outcome,
  final_status,
  count(*) AS subscriptions,
  round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY period_months), 1) / 100.0 AS pct
FROM ${subscription_status}
GROUP BY 1, 2, 3, 4
ORDER BY period_months, subscriptions DESC
```

</Details>

**Annual plans activate auto-renew about as reliably as monthly plans but get cancelled at 2.79x the rate afterward.** Since 93.5% of the full dataset is 12-month plans, this single pattern describes what happens to the overwhelming majority of the customer base. The large upfront lump-sum renewal charge is the most likely trigger.

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

<Details title="SQL query used for By Price Range">

```sql
SELECT
  CASE
    WHEN billings_eur_excl_vat = 0  THEN '1. Free (€0)'
    WHEN billings_eur_excl_vat < 5  THEN '2. €0.01-5'
    WHEN billings_eur_excl_vat < 10 THEN '3. €5-10'
    WHEN billings_eur_excl_vat < 20 THEN '4. €10-20'
    ELSE '5. €20+'
  END AS price_bucket,
  CASE final_status
    WHEN 'stayed_enabled' THEN 'Stayed enabled'
    WHEN 'disabled_before_expiry' THEN 'Actively cancelled'
    WHEN 'no_record' THEN 'No record'
  END AS outcome,
  final_status,
  count(*) AS subscriptions,
  round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY
    CASE
      WHEN billings_eur_excl_vat = 0  THEN '1. Free (€0)'
      WHEN billings_eur_excl_vat < 5  THEN '2. €0.01-5'
      WHEN billings_eur_excl_vat < 10 THEN '3. €5-10'
      WHEN billings_eur_excl_vat < 20 THEN '4. €10-20'
      ELSE '5. €20+'
    END), 1) / 100.0 AS pct
FROM ${subscription_status}
WHERE period_months::varchar LIKE '${inputs.plan_filter.value}'
GROUP BY 1, 2, 3
ORDER BY price_bucket, subscriptions DESC
```

</Details>

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

<Details title="SQL query used for By Payment Gateway Type">

```sql
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
WHERE period_months::varchar LIKE '${inputs.plan_filter.value}'
GROUP BY 1, 2, 3
ORDER BY gateway_type, subscriptions DESC
```

</Details>

**We don't know why crypto's no-record rate is so high — this data has no field that explains it.** One assumption worth testing: crypto payments generally can't be stored for automatic re-billing the way a card can, which would make this a platform constraint rather than a behavioral signal. "No gateway on file" (14.6% of subscriptions) has a meaningfully elevated no-record rate too, and the same caveat applies — it's an assumption, not a confirmed cause.

</Details>

---

# Timing and Duration of Cancellation

Two related questions, both split by plan length since "30 days before renewal" or "days kept on" mean very different things for a 30-day term vs. a 365-day term.

## How close to the renewal date did the cancellation happen?

**1-month plans** (n=316; excludes 3 subscriptions with a data error — see Data Quality Findings)

<BarChart data={auto_renew_cancellation_timing_1mo_plans} x=bucket y=n sort=false labels=true labelPosition=center chartAreaHeight=250 />

<Details title="SQL query used for 1-month timing">

```sql
SELECT
  CASE
    WHEN days_before_expiry_disabled <= 3  THEN '0-3 days before'
    WHEN days_before_expiry_disabled <= 7  THEN '4-7 days before'
    WHEN days_before_expiry_disabled <= 14 THEN '8-14 days before'
    ELSE '15-30 days before'
  END AS bucket,
  min(days_before_expiry_disabled) AS sort_key,
  count(*) AS n,
  round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
FROM ${subscription_status}
WHERE final_status = 'disabled_before_expiry' AND is_clean_window AND period_months = 1
GROUP BY 1
ORDER BY sort_key
```

</Details>

These 4 buckets cover the entire possible range (0-30 days) and sum to 100% — every 1-month cancellation is trivially "within 30 days," since the whole term only lasts 30 days. That's exactly why this framing is meaningless here.

**12-month plans** (n=12,560)

<BarChart data={auto_renew_cancellation_timing_12mo_plans} x=bucket y=n sort=false labels=true labelPosition=center chartAreaHeight=250 />

<Details title="SQL query used for 12-month timing">

```sql
SELECT
  CASE
    WHEN days_before_expiry_disabled <= 3  THEN '0-3 days before'
    WHEN days_before_expiry_disabled <= 14 THEN '4-14 days before'
    WHEN days_before_expiry_disabled <= 30 THEN '15-30 days before'
    WHEN days_before_expiry_disabled <= 90 THEN '31-90 days before'
    ELSE '90+ days before'
  END AS bucket,
  min(days_before_expiry_disabled) AS sort_key,
  count(*) AS n,
  round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
FROM ${subscription_status}
WHERE final_status = 'disabled_before_expiry' AND is_clean_window AND period_months = 12
GROUP BY 1
ORDER BY sort_key
```

</Details>

**53.3% of annual-plan cancellations happen within 30 days of renewal** — a plausible reaction to renewal-reminder emails or notifications. This is the real signal.

## How long did the customer keep auto-renew on before cancelling?

**1-month plans** (max possible: 30 days, n=316)

<BarChart data={auto_renew_cancellation_duration_1mo_plans} x=bucket y=n sort=false labels=true labelPosition=center chartAreaHeight=250 />

<Details title="SQL query used for 1-month duration">

```sql
SELECT
  CASE
    WHEN days_to_disable <= 3  THEN '0-3 days'
    WHEN days_to_disable <= 7  THEN '4-7 days'
    WHEN days_to_disable <= 14 THEN '8-14 days'
    WHEN days_to_disable <= 21 THEN '15-21 days'
    ELSE '22-30 days'
  END AS bucket,
  min(days_to_disable) AS sort_key,
  count(*) AS n,
  round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
FROM ${subscription_status}
WHERE final_status = 'disabled_before_expiry' AND is_clean_window AND period_months = 1
GROUP BY 1
ORDER BY sort_key
```

</Details>

Mean: 14.3 days · Median: 16.0 days — roughly the halfway point of the term, fairly spread out.

**12-month plans** (max possible: 364 days, n=12,560)

<BarChart data={auto_renew_cancellation_duration_12mo_plans} x=bucket y=n sort=false labels=true labelPosition=center chartAreaHeight=250 />

<Details title="SQL query used for 12-month duration">

```sql
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
```

</Details>

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

<Details title="SQL query used for Returning Customers">

```sql
SELECT
  CASE WHEN n_windows > 1 THEN 'Toggled more than once' ELSE 'Never toggled back' END AS grp,
  CASE final_status
    WHEN 'stayed_enabled' THEN 'Stayed enabled'
    WHEN 'disabled_before_expiry' THEN 'Actively cancelled'
  END AS outcome,
  final_status,
  count(*) AS n,
  round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY
    CASE WHEN n_windows > 1 THEN 'Toggled more than once' ELSE 'Never toggled back' END), 1) / 100.0 AS pct
FROM ${subscription_status}
WHERE final_status != 'no_record'
GROUP BY 1, 2, 3
ORDER BY grp, n DESC
```

</Details>

**Returners end up far more likely to stay enabled (68.5%) than everyone else (49.1%).** 12-month plans toggle back at over 4x the rate of monthly plans, even after adjusting for volume — domain leads among products. These customers already showed intent to cancel once, then changed their mind; whatever prompted the re-enable is worth understanding, since it may be a cheap, repeatable save tactic.

---

# Seasonality

For 12-month plans, the renewal date falls in the same calendar month as the original purchase, a year later; for 1-month plans it's simply the following month. Toggle between them below — the two plan lengths have different volumes and different patterns, so they're shown one at a time rather than blended. Full dataset, all three outcomes, no date filter applied.

<Dropdown name=seasonality_plan>
    <DropdownOption value=12 valueLabel="12-month plans"/>
    <DropdownOption value=1 valueLabel="1-month plans"/>
</Dropdown>

<BarChart
    data={auto_renew_seasonality_by_renewal_month}
    x=renewal_month
    y=total
    y2SeriesType=line
    y2=stayed_pct
    y2Fmt=pct1
    sort=false
    labels=true
    labelPosition=center
    chartAreaHeight=350
/>

<DataTable data={auto_renew_seasonality_by_renewal_month}>
  <Column id=renewal_month title="Month" />
  <Column id=total />
  <Column id=stayed_pct fmt=pct1 title="Stayed enabled" />
  <Column id=cancelled_pct fmt=pct1 title="Cancelled" />
  <Column id=no_record_pct fmt=pct1 title="No record" />
</DataTable>

<Details title="SQL query used for Seasonality">

```sql
SELECT
  strftime(ended_at, '%m-%b') AS renewal_month,
  count(*) AS total,
  round(100.0 * sum(CASE WHEN final_status = 'stayed_enabled' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS stayed_pct,
  round(100.0 * sum(CASE WHEN final_status = 'disabled_before_expiry' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS cancelled_pct,
  round(100.0 * sum(CASE WHEN final_status = 'no_record' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS no_record_pct
FROM ${subscription_status}
WHERE period_months = ${inputs.seasonality_plan.value} AND final_status != 'excluded_unreliable'
GROUP BY 1
ORDER BY 1
```

</Details>

**On the 12-month view (the default above):** November is both the highest-volume renewal month (4,159) and one of the worst-retaining (30.6% stayed, 46.0% cancelled) — plausibly tied to Black Friday driving price-sensitive signups. January and February stand out for a different reason: no-record sits at 38.1% and 34.7%, well above every other month (15-29% elsewhere) — worth checking against the tracking-gap timing before reading this as a real January/February effect, since these two months draw more heavily from the earlier, less-reliable cohort.

**Switch to the 1-month view and the November dip disappears.** November sits at 58.7% stayed — unremarkable, near the middle of the range (42.5-65.3% across all 12 months). That's a real difference, not just smaller numbers: it suggests the Black Friday effect is specific to annual-plan buyers (bigger purchase, more promo-sensitive), not a general seasonal pattern across every product. December is the standout month for 1-month plans instead — highest volume (267) and, alongside January and February, one of three months with elevated no-record (34.8% / 33.6% / 41.1%), consistent with the same tracking-gap pattern seen in the 12-month view.

---


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
    labels=true
    labelPosition=top
    chartAreaHeight=350
/>

<DataTable data={auto_renew_outcome_timeseries}>
  <Column id=month />
  <Column id=outcome />
  <Column id=subscriptions />
</DataTable>

<Details title="SQL query used for Outcome Over Time">

```sql
SELECT
  date_trunc('month', started_at) AS month,
  CASE final_status
    WHEN 'stayed_enabled' THEN 'Stayed enabled'
    WHEN 'disabled_before_expiry' THEN 'Actively cancelled'
    WHEN 'no_record' THEN 'No record'
  END AS outcome,
  final_status,
  count(*) AS subscriptions
FROM ${subscription_status}
WHERE product_group LIKE '${inputs.group_filter.value}'
  AND product_slug LIKE '${inputs.slug_filter.value}'
GROUP BY 1, 2, 3
ORDER BY 1
```

</Details>

The slug dropdown updates to only show slugs belonging to the currently selected product group — switch to "domain" and it narrows to TLDs; switch to "hosting" and it narrows to shared/cloud slugs.

---

# Appendix: Data Quality Findings

Three distinct issues surfaced during analysis. One (below, "20 Records Excluded") was corrected directly in the classification logic, not just noted — the other two are flagged for the data/engineering team but don't change any number in this report.

- **Tracking gap, pre-March 2022.** A likely rollout gap in the `ar_valid_from`/`ar_valid_to` logging mechanism, not a product or customer issue. Included in all figures, not excluded, but inflates "no record" for that period.
- **2,239 delayed-activation records.** Auto-renew turns on some time after `started_at` rather than immediately (651 free, 1,588 paid). Checked directly rather than assumed: this group has a zero-billing rate of 29.1% vs. 13.1% for normally-timed activations (2.2x higher), and no payment gateway on file 21.4% of the time vs. 11.6% (1.8x higher) — a real, verified correlation with free/no-payment-method signups, though a partial explanation, not a full one (70.9% still has real billing). **Kept in every chart, not excluded:** classification depends on `ar_valid_to`, not `ar_valid_from` — and `ar_valid_to` is a normal, trustworthy date for all 2,239 (63.3% match `ended_at` exactly, i.e. stayed enabled after the late start; the rest cancelled again before term end, both coherent outcomes). Once `ar_valid_to` is known, whether they stayed enabled or cancelled is answered correctly regardless of when activation happened — a late start doesn't make the outcome less trustworthy, unlike the 20 records below where the corrupted field is the one classification actually depends on.
- **5 unexpected free (€0) hosting/mail records.** Hosting and mail are otherwise almost never free (0-0.2% of records), so these 5 stand out numerically. No promo flag or comp-reason field exists in this data to confirm *why* — stated here as an observed anomaly, not a guessed cause.

**Additional checks that came back clean:** `period_months` has only 2 values (1 and 12), confirmed exhaustive. Term length matches `period_months` in every row (1-month: 28-31 actual days; 12-month: exactly 365, always). `product_group`, `product_sub_group`, `product_slug`, `billings_eur_excl_vat` have zero nulls; `payment_gateway`'s 5,079 nulls are already accounted for in the gateway breakdown above.

## 20 Records Excluded From Every Chart Above

Two distinct bugs, both resulting in a subscription's classification being untrustworthy — removed from every outcome chart, table, and percentage in this report rather than silently counted, and shown here explicitly instead of just noted.

**Group 1 — 17 subscriptions (18 raw log rows), all `domain:.es`.** `ar_valid_from` is dated *after* `ar_valid_to` — a logically impossible order. Several share identical dates across unrelated subscriptions (e.g. four different subscriptions all show `2023-03-15`), pointing to a batch job writing a bad run-date into old, already-closed records. (18 raw rows collapse to 17 unique subscriptions because one subscription had 2 broken rows; only its most recent survives the "one row per subscription" step used throughout this analysis.) `ar_valid_to` itself still equals `ended_at` for all of them, so the "stayed enabled" verdict would have been directionally correct — but a row containing a provably impossible date order isn't trusted here, regardless of which specific field the classification technically depends on.

**Group 2 — 3 subscriptions, all monthly `hosting:hostinger_premium`.** The entire logged auto-renew window predates the subscription's own `started_at`. Unlike Group 1, here the corrupted field (`ar_valid_to`) is exactly the one that decides `final_status`, so the classification itself can't be trusted for a more direct reason. All 3 are priced at exactly the same €2.4456 across 3 different payment gateways — the identical price suggests a shared root cause, not 3 independent customer actions.

<DataTable data={auto_renew_excluded_unreliable_records}>
  <Column id=subscription_id />
  <Column id=product_slug title="Product" />
  <Column id=exclusion_reason title="Bug group" />
  <Column id=started_at title="Started" />
  <Column id=ended_at title="Ends" />
  <Column id=last_enabled_from title="Logged ON from" />
  <Column id=last_enabled_to title="Logged ON to" />
  <Column id=billings_eur_excl_vat fmt='€#,##0.0000' title="Price" />
</DataTable>

<Details title="SQL query used for the excluded records">

```sql
SELECT
  subscription_id,
  product_slug,
  exclusion_reason,
  started_at,
  ended_at,
  last_enabled_from,
  last_enabled_to,
  billings_eur_excl_vat
FROM ${subscription_status}
WHERE final_status = 'excluded_unreliable'
ORDER BY exclusion_reason, subscription_id
```

</Details>

**Impact on the rest of this report: negligible** — every headline percentage is unchanged at 1 decimal place (37.4% / 36.6% / 26.0%), since this is 20 out of 34,411 subscriptions (0.058%). This is a correctness fix, not a story change: both bugs are recommended as direct bug reports, and these 20 should be re-classified once the data team confirms what actually happened to them.

---

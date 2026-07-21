---
title: Auto-Renew Dynamics Analysis
queries:
  - subscriptions.sql
  - subscription_status.sql
  - auto_renew/outcome_overall.sql
  - auto_renew/revenue_by_outcome.sql
  - auto_renew/revenue_cancelled_vs_rest.sql
  - auto_renew/outcome_by_product.sql
  - auto_renew/outcome_by_product_wide.sql
  - auto_renew/outcome_by_hosting_subgroup.sql
  - auto_renew/outcome_by_hosting_subgroup_wide.sql
  - auto_renew/outcome_by_domain_tld.sql
  - auto_renew/excluded_unreliable_records.sql
  - auto_renew/cancelled_revenue_by_product.sql
  - auto_renew/outcome_by_plan_length.sql
  - auto_renew/outcome_by_plan_length_wide.sql
  - auto_renew/outcome_by_price.sql
  - auto_renew/outcome_by_price_wide.sql
  - auto_renew/outcome_by_payment_gateway.sql
  - auto_renew/outcome_by_payment_gateway_wide.sql
  - auto_renew/cancellation_timing_1mo_plans.sql
  - auto_renew/cancellation_timing_12mo_plans.sql
  - auto_renew/returning_customers_outcome.sql
  - auto_renew/returning_customers_outcome_wide.sql
  - auto_renew/seasonality_by_renewal_month.sql
  - auto_renew/distinct_product_groups.sql
  - auto_renew/distinct_product_slugs.sql
  - auto_renew/outcome_timeseries.sql
  - auto_renew/outcome_timeseries_wide.sql
---

A subscription-based hosting/domain provider needed to understand **when users tend to enable or disable their auto-renew**. The goal was to understand behavioural patterns and provide actionable insights and suggestions to improve the auto-renew rate, for non-technical stakeholders on the product team.

**In short:** most subscriptions aren't failing to activate auto-renew. They're usually default-activated, then actively cancelled later, usually right before the big annual charge would hit.

Key questions included:
- When do customers tend to enable or disable auto-renew?
- Is the bigger problem activation (never turning it on) or retention (turning it off later)?
- Which segments (product, plan length, price, payment method) have the healthiest auto-renew rates?

---

## Jump to
- [Executive Summary](#executive-summary)
- [Data Schema](#data-schema)
- [Auto-Renew Outcomes by Segment](#auto-renew-outcomes-by-segment)
- [When Do Cancellations Happen?](#when-do-cancellations-happen)
- [Returning Customers](#returning-customers-turned-auto-renew-off-then-back-on)
- [Seasonality](#seasonality)
- [Signup Cohorts: Outcome Over Time](#signup-cohorts-outcome-over-time)
- [Appendix: Assumptions, Limitations & Data Quality Findings](#appendix-assumptions-limitations--data-quality-findings)
- [Conclusions](#conclusions)
- [Recommendations](#recommendations)

---

# Executive Summary

## Headline
- Only **37.4%** of subscriptions are actively cancelled, **36.6%** stay enabled, **26.0%** have no activation on record
- **€45,779 (40.6% of all revenue tracked)** is tied to subscriptions that actively cancelled auto-renew
- **53.3%** of 12-month cancellations happen within 30 days of the renewal date

## Plan Length & Price
- 12-month plans cancel at **2.79x** the rate of 1-month plans, despite activating just as reliably at purchase
- Retention rises steadily with price, no reversals, from 33.0% (free) to 73.4% (€20+)

## Payment & Timing
- Crypto-paid subscriptions almost never auto-renew (95.2% no record). We don't know why; a plausible assumption is a technical/platform constraint, but the data can't confirm that
- November is both the highest-volume signup month and one of the worst-retaining. The Black Friday link is a plausible, timing-based inference, not confirmed by any promotional data

## Product & Domain Detail
- **Cloud hosting retains 19 points better than shared hosting** (64.2% vs. 45.4%), a concrete lever: push customers towards cloud. By median price (average is skewed by a few expensive outliers), cloud isn't actually pricier than shared, so price alone doesn't explain the gap
- **`.shop` is the single worst-performing segment in the entire report** (55.9% cancel): a steep first-year price followed by a 10-20x renewal jump, with signups concentrated near Black Friday. No promo data exists to confirm the cause
- Domain, hosting, and mail all show meaningfully different "no record" rates (37.5% / 9.9% / 40.4%), worth checking against the tracking gap before treating as a behavioural finding

## Returning Customers
- The 1.1% of subscriptions that turned auto-renew off, then back on again, **retain far better than everyone else** (68.1% vs. 49.1%): a small population, but a strong signal that re-engagement works

---

# Data Schema

<Details title="Subscriptions table: column reference (click to expand)">

## Subscriptions table
<table class="markdown text-left"><thead class="markdown"><tr class="markdown"><th class="markdown"><strong class="markdown">Column</strong></th> <th class="markdown"><strong class="markdown">Data Type</strong></th> <th class="markdown"><strong class="markdown">Description</strong></th></tr></thead> <tbody class="markdown"><tr class="markdown"><td class="markdown">subscription_id</td> <td class="markdown">INTEGER</td> <td class="markdown">ID of the subscription</td></tr> <tr class="markdown"><td class="markdown">payment_gateway</td> <td class="markdown">STRING</td> <td class="markdown">Payment gateway used (Checkout / Credorax / PayPal / crypto / etc.)</td></tr> <tr class="markdown"><td class="markdown">product_group</td> <td class="markdown">STRING</td> <td class="markdown">Broadest product category (domain / hosting / mail)</td></tr> <tr class="markdown"><td class="markdown">product_sub_group</td> <td class="markdown">STRING</td> <td class="markdown">Subset of product group</td></tr> <tr class="markdown"><td class="markdown">product_slug</td> <td class="markdown">STRING</td> <td class="markdown">Detailed product name</td></tr> <tr class="markdown"><td class="markdown">period_months</td> <td class="markdown">INTEGER</td> <td class="markdown">Plan duration in months</td></tr> <tr class="markdown"><td class="markdown">started_at</td> <td class="markdown">DATE</td> <td class="markdown">Subscription start date</td></tr> <tr class="markdown"><td class="markdown">ended_at</td> <td class="markdown">DATE</td> <td class="markdown">Subscription end date</td></tr> <tr class="markdown"><td class="markdown">is_auto_renew</td> <td class="markdown">BOOLEAN</td> <td class="markdown">TRUE if auto-renew is on</td></tr> <tr class="markdown"><td class="markdown">ar_valid_from</td> <td class="markdown">DATE</td> <td class="markdown">Date auto-renew was enabled</td></tr> <tr class="markdown"><td class="markdown">ar_valid_to</td> <td class="markdown">DATE</td> <td class="markdown">Date auto-renew was disabled</td></tr> <tr class="markdown"><td class="markdown">billings_eur_excl_vat</td> <td class="markdown">DECIMAL</td> <td class="markdown">Billed amount in EUR, excl. VAT</td></tr></tbody></table>

**Important structural note:** this table is a *status-change log*, not one row per subscription. A subscription only gets more than one row if the customer turned auto-renew off and back on more than once during the term (365 of 34,411 subscriptions do this; see Returning Customers below).

</Details>

<Details title="Glossary: what the terms in this report mean (click to expand)">

- **Stayed enabled:** auto-renew was on and still on when the term ended; the customer was set to renew.
- **Actively cancelled:** auto-renew was turned on at some point, then turned off again before the term ended.
- **No record:** we cannot say whether this subscription was ever auto-renewed or cancelled: `is_auto_renew` is blank, so no enable *or* disable event was ever logged. This is **not** a missing subscription: `started_at`/`ended_at` (the term itself) are always present, with zero nulls across the entire dataset. It's specifically `ar_valid_from`/`ar_valid_to` (the auto-renew on/off dates) that are missing. The auto-renew status is simply unobserved, not "cancelled," not "confirmed enabled." See Assumptions and Limitations in the Appendix for the two live theories on why.
- **Excluded (unreliable record):** a small group of 20 subscriptions with corrupted `ar_valid_from`/`ar_valid_to` dates (a logically impossible order, or a window that predates the subscription itself). Held out of every chart, table, and percentage in this report; see the Appendix for the full breakdown.
- **`ar_valid_from` / `ar_valid_to`:** the raw column names for the date auto-renew was turned on / turned off, respectively. Dates only, no timestamps: anything that happens and reverses within the same day is invisible to this data.
- **Renewal date:** the date a subscription's current term ends (`ended_at`): the point at which auto-renew would trigger the next charge, if it's on.
- **Term / plan length:** the subscription's billing cycle length: either 1 month or 12 months (`period_months`), never anything else in this dataset.
- **Status-change log:** the raw file isn't one row per subscription; see the structural note above.

</Details>

---

# Auto-Renew Outcomes by Segment

Every chart below is built on one classification query (`subscription_status.sql`) that collapses the raw status-change log into one final outcome per subscription:

<Details title="Base classification query (subscription_status.sql): every chart in this report is grouped off of this">

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

**Every subscription is accounted for exactly once: no gaps, no double-counting.**

<Details title="How this was checked">

Every subscription lands in exactly one of the three main outcome segments, plus a 4th, tiny "excluded (unreliable record)" bucket held out of every chart in this report (34,411 = 12,876 + 12,570 + 8,945 + 20, checked against the raw file's unique subscription count). See the Appendix for what the 20 excluded records are and why.

</Details>

**Filter the Overall, Product, Price, and Gateway charts below by plan length.** This is the single factor that changes almost every finding in this report, so it's worth exploring interactively rather than only as static tables:

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

## Revenue Lost to Cancellation

<BarChart
    data={auto_renew_revenue_cancelled_vs_rest}
    x=bucket
    y=revenue_eur
    yFmt='€#,##0'
    labels=true
    labelPosition=right
    labelFmt='€#,##0'
    swapXY=true
    chartAreaHeight=220
/>

<DataTable data={auto_renew_revenue_cancelled_vs_rest}>
  <Column id=bucket title="Bucket" />
  <Column id=revenue_eur fmt='€#,##0' title="Revenue" />
  <Column id=pct_of_total fmt=pct1 title="% of total" />
</DataTable>

<Details title="SQL query used for Revenue Lost to Cancellation">

```sql
SELECT
  CASE WHEN final_status = 'disabled_before_expiry' THEN '1. Lost to cancellation' ELSE '2. Not lost (stayed enabled + no record)' END AS bucket,
  round(sum(billings_eur_excl_vat), 2) AS revenue_eur,
  round(100.0 * sum(billings_eur_excl_vat) / sum(sum(billings_eur_excl_vat)) OVER (), 1) / 100.0 AS pct_of_total
FROM ${subscription_status}
WHERE final_status != 'excluded_unreliable'
GROUP BY 1
ORDER BY bucket
```

</Details>

**€45,779 (40.6% of all revenue tracked) is tied to subscriptions that actively cancelled auto-renew.** Of that, €28,054 (6,689 subscriptions) sits in the highest-leverage window: 12-month plans cancelled within 30 days of renewal.

**No save-flow has been tested, so there's no real recovery rate to cite. The numbers below are a rough sizing exercise.** At an illustrative (not measured) 10% recovery, that's roughly €2,800/year retained; at 5% it's ~€1,400, at 20% it's ~€5,600. Pin down the real number with an actual pilot before it shows up as a commitment in a planning doc.

**Full breakdown, including the "everything else" split into its two parts:**

<DataTable data={auto_renew_revenue_by_outcome}>
  <Column id=outcome />
  <Column id=subscriptions />
  <Column id=revenue_eur fmt='€#,##0' title="Revenue" />
</DataTable>

<Details title="SQL query used for the full 3-way revenue breakdown">

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
WHERE final_status != 'excluded_unreliable'
GROUP BY 1, 2
ORDER BY revenue_eur DESC
```

</Details>

### Which Product Actually Loses the Most Money: Rate vs. Revenue

Every breakdown above shows cancel *rates*. Rate alone can mislead prioritisation: a scary-looking percentage on a tiny product matters less than a modest one on a huge product. Ranked by actual euros lost instead:

<BarChart
    data={auto_renew_cancelled_revenue_by_product}
    x=product_slug
    y=cancelled_revenue
    yFmt='€#,##0'
    labels=true
    labelPosition=right
    labelFmt='€#,##0'
    swapXY=true
    chartAreaHeight=450
/>

Click any column header to sort, e.g. by cancel rate instead of revenue.

<DataTable data={auto_renew_cancelled_revenue_by_product}>
  <Column id=product_slug title="Product" />
  <Column id=subscriptions />
  <Column id=subscriptions_pct fmt=pct1 title="% of total subs" />
  <Column id=cancelled_revenue fmt='€#,##0.00' title="Cancelled revenue" />
  <Column id=cancelled_pct fmt=pct1 title="Cancel rate" />
  <Column id=stayed_pct fmt=pct1 title="Stay rate" />
  <Column id=no_record_pct fmt=pct1 title="No record rate" />
</DataTable>

<Details title="SQL query used for Rate vs. Revenue">

```sql
SELECT
  product_slug,
  count(*) AS subscriptions,
  round(100.0 * count(*) / sum(count(*)) OVER (), 1) / 100.0 AS subscriptions_pct,
  round(sum(CASE WHEN final_status = 'disabled_before_expiry' THEN billings_eur_excl_vat ELSE 0 END), 2) AS cancelled_revenue,
  round(100.0 * sum(CASE WHEN final_status = 'disabled_before_expiry' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS cancelled_pct,
  round(100.0 * sum(CASE WHEN final_status = 'stayed_enabled' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS stayed_pct,
  round(100.0 * sum(CASE WHEN final_status = 'no_record' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS no_record_pct
FROM ${subscription_status}
WHERE final_status != 'excluded_unreliable'
GROUP BY 1
ORDER BY cancelled_revenue DESC
```

</Details>

**`hosting:hostinger_premium` is where the real money is lost: €38,998, 85.2% of all cancelled revenue. `.shop` has the highest cancel rate in the report (55.9%) but only €94 of cancelled revenue (0.2%). The save-flow effort (recommendation #1) should target `hosting:hostinger_premium` first.**

<Details title="Why rate and revenue tell different stories here">

`hosting:hostinger_premium`'s cancel rate (44.6%) is unremarkable next to `.shop`'s 55.9%. Yet it accounts for 85.2% of all cancelled revenue in this report, purely on volume and price. `.shop` has the highest cancel rate in the report but contributes only €94, which is 0.2% of cancelled revenue. Rate and revenue point at two different products here. `domain:.es` is a distant second at €2,818 (6.2%).

</Details>

## Segment Deep-Dive: Product, Plan, Price, Payment

<Details title="Click to expand: Product, Plan, Price, Payment breakdowns">

Cancel *rate* by product, plan length, price, and payment method: supporting detail behind the Overall and Revenue Lost to Cancellation charts above. Worth reading if you want to know *where* the cancellations concentrate, not just how many there are.

## By Product Group

<Heatmap
    data={auto_renew_outcome_by_product}
    x=product_group
    y=outcome
    value=pct
    valueFmt=pct1
/>

<DataTable data={auto_renew_outcome_by_product_wide}>
  <Column id=product_group title="Product group" />
  <Column id=subscriptions />
  <Column id=stayed_pct fmt=pct1 title="Stayed enabled" />
  <Column id=cancelled_pct fmt=pct1 title="Cancelled" />
  <Column id=no_record_pct fmt=pct1 title="No record" />
  <Column id=median_price fmt='€#,##0.00' title="Median price" />
</DataTable>

<Details title="SQL query used for By Product Group">

```sql
SELECT
  product_group,
  count(*) AS subscriptions,
  round(100.0 * sum(CASE WHEN final_status = 'stayed_enabled' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS stayed_pct,
  round(100.0 * sum(CASE WHEN final_status = 'disabled_before_expiry' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS cancelled_pct,
  round(100.0 * sum(CASE WHEN final_status = 'no_record' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS no_record_pct,
  round(median(billings_eur_excl_vat), 2) AS median_price
FROM ${subscription_status}
WHERE period_months::varchar LIKE '${inputs.plan_filter.value}' AND final_status != 'excluded_unreliable'
GROUP BY 1
ORDER BY subscriptions DESC
```

</Details>

**Hosting has both the best retention and the lowest no-record rate of any product.** Domain and mail both show high no-record shares, likely inflated by the tracking gap.

<Details title="How the tracking-gap claim was checked, and why price is shown as median">

For `domain:.es` specifically, no-record sits at 50.6% for subscriptions purchased before March 2022, vs. 9.2% after. That's an 82% relative drop. The tracking gap is real and large. Mail's smaller sample makes it a lead rather than a settled finding.

Price is shown as median, not average. Domain's average price (€0.79) is nearly 3x its median (€0.27). A handful of pricier TLDs (domain extensions) pull the average up. Median better represents what a typical customer actually pays. Average is shown elsewhere only where the total matters more than the typical case.

</Details>

### Hosting Isn't One Product: Shared vs. Cloud

`product_group` treats all of hosting as one bucket. It isn't: shared and cloud hosting are different products with very different retention:

<Heatmap
    data={auto_renew_outcome_by_hosting_subgroup}
    x=product_sub_group
    y=outcome
    value=pct
    valueFmt=pct1
/>

<DataTable data={auto_renew_outcome_by_hosting_subgroup_wide}>
  <Column id=product_sub_group title="Sub-group" />
  <Column id=subscriptions />
  <Column id=stayed_pct fmt=pct1 title="Stayed enabled" />
  <Column id=cancelled_pct fmt=pct1 title="Cancelled" />
  <Column id=no_record_pct fmt=pct1 title="No record" />
  <Column id=median_price fmt='€#,##0.00' title="Median price" />
</DataTable>

<Details title="SQL query used for Hosting: Shared vs. Cloud">

```sql
SELECT
  product_sub_group,
  count(*) AS subscriptions,
  round(100.0 * sum(CASE WHEN final_status = 'stayed_enabled' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS stayed_pct,
  round(100.0 * sum(CASE WHEN final_status = 'disabled_before_expiry' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS cancelled_pct,
  round(100.0 * sum(CASE WHEN final_status = 'no_record' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS no_record_pct,
  round(median(billings_eur_excl_vat), 2) AS median_price
FROM ${subscription_status}
WHERE product_group = 'hosting' AND final_status != 'excluded_unreliable'
GROUP BY 1
ORDER BY subscriptions DESC
```

</Details>

**Cloud hosting retains nearly 19 points better than shared (64.2% vs. 45.4%), and it's not because cloud is pricier. Cloud's typical customer is probably just stickier.**

<Details title="Why we don't think this is just a price effect">

Using *average* price, cloud looked far pricier than shared (€18.36 vs. €6.36). That suggested the retention gap might just be the price story again. But cloud's *median* price is actually €4.80, slightly *below* shared's €5.73. A handful of very expensive cloud plans distort the average. On the typical-customer price, cloud is not more expensive, yet it still retains 19 points better. That weakens the "it's just price" explanation.

**Plausible reasons instead, though none can be fully verified from this data:**
- **Customer type likely differs.** Cloud hosting is typically bought by developers, agencies, or businesses running something with a real operational dependency. That's a stickier customer than someone testing a hobby project.
- **Switching costs are probably higher.** Migrating a cloud setup (DNS, deployments, configs) takes more effort than abandoning shared hosting. Even a dissatisfied customer has more friction to leave.
- **No field in this data indicates business vs. personal use.** That would be the real test of whether "cloud loyalty" is its own effect or a proxy for something else.

</Details>

### Domain TLDs Vary Enormously Too

Same issue, one level down: "Domain" (29.0% stayed) hides a wide range across TLDs:

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

**`.shop` actively cancels at 55.9%**, worse than any other segment in this entire report. Mostly the price story wearing a TLD costume, but still worth surfacing by name since it's something a pricing or promo team can act on directly.

<Details title="Why .shop specifically, and what's driving it">

Largely tracks price again. `.xyz` is free, `.online`/`.store`/`.tech` sit near €0.27-0.30, while `.es` and `.org` cost more and retain better. (`.be` at 66.7% stayed is directional only. n=24 is too small to trust on its own.)

Two things line up for `.shop` specifically:
- **Seasonal concentration.** 218 of 410 signups (53.2%) landed in Aug-Nov 2022, peaking at 67 in November. That's the same Black Friday window flagged as weak elsewhere in this report. No campaign data exists to confirm why, but the overlap is real.
- **A first-year price cliff.** 395 of 410 subscriptions (96.3%) cluster at €0-0.76. A separate group of 15 sits at €5.55-7.99, roughly a 10-20x jump at renewal. `.es`, a better-retaining TLD, sits in a narrow band around €1.7 with no cliff.

Put together, `.shop` looks like a steep first-year price, Black Friday-adjacent signups, and a renewal charge many times the original. It's a sharper, TLD-specific version of the renewal-charge cluster documented for annual plans generally. But this is inferred from prices and dates alone. There's no promo flag or list-price field to confirm whether it was an actual promotion, a standard intro rate, or something else.

Mail was checked for sub-segments too, for consistency. It has none. One `product_sub_group`, one `product_slug` (`hostinger_mail:pro`).

</Details>

## By Plan Length

<Heatmap
    data={auto_renew_outcome_by_plan_length}
    x=plan
    y=outcome
    value=pct
    valueFmt=pct1
/>

<DataTable data={auto_renew_outcome_by_plan_length_wide}>
  <Column id=plan title="Plan" />
  <Column id=subscriptions />
  <Column id=stayed_pct fmt=pct1 title="Stayed enabled" />
  <Column id=cancelled_pct fmt=pct1 title="Cancelled" />
  <Column id=no_record_pct fmt=pct1 title="No record" />
  <Column id=median_price fmt='€#,##0.00' title="Median price" />
</DataTable>

<Details title="SQL query used for By Plan Length">

```sql
SELECT
  period_months || '-month' AS plan,
  period_months,
  count(*) AS subscriptions,
  round(100.0 * sum(CASE WHEN final_status = 'stayed_enabled' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS stayed_pct,
  round(100.0 * sum(CASE WHEN final_status = 'disabled_before_expiry' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS cancelled_pct,
  round(100.0 * sum(CASE WHEN final_status = 'no_record' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS no_record_pct,
  round(median(billings_eur_excl_vat), 2) AS median_price
FROM ${subscription_status}
WHERE final_status != 'excluded_unreliable'
GROUP BY 1, 2
ORDER BY period_months
```

</Details>

**Annual plans activate auto-renew about as reliably as monthly plans but get cancelled at 2.79x the rate afterward.** Since 93.5% of the full dataset is 12-month plans, this single pattern describes what happens to the overwhelming majority of the customer base. The large upfront lump-sum renewal charge is the strongest candidate trigger, exact mechanism unconfirmed.

## By Price Range

<Details title="How the price buckets were chosen">

Boundaries were checked against the real data before picking them. 95.4% of subscriptions are under €10, since prices cluster hard at specific SKU points. The tail thins fast past €20, with only 504 subscriptions above that. An earlier €0.01-2/€2-5 split was tested and rejected. It produced a non-monotonic result that didn't make sense.

</Details>

<Heatmap
    data={auto_renew_outcome_by_price}
    x=price_bucket
    y=outcome
    value=pct
    valueFmt=pct1
/>

<DataTable data={auto_renew_outcome_by_price_wide}>
  <Column id=price_bucket title="Price" />
  <Column id=subscriptions />
  <Column id=stayed_pct fmt=pct1 title="Stayed enabled" />
  <Column id=cancelled_pct fmt=pct1 title="Cancelled" />
  <Column id=no_record_pct fmt=pct1 title="No record" />
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
  count(*) AS subscriptions,
  round(100.0 * sum(CASE WHEN final_status = 'stayed_enabled' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS stayed_pct,
  round(100.0 * sum(CASE WHEN final_status = 'disabled_before_expiry' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS cancelled_pct,
  round(100.0 * sum(CASE WHEN final_status = 'no_record' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS no_record_pct
FROM ${subscription_status}
WHERE period_months::varchar LIKE '${inputs.plan_filter.value}' AND final_status != 'excluded_unreliable'
GROUP BY 1
ORDER BY price_bucket
```

</Details>

**Retention rises steadily and cleanly with price, no reversals.** Stayed-enabled climbs from 33.0% (free) to 73.4% (€20+), more than doubling.

<Details title="Checked the top price bucket for outliers">

The €20+ bucket (max price €109.41) isn't being inflated by a few extreme outliers. 489 of 504 sit in a tight €20-40 range at 74.0% retention. Only 15 sit above €40, at 53.3%, too small to trust alone. If anything, the outliers pull the headline figure down slightly, not up.

</Details>

## By Payment Gateway Type

Card/bank and crypto alone don't cover 100% of subscriptions: they're 85.1% of the 34,411 total. The remaining ~15% splits into two distinct groups, shown below rather than left out.

<Heatmap
    data={auto_renew_outcome_by_payment_gateway}
    x=gateway_type
    y=outcome
    value=pct
    valueFmt=pct1
/>

<DataTable data={auto_renew_outcome_by_payment_gateway_wide}>
  <Column id=gateway_type title="Gateway type" />
  <Column id=subscriptions />
  <Column id=stayed_pct fmt=pct1 title="Stayed enabled" />
  <Column id=cancelled_pct fmt=pct1 title="Cancelled" />
  <Column id=no_record_pct fmt=pct1 title="No record" />
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
  count(*) AS subscriptions,
  round(100.0 * sum(CASE WHEN final_status = 'stayed_enabled' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS stayed_pct,
  round(100.0 * sum(CASE WHEN final_status = 'disabled_before_expiry' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS cancelled_pct,
  round(100.0 * sum(CASE WHEN final_status = 'no_record' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS no_record_pct
FROM ${subscription_status}
WHERE period_months::varchar LIKE '${inputs.plan_filter.value}' AND final_status != 'excluded_unreliable'
GROUP BY 1
ORDER BY gateway_type
```

</Details>

**We don't know why crypto's no-record rate is so high. This data has no field that explains it.**

<Details title="One assumption worth testing">

Crypto payments generally can't be stored for automatic re-billing the way a card can. That would make this a platform constraint rather than a behavioural signal. But that's a guess, not a finding. "No gateway on file" (14.6% of subscriptions) has a meaningfully elevated no-record rate too, and the same caveat applies.

</Details>

</Details>

---

# When Do Cancellations Happen?

Split by plan length, since "days before renewal" means very different things for a 30-day term vs. a 365-day term.

**1-month plans** (n=316; excludes 3 subscriptions with a data error; see Appendix)

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

These 4 buckets cover the entire possible range (0-30 days) and sum to 100%: every 1-month cancellation is trivially "within 30 days," since the whole term only lasts 30 days. So "within 30 days" doesn't mean anything for monthly plans. (Mean 14.3 days, median 16.0 days on before cancelling, roughly the halfway point of the term.)

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

**53.3% of annual-plan cancellations happen within 30 days of renewal**, a plausible reaction to renewal-reminder emails or notifications. This clustering points to the size and timing of the annual renewal charge as the driver, not a general late-term pattern, exact mechanism unconfirmed. (Mean 270.5 days, median 336.0 days on before cancelling, heavily back-loaded to the final quarter of the term: 69.8% of annual cancellations happen in the final 3 months.)

---

# Returning Customers: Turned Auto-Renew Off, Then Back On

365 of 34,411 subscriptions (1.1%) turned auto-renew off, then back on again, at least once during their term. Everything above uses only their *most recent* window, discarding this history. Looked at on its own (361 of the 365; 4 have their most recent window among the 20 excluded-unreliable records from the Appendix, so they're left out of the outcome split below, same as everywhere else in this report):

<Heatmap
    data={auto_renew_returning_customers_outcome}
    x=grp
    y=outcome
    value=pct
    valueFmt=pct1
/>

<DataTable data={auto_renew_returning_customers_outcome_wide}>
  <Column id=grp title="Group" />
  <Column id=n title="Subscriptions" />
  <Column id=stayed_pct fmt=pct1 title="Stayed enabled" />
  <Column id=cancelled_pct fmt=pct1 title="Cancelled" />
</DataTable>

<Details title="SQL query used for Returning Customers">

```sql
SELECT
  CASE WHEN n_windows > 1 THEN 'Toggled more than once' ELSE 'Never toggled back' END AS grp,
  count(*) AS n,
  round(100.0 * sum(CASE WHEN final_status = 'stayed_enabled' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS stayed_pct,
  round(100.0 * sum(CASE WHEN final_status = 'disabled_before_expiry' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS cancelled_pct
FROM ${subscription_status}
WHERE final_status NOT IN ('no_record', 'excluded_unreliable')
GROUP BY 1
ORDER BY grp
```

</Details>

**Customers who turn auto-renew off and then back on end up far more likely to stay enabled (68.1%) than everyone else (49.1%)**, a strong signal that re-engagement works, and worth understanding since it may be a cheap, repeatable save tactic.

<Details title="Supporting detail">

These customers already showed intent to cancel once, then changed their mind. 12-month plans re-enable at over 4x the rate of monthly plans, even after adjusting for volume. Domain leads among products.

**Same product every time, which is structurally guaranteed rather than a finding.** A subscription can't switch products mid-term. All 365 returners re-enable the exact same `product_slug` and price they started with.

**They skew slightly cheaper.** Median price for returners is €1.71, vs. €2.62 for everyone else. Lower-stakes plans are easier to flip back on.

**Timing varies widely.** Median 53 days between turning it off and back on (mean 104.4 days, pulled up by a long tail, range 2-368). Half come back within under two months. But there's no tight, predictable window to design a save-flow trigger around.

</Details>

---

# Seasonality

For 12-month plans, the renewal date falls in the same calendar month as the original purchase, a year later. For 1-month plans it's simply the following month. Switch between them below. The two plan lengths have different volumes and different patterns, so they're shown one at a time rather than blended. Full dataset, all three outcomes, no date filter applied.

This is the same one-outcome-per-subscription view as the Signup Cohorts section further down, with one difference: here every year is collapsed into a single Jan-Dec calendar, keyed to when the term ends, to isolate a repeating seasonal pattern. That section keeps the raw month-by-month timeline instead.

**Each bar is a sum across every year in the dataset (renewal dates span 2021-2023), not a single year's volume**, so a one-off spike in any single year doesn't get mistaken for a real seasonal pattern.

<Dropdown name=seasonality_plan>
    <DropdownOption value=12 valueLabel="12-month plans"/>
    <DropdownOption value=1 valueLabel="1-month plans"/>
</Dropdown>

<BarChart
    data={auto_renew_seasonality_by_renewal_month}
    x=renewal_month
    y=cancelled_pct
    yFmt=pct1
    y2=term_end_subscriptions
    y2SeriesType=line
    sort=false
    labels=true
    labelPosition=center
    chartAreaHeight=350
/>

<DataTable data={auto_renew_seasonality_by_renewal_month}>
  <Column id=renewal_month title="Month" />
  <Column id=term_end_subscriptions title="Subscriptions with term ending this month (all years combined)" />
  <Column id=stayed_pct fmt=pct1 title="Stayed enabled" />
  <Column id=cancelled_pct fmt=pct1 title="Cancelled" />
  <Column id=no_record_pct fmt=pct1 title="No record" />
</DataTable>

<Details title="SQL query used for Seasonality">

```sql
SELECT
  strftime(ended_at, '%m-%b') AS renewal_month,
  count(*) AS term_end_subscriptions,
  round(100.0 * sum(CASE WHEN final_status = 'stayed_enabled' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS stayed_pct,
  round(100.0 * sum(CASE WHEN final_status = 'disabled_before_expiry' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS cancelled_pct,
  round(100.0 * sum(CASE WHEN final_status = 'no_record' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS no_record_pct
FROM ${subscription_status}
WHERE period_months = ${inputs.seasonality_plan.value} AND final_status != 'excluded_unreliable'
GROUP BY 1
ORDER BY 1
```

</Details>

**November is the worst-retaining month for 12-month plans (46.1% cancelled). But switch to the 1-month view and the November dip disappears entirely, suggesting the effect is specific to annual-plan buyers, not a general seasonal pattern.**

<Details title="Supporting detail, both views">

On the 12-month view (the default above), November is both the highest-volume renewal month (4,158) and one of the worst-retaining (30.6% stayed, 46.1% cancelled). That's plausibly tied to Black Friday driving price-sensitive signups. January and February stand out for a different reason. Their no-record rates sit at 38.1% and 34.7%, well above every other month (15-29% elsewhere). Check that against the tracking-gap timing before reading it as a real January/February effect, since these two months draw more heavily from the earlier, less-reliable cohort.

On the 1-month view, November sits at 58.7% stayed. That's unremarkable, near the middle of the range (42.5-65.3% across all 12 months). December is the standout month for 1-month plans instead. It has the highest volume (267) and, alongside January and February, one of three elevated no-record rates (34.8% / 33.6% / 41.1%), consistent with the same tracking-gap pattern seen in the 12-month view.

</Details>

---

# Signup Cohorts: Outcome Over Time

**A signup cohort here is every subscription that started in the same calendar month, tracked to its final outcome (stayed enabled / actively cancelled / no record) by the end of that subscription's own term.** It's not a multi-year retention curve. This dataset has no customer ID to follow the same person across renewal cycles (see Appendix). It's a same-term, one-outcome-per-subscription view, shown on the raw month-by-month timeline and grouped by when people signed up.

**On the full, unfiltered dataset: the cancel rate roughly doubles right when the no-record rate collapses (March 2022). That's a tracking-gap fix becoming visible, not a real behaviour change.** Use the dropdowns below to check whether that holds for a specific product or TLD.

<Details title="How to use this view, and how it differs from Seasonality above">

1. Pick a product group from the first dropdown.
2. Optionally narrow to a specific slug in the second dropdown (e.g. a single TLD like `.shop`).
3. Watch how that signup-month cohort's outcomes trend over time.

**How this differs from Seasonality above:** Seasonality collapses every year into one Jan-Dec pattern to isolate a *repeating* calendar effect. This view is the raw chronological timeline (actual year-month) for a specific product, with no year-collapsing.

</Details>

<Dropdown data={auto_renew_distinct_product_groups} name=group_filter value=product_group>
    <DropdownOption value="%" valueLabel="All product groups"/>
</Dropdown>

<Dropdown data={auto_renew_distinct_product_slugs} name=slug_filter value=product_slug>
    <DropdownOption value="%" valueLabel="All slugs in this group"/>
</Dropdown>

*Small segments will look jumpy month to month. Percentages on a handful of subscriptions aren't meaningful.*

<LineChart
    data={auto_renew_outcome_timeseries}
    x=month
    y=pct
    yFmt=pct1
    series=outcome
    labels=true
    labelPosition=top
    labelFmt=pct1
    chartAreaHeight=350
>
    <ReferenceLine x='2022-03-01' label="Tracking fix visible" hideValue=true/>
</LineChart>

<Details title="Same data as a cancellation-rate trend against total volume, plus the exact per-outcome % for every month">

<BarChart
    data={auto_renew_outcome_timeseries_wide}
    x=month
    y=subscriptions
    y2SeriesType=line
    y2=cancelled_pct
    y2Fmt=pct1
    chartAreaHeight=300
/>

<DataTable data={auto_renew_outcome_timeseries_wide}>
  <Column id=month />
  <Column id=subscriptions />
  <Column id=stayed_pct fmt=pct1 title="Stayed enabled" />
  <Column id=cancelled_pct fmt=pct1 title="Cancelled" />
  <Column id=no_record_pct fmt=pct1 title="No record" />
</DataTable>

<Details title="SQL query used for the volume + cancellation-rate chart and table above">

```sql
SELECT
  date_trunc('month', started_at) AS month,
  count(*) AS subscriptions,
  round(100.0 * sum(CASE WHEN final_status = 'stayed_enabled' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS stayed_pct,
  round(100.0 * sum(CASE WHEN final_status = 'disabled_before_expiry' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS cancelled_pct,
  round(100.0 * sum(CASE WHEN final_status = 'no_record' THEN 1 ELSE 0 END) / count(*), 1) / 100.0 AS no_record_pct
FROM ${subscription_status}
WHERE product_group LIKE '${inputs.group_filter.value}'
  AND product_slug LIKE '${inputs.slug_filter.value}'
  AND final_status != 'excluded_unreliable'
GROUP BY 1
ORDER BY 1
```

</Details>

</Details>

<Details title="What the month-by-month numbers show">

No-record spikes as high as 68% (June 2021) and stays elevated through February 2022. Then it drops sharply to a stable 11-16% from March 2022 onward, matching the tracking-gap cutoff used throughout this report. As no-record falls, cancelled % rises in near lock-step, from the 20-30% range pre-2022 to 37-56% from March 2022 on. The most likely read is that many pre-March-2022 "no record" subscriptions were real cancellations that just weren't logged. Once tracking improved, the true cancel rate became visible, not higher.

One nuance worth flagging. The gap isn't uniform across "before March 2022." January-April 2021 actually shows a *lower* no-record rate (21-28%) than May 2021-February 2022 (38-68%). The tracking problem has a specific onset around May 2021, not from the start of the dataset. That's worth mentioning if the data team tries to pin down exactly when the logging issue began.

Volume also grows over the period, from roughly 700-900/month in early-mid 2021 to 1,500-2,700/month by late 2022. There's a visible spike every November in both years, consistent with the Black Friday pattern flagged elsewhere in this report.

</Details>

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
  count(*) AS subscriptions,
  round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY date_trunc('month', started_at)), 1) / 100.0 AS pct
FROM ${subscription_status}
WHERE product_group LIKE '${inputs.group_filter.value}'
  AND product_slug LIKE '${inputs.slug_filter.value}'
  AND final_status != 'excluded_unreliable'
GROUP BY 1, 2, 3
ORDER BY 1
```

</Details>

The slug dropdown updates to only show slugs belonging to the currently selected product group: switch to "domain" and it narrows to TLDs; switch to "hosting" and it narrows to shared/cloud slugs.

---

# Appendix: Assumptions, Limitations & Data Quality Findings

Before acting on anything above, here's what could complicate it: judgement calls made along the way, open questions, and data issues found and corrected during analysis.

## Assumptions and Limitations

- **Pre-March 2022 subscriptions are more likely to show "no record," a tracking gap, not real behaviour. Kept in the data, not excluded.**

  <Details title="Detail">

  Subscriptions purchased before March 2022 show a "no record" rate as high as 68% in some months, vs. a stable ~11-16% from March 2022 onward. This is treated as a logging/rollout gap, not real customer behaviour. Every figure in this report includes the full dataset (34,411 subscriptions). The older cohort is simply more likely to land in the "no record" bucket than it should.

  **Not allocated to "stayed enabled" or "cancelled," for two reasons.** First, the size. 26.0% (8,945 subscriptions) is too large to guess in either direction. Assuming all of it cancelled pushes the cancel rate to 63.4%. Assuming all of it stayed pushes retention to 62.6%. Neither guess is more justified than the other. Second, the sharp, dated drop at March 2022 looks like a fix being introduced, not a gradual decline. That points to a knowable, fixable root cause rather than a permanent gap to estimate around. **The recommendation is to track down and fix the underlying issue, not to model or impute the missing values** (see Recommendation #6).

  </Details>

- **26.0% of subscriptions have zero evidence auto-renew was ever touched. Kept as its own category rather than guessed at, because we can't tell why.**

  <Details title="The two live theories, and what's been ruled out">

  There is no enable *or* disable event logged for this group. Not "touched but unexplained." Nothing at all. The "auto-renew is usually on by default" policy would settle this only if these subscriptions started on, and "usually" leaves room for exceptions.

  **Ruled out: the checkout-checkbox theory.** A customer declining an auto-renew checkbox at checkout can't explain it. Checkout has no such option in the flow, confirmed with the product team.

  **Two live theories remain.** (1) Auto-renew was switched on and off within the same session. The data stores dates, not timestamps, so anything that reverses within one day leaves no trace. (2) This segment genuinely never had auto-renew touched, a real exception to the default-on policy.

  **Two direct tests were run against theory (1).** First, same-day on/off events do get logged. 333 windows in the data have enable and disable on the same calendar day, so "too fast to log" can't be a blanket explanation. It proves nothing about sub-day speed, though. Second, the no-record group isn't disproportionately free or payment-less, which rules out a simple product-exemption story. Both tests weaken theory (1) without eliminating it. The group stays its own neutral category until the data owner can answer the question.

  </Details>

- **No customer/account-level ID.** Only `subscription_id` is available: a customer with several subscriptions is counted once per subscription; cross-product customer behaviour can't be observed.
- **No order-type / checkout-flow field, and no event timestamps (dates only).** Can't distinguish an original purchase from a renewal-generated continuation. `ar_valid_from`/`ar_valid_to` are dates, not timestamps: anything that happens and reverses within the same day leaves no trace.

## Data Quality Findings

Three distinct issues surfaced during analysis. One (below, "20 Records Excluded") was corrected directly in the classification logic, not just noted; the other two are flagged for the data/engineering team but don't change any number in this report.

- **Tracking gap, pre-March 2022.** A likely rollout gap in the `ar_valid_from`/`ar_valid_to` logging mechanism, not a product or customer issue. Included in all figures, not excluded, but inflates "no record" for that period.
- **2,239 subscriptions activated auto-renew late (after signup, not immediately). Kept in every chart, since their outcome is still trustworthy.**

  <Details title="Why this is safe to keep">

  Auto-renew turned on some time after signup for these 2,239 subscriptions (651 free, 1,588 paid). The group skews towards free or no-payment signups. Its zero-billing rate is 29.1% vs. 13.1% for on-time activations, and 21.4% have no payment gateway on file vs. 11.6%. That's only a partial explanation, though. 70.9% still paid something.

  They're safe to keep because classification depends on `ar_valid_to`, not `ar_valid_from`, and that date is normal for all 2,239. For 63.3% it matches `ended_at` exactly, meaning they stayed enabled after the late start. The rest disabled again before term end. When activation happened doesn't affect whether the outcome is read correctly. The 20 excluded records below are different. There, the corrupted date is the one classification actually depends on.

  </Details>

- **5 unexpected free (€0) hosting/mail records.** Hosting and mail are otherwise almost never free (0-0.2% of records), so these 5 stand out numerically. No promo flag or comp-reason field exists in this data to confirm *why*; stated here as an observed anomaly, not a guessed cause.

<Details title="Additional checks that came back clean">

`period_months` has only 2 values (1 and 12), confirmed exhaustive. Term length matches `period_months` in every row (1-month: 28-31 actual days; 12-month: exactly 365, always). `product_group`, `product_sub_group`, `product_slug`, `billings_eur_excl_vat` have zero nulls; `payment_gateway`'s 5,079 nulls are already accounted for in the gateway breakdown above.

</Details>

## 20 Records Excluded From Every Chart Above

Two distinct bugs, both resulting in a subscription's classification being untrustworthy. Both are removed from every chart, table, and percentage in this report, and listed below.

**Group 1 (17 subscriptions, all `domain:.es`):** dates in an impossible order, likely a batch job bug. **Group 2 (3 subscriptions, all `hosting:hostinger_premium`):** the logged window predates the subscription itself.

<Details title="Detail on both groups">

**Group 1 (17 subscriptions, 18 raw rows):** `ar_valid_from` is dated *after* `ar_valid_to`, which is impossible. Several share identical dates across unrelated subscriptions. Four different ones all show `2023-03-15`, which points to a batch job stamping its own run date into old, closed records. (18 rows collapse to 17 subscriptions because one had two broken rows. Only its most recent survives the one-row-per-subscription step used throughout this analysis.) For all of them `ar_valid_to` still equals `ended_at`, so "stayed enabled" would have been the right call anyway. But a row with a provably impossible date order doesn't get trusted here.

**Group 2 (3 subscriptions):** the whole logged auto-renew window predates the subscription's own start date. This is worse than Group 1, because the corrupted field (`ar_valid_to`) is exactly the one classification depends on. All 3 cost exactly €2.4456 across 3 different payment gateways. An identical price suggests one shared root cause, not three separate customer actions.

</Details>

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

Excluding these 20 records (0.058% of 34,411) doesn't change any headline percentage at 1 decimal place (37.4% / 36.6% / 26.0%). Both bugs should go to the data team as bug reports, and these 20 can be re-classified once the root cause is confirmed.

---

# Conclusions

**When do users enable or disable auto-renew, and what can the product team do to improve the auto-renew rate?** Concisely, what the data shows:

1. **The problem is retention, not activation.** Most subscriptions do turn auto-renew on (26.0% have no activation on record, and part of that is a tracking gap). 37.4% actively cancel *after* activating, the bigger, more fixable group.

2. **Cancellation clusters right before the big charge, not gradually**, consistent with sticker shock, though the data can't isolate that specific mechanism from a general term-end effect.

   <Details title="Detail">

   53.3% of annual cancellations happen within 30 days of renewal, and 69.8% within the final 3 months. Annual plans cancel at 2.79x the rate of monthly plans despite activating just as reliably. The renewal charge is the strongest candidate trigger. Timing fits, but the exact mechanism (reminder vs. price jump vs. term-end salience) isn't isolated.

   </Details>

3. **Price predicts retention, but not everything is price.** Retention rises steadily with price (33.0% free → 73.4% at €20+). But cloud hosting retains 19 points better than shared (64.2% vs. 45.4%) despite *not* being pricier by median: a real product/customer effect, not just price.

4. **The biggest cancel rate isn't where the biggest money loss is.** `hosting:hostinger_premium` drives 85.2% of cancelled revenue (€38,998) on an unremarkable 44.6% rate; `.shop` has the worst rate (55.9%) but only 0.2% of the euros. Prioritise by revenue, not rate.

5. **Customers who come back once tend to stay.** Re-enablers retain far better afterward (68.1% vs. 49.1%), a real, repeatable save signal, though the timing to come back varies too widely (2-368 days) to target a single trigger window.

6. **Two patterns are real but unconfirmed:** crypto's near-zero activation rate, and the November/Black Friday retention dip. Flagged as open questions throughout, not settled facts.

   <Details title="Where these are discussed in full">

   Crypto: see Payment & Timing (Executive Summary) and By Payment Gateway Type. November/Black Friday: see Seasonality and the `.shop` deep-dive under Segment Deep-Dive.

   </Details>

---

# Recommendations

1. **Target annual `hosting:hostinger_premium` customers with a save offer 15-30 days before renewal.** The single biggest lever by both count and revenue.

   <Details title="Why">

   - **How many cancel:** 39.1% of annual subscriptions actively cancel, over half of those within the final 30 days before renewal.
   - **The cliff is sharper for `hostinger_premium` specifically:** 65.4% of its annual cancellations fall within 30 days of renewal, vs. 41.9% for all other products.
   - **Where the money is:** `hosting:hostinger_premium` alone accounts for 85.2% of all cancelled revenue (€38,998), far more than its cancel rate alone would suggest.
   - **The size of the opportunity (no recovery rate has actually been measured yet):** €28,054 in current-term revenue sits in that 30-day pre-renewal window, across all products. An illustrative 10% recovery is ~€2,800/year retained; 5% is ~€1,400, 20% is ~€5,600. Don't plan around any single number here; pilot the save flow first, measure the real rate, then re-run this math.

   </Details>

2. **Make the annual renewal charge less jarring.** Four tactics, ordered by how directly they address the trigger:

   - **"Decoupled" billing:** charge monthly amounts, but frame it as "your annual plan, billed monthly." This keeps the annual discount and commitment psychology without the customer ever seeing one large number, basically the gym/insurance model.
   - **A value recap, not just a reminder.** A bare "your card will be charged €X on [date]" notice may itself be part of the trigger, not just a warning about it. Pair it with a personalised "here's what you got this year" (usage stats, milestones, savings vs. monthly pricing) so the renewal notification arrives with justification attached, not just a bill.
   - **Time it 45-60 days out**, before the 30-day cancellation cluster starts, so it reframes the decision before the sticker-shock reflex kicks in, rather than triggering it.
   - **Offer a pause, not just cancel-or-keep.** A middle option may capture customers who'd cancel outright when the only choice is binary.

   <Details title="Why: the theory, the evidence, and an important caveat">

   **The theory:** a monthly plan spreads cost into 12 small charges; an annual plan is one large lump sum, a year after the customer last thought about it. Behaviourally, a single large, half-forgotten charge is a much sharper trigger to cancel than the same total spread thin.

   **What supports it, beyond the 2.79x rate gap:** cancellation timing clusters tightly around the renewal date rather than spreading evenly across the year. 53.3% of annual cancellations happen within 30 days of renewal, and 69.8% happen in the final 3 months of the term. The cancel event itself happens *before* the term expires, not after, which is consistent with customers reacting to a renewal-reminder notification and cancelling pre-emptively rather than getting charged first and complaining afterward. Annual plans also cancel at 2.79x the rate of monthly despite activating just as reliably at purchase, so it isn't that annual buyers are lower-quality customers from the start. Something specific to the renewal moment is driving it.

   **Important caveat:** this data has no field confirming reminder emails exist, when they're sent, or what they say. "Customers react to a renewal reminder" is itself an assumption, not something confirmed here. It's possible the reminder is partly *manufacturing* the 30-day cancellation spike rather than just revealing pre-existing intent. Before rolling any of the four tactics above out broadly, A/B test whether the current reminder (if one exists) helps or hurts retention, and test the value-recap version against a no-recap control. Don't assume the mechanism, measure it.

   </Details>

3. **Investigate domain and mail no-record rates, but confirm the tracking-gap contribution first.**

   <Details title="Why">

   Both skew towards the less-reliable pre-March-2022 cohort. Hosting, which skews more recent, has a much lower no-record rate and may just be more cleanly tracked.

   </Details>

4. **Get confirmation on whether crypto's near-100% no-record rate is a technical limitation or something else.**

   <Details title="Why">

   We don't know the cause. No field in this data explains it. One assumption worth testing is a platform constraint, since crypto generally can't be stored for automatic re-billing. But that's a guess, not a finding. Ask whoever owns the payment integration directly before treating it as settled and excluding crypto from auto-renew health metrics on that basis.

   </Details>

5. **Give the November 2022 cohort a dedicated retention plan, but confirm the Black Friday explanation first.**

   <Details title="Why">

   November is the largest signup month and one of the worst-retaining. €6,076 in cancelled 12-month subscriptions came from the November 2022 cohort alone (€8,395 across all November signups, all years). This report has no promotional or campaign data. The Black Friday link is an assumption based on timing alone, meaning the November volume spike plus calendar proximity, not a confirmed cause. Confirm it with whoever ran marketing that year, and check that the pattern repeats in future years, before treating it as permanent.

   </Details>

   **Three deeper checks were run against the theory: timing partly supports it, price argues against it, and the strongest test can't be run at all with this data.** The three checks point in different directions, so they're listed separately rather than summarised into one verdict.

   <Details title="The three checks, in detail">

   **1. Timing: supports the theory in 2022, weak in 2021.** Black Friday (Nov 25) and Cyber Monday (Nov 28) 2022 were the two highest-volume signup days in the late-November window. They hit 126 and 122, against 69-118 on surrounding days. A real, specific spike. The same two days in 2021 (70 and 74, against 36-76) barely stand out. That's more a gradual late-month ramp. The year-over-year difference is itself a question marketing can answer. Did Black Friday spend or discount depth change between 2021 and 2022? If yes, the causal story gets stronger, since spike size tracks promo intensity. If no, it's a point against.

   **2. Price: no discount signature, once product mix is controlled for.** Within the same product group, November prices are flat against other months. Domain is marginally cheaper (€0.71 vs. €0.80 avg) and hosting marginally pricier on 12-month plans (€7.41 vs. €7.00). We looked for a discount fingerprint and didn't find one. That argues against a simple promo-discount-churn mechanism. One caveat. A flat-rate promo that wasn't applied universally wouldn't necessarily lower the average, so a promotion isn't fully ruled out. It's just not supported.

   **3. Mechanism: can't be tested with this data.** The decisive test is whether churn concentrated among accounts whose price jumped at renewal, i.e. a discount expiring. That needs each customer's first-year price linked to their renewal-year price. With no customer ID, the two terms can't be joined at all. This is the one test that would separate promo-driven from channel-driven from seasonal-intent churn. It's worth a concrete data request. Even a partial identifier (email hash, payment token) for a sample of November customers would do. Get that before finalising a retention plan built on an unconfirmed mechanism.

   </Details>

6. **Track down and fix the "no record" logging gap. Don't model or guess around it.** The single biggest open question in this whole analysis, and at 26.0% (8,945 subscriptions) too large to leave unresolved.

   <Details title="Why">

   Does a blank `is_auto_renew` mean auto-renew was enabled and cancelled within the same session, too fast to log since the data only has dates? Or was it never touched at all? The checkout-checkbox theory is already ruled out, since no such option exists in the flow. That narrows it to one real question. Could the logging system miss a same-session on/off event? See Assumptions and Limitations in the Appendix.

   **Why this looks fixable:** the no-record rate isn't a flat, ongoing problem. It drops sharply and specifically at March 2022, from as high as 68% in some months down to a stable 11-16%. That looks like a fix was already introduced then, whether intentional or not. The root cause should be findable, not something to live with indefinitely.

   **How this report treated it in the meantime:** it stays its own `no_record` category everywhere. It's never folded into "cancelled" or "stayed enabled," and never allocated proportionally either. The segment is too large to guess. All-cancelled pushes the cancel rate to 63.4%. All-stayed pushes retention to 62.6%. Either choice would silently bake an unconfirmed guess into every headline number. The fix is to find and resolve the logging issue, not to estimate around it.

   </Details>

7. **Fix the underlying tracking gap and the two isolated data-quality bugs** (`.es` domain batch job, `hosting_premium` window-predates-start) before any future auto-renew reporting relies on this pipeline again.

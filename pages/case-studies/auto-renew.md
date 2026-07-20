---
title: Auto-Renew Dynamics Analysis
queries:
  - subscriptions.sql
  - subscription_status.sql
  - auto_renew/outcome_overall.sql
  - auto_renew/revenue_by_outcome.sql
  - auto_renew/outcome_by_product.sql
  - auto_renew/outcome_by_plan_length.sql
  - auto_renew/outcome_by_price.sql
  - auto_renew/outcome_by_payment_gateway.sql
  - auto_renew/cancellation_timing_1mo_plans.sql
  - auto_renew/cancellation_timing_12mo_plans.sql
  - auto_renew/cancellation_duration_1mo_plans.sql
  - auto_renew/cancellation_duration_12mo_plans.sql
  - auto_renew/returning_customers_outcome.sql
  - auto_renew/seasonality_by_renewal_month.sql
---

A subscription-based hosting/domain provider needed to understand **when users tend to enable or disable their auto-renew**. The goal was to understand behavioral patterns and provide actionable insights and suggestions to improve the auto-renew rate, for non-technical stakeholders on the product team.

Key questions included:
- When do customers tend to enable or disable auto-renew?
- Is the bigger problem activation (never turning it on) or retention (turning it off later)?
- Which segments — product, plan length, price, payment method — have the healthiest auto-renew rates?

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

**Hosting has both the best retention and the lowest no-record rate of any product.** Domain and mail both show high no-record shares — domains skew heavily toward the pre-March-2022 cohort, so that number is likely inflated by the tracking gap; mail's smaller sample makes it a lead, not a settled finding.

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

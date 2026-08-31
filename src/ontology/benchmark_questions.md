# Executive Analyst — Genie benchmark questions (Step 4)

Use these to evaluate the Genie space. Prefer fixing **metric views / sql_snippets / glossary** over growing `text_instructions`.

Catalog: `gold_dev`. OEE is **0–100** percent; below 70% → `OEE_PCT < 70` / `oee_below_70`.

## PRD samples (8)


| #   | Question                                    | Domain / view                  | Expected binding                                    | Pass notes                       |
| --- | ------------------------------------------- | ------------------------------ | --------------------------------------------------- | -------------------------------- |
| 1   | How is the business doing this quarter?     | Cross: all five `metrics_*`    | Separate queries; no cross-domain JOIN              | Touches revenue + OEE + stockout |
| 2   | Top 5 campaigns by ROAS last month          | `metrics_campaign_performance` | `MEASURE(weighted_roas)`; never `AVG(ROAS)`         | Group by `campaign_name`         |
| 3   | Which plants had OEE below 70% last week?   | `metrics_production_execution` | `oee_below_70` or `OEE_PCT < 70`                    | Use `plant_name`                 |
| 4   | Parts at high stockout risk                 | `metrics_inventory_snapshot`   | `high_stockout` + `is_current_snapshot`             | Never sum on-hand across dates   |
| 5   | Supplier quality scores for Q2              | `metrics_supplier_quality`     | `MEASURE(average_quality_score)`, `ppm`, `copq`     | By `supplier_name`               |
| 6   | Total revenue vs discount amount this month | `metrics_sales_order`          | `MEASURE(total_revenue)`, `MEASURE(total_discount)` | Not bookings unless asked        |
| 7   | Marketing cost per lead by channel          | `metrics_campaign_performance` | `MEASURE(cost_per_lead)` by `channel_name`          | Never `AVG(COST_PER_LEAD)`       |
| 8   | Production downtime trends by shift         | `metrics_production_execution` | `MEASURE(total_downtime)` by `shift_code`           |                                  |




## Failure / disambiguation (7+)


| #   | Question                                                   | Expected behavior                                                                            | Pass notes               |
| --- | ---------------------------------------------------------- | -------------------------------------------------------------------------------------------- | ------------------------ |
| 9   | What was our marketing cost last month?                    | Clarify or use campaign spend (`MEASURE(total_spend)` / CPL) — not COPQ/discount without ask | Ambiguous **cost**       |
| 10  | Which plants are inefficient this week?                    | Clarify OEE vs inventory turnover; if production → OEE                                       | Ambiguous **efficiency** |
| 11  | Total inventory value across all dates                     | Refuse / correct: single snapshot / `is_current_snapshot`; never SUM valuation across dates  | Snapshot summing trap    |
| 12  | Average ROAS by channel last month                         | `MEASURE(weighted_roas)` by channel — **not** `AVG(ROAS)`                                    | Weighted ROAS            |
| 13  | How many conversions did we get from campaigns last month? | Marketing `MEASURE(total_conversions)` — **not** DELIVERED orders                            | Conversion ≠ delivered   |
| 14  | Show parts at high stockout risk on the current snapshot   | `high_stockout` + `is_current_snapshot`; `part_name`                                         | Certified stockout       |
| 15  | Revenue recognized vs bookings this month                  | `MEASURE(total_revenue)` vs `MEASURE(total_bookings)`                                        | Revenue ≠ bookings       |




## C-suite voice (by executive theme)

Ask these as a CEO / CXO. They should still bind to certified measures — no invented HR, P&L, or legal datasets. Catalog: `gold_dev`.

### 1. Revenue & Growth


| #   | Question                                                                                            | Domain / view                  | Expected binding                                      | Pass notes                     |
| --- | --------------------------------------------------------------------------------------------------- | ------------------------------ | ----------------------------------------------------- | ------------------------------ |
| C1  | How is revenue tracking this quarter versus last quarter?                                           | `metrics_sales_order`          | `MEASURE(total_revenue)` by quarter                   | Not bookings unless asked      |
| C2  | Which dealers and vehicle models are actually growing our top line this month?                      | `metrics_sales_order`          | `total_revenue` by `dealer_name`, `model_name`        | Rank / top contributors        |
| C3  | What is the bookings pipeline versus recognized revenue this month?                                 | `metrics_sales_order`          | `MEASURE(total_bookings)` vs `MEASURE(total_revenue)` | Revenue ≠ bookings             |
| C4  | Are we converting marketing spend into growth — which campaigns delivered the best ROAS last month? | `metrics_campaign_performance` | `MEASURE(weighted_roas)` by `campaign_name`           | Never `AVG(ROAS)`              |
| C5  | Which customer segments are driving campaign conversions this quarter?                              | `metrics_campaign_performance` | `MEASURE(total_conversions)` by `segment_name`        | Conversions ≠ DELIVERED orders |




### 2. Profitability & Cost


| #   | Question                                                                           | Domain / view                  | Expected binding                                                                 | Pass notes                                                            |
| --- | ---------------------------------------------------------------------------------- | ------------------------------ | -------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| C6  | How much discount are we giving away relative to revenue this month?               | `metrics_sales_order`          | `MEASURE(total_discount)`, `MEASURE(total_revenue)`, `MEASURE(discount_percent)` | Percent is 0–100, not INR — separate columns, no stacked value column |
| C7  | What is our marketing cost per lead by channel, and is spend efficient?            | `metrics_campaign_performance` | `MEASURE(cost_per_lead)`, `MEASURE(total_spend)` by `channel_name`               | Never `AVG(COST_PER_LEAD)`                                            |
| C8  | What is the cost of poor quality this quarter, and which suppliers are driving it? | `metrics_supplier_quality`     | `MEASURE(copq)` by `supplier_name`                                               | COPQ ≠ campaign spend                                                 |
| C9  | If I say “what did we spend last month,” what costs should I look at first?        | Cross                          | Clarify: campaign spend / CPL vs COPQ vs discount                                | Ambiguous **cost**                                                    |




### 3. Customers


| #   | Question                                                                                     | Domain / view                  | Expected binding                                                 | Pass notes                       |
| --- | -------------------------------------------------------------------------------------------- | ------------------------------ | ---------------------------------------------------------------- | -------------------------------- |
| C10 | Which customer segments are we reaching most effectively this quarter?                       | `metrics_campaign_performance` | conversions / CPL / ROAS by `segment_name`                       | Marketing segment, not CRM LTV   |
| C11 | Are we delivering what we booked — delivered-order revenue versus total bookings this month? | `metrics_sales_order`          | `MEASURE(delivered_order_revenue)` vs `MEASURE(total_bookings)`  | DELIVERED ≠ marketing conversion |
| C12 | Which dealers are our most important customer-facing partners by revenue this quarter?       | `metrics_sales_order`          | `MEASURE(total_revenue)` by `dealer_name`                        | Dealer as sales partner          |
| C13 | Do campaign conversions last month actually show up as delivered sales?                      | Cross                          | Conversions on campaigns; delivered on sales orders — do not mix | Disjoint terms                   |




### 4. Strategy & Competitive Advantage


| #   | Question                                                                                          | Domain / view               | Expected binding                                                                 | Pass notes            |
| --- | ------------------------------------------------------------------------------------------------- | --------------------------- | -------------------------------------------------------------------------------- | --------------------- |
| C14 | Which models should we double down on — revenue this quarter plus plant OEE for those models?     | Cross: sales + production   | Separate queries: `total_revenue` by `model_name`; `average_oee` by `model_name` | No cross-domain JOIN  |
| C15 | Where is our commercial edge: top channels by weighted ROAS versus top models by revenue?         | Cross: marketing + sales    | `weighted_roas` by `channel_name`; `total_revenue` by `model_name`               | Separate queries      |
| C16 | How is the business doing this quarter across revenue, plant performance, and stock availability? | Cross: all five `metrics_*` | Separate queries; no cross-domain JOIN                                           | Same intent as PRD #1 |
| C17 | Are we winning on quality in the supply base — supplier quality scores and PPM this quarter?      | `metrics_supplier_quality`  | `MEASURE(average_quality_score)`, `MEASURE(ppm)` by `supplier_name`              |                       |
|     |                                                                                                   |                             |                                                                                  |                       |
|     |                                                                                                   |                             |                                                                                  |                       |
|     |                                                                                                   |                             |                                                                                  |                       |
|     |                                                                                                   |                             |                                                                                  |                       |




### 5. People & Execution

No HR / headcount / attrition views. Execution = plants, shifts, lines, dealers, and campaign ops.


| #   | Question                                                                                      | Domain / view                  | Expected binding                                                     | Pass notes                       |
| --- | --------------------------------------------------------------------------------------------- | ------------------------------ | -------------------------------------------------------------------- | -------------------------------- |
| C18 | Which plants are not executing — OEE below 70% last week?                                     | `metrics_production_execution` | `oee_below_70` or `OEE_PCT < 70` by `plant_name`                     | Threshold 70 on 0–100 scale      |
| C19 | Where is the shop floor losing time — downtime by plant, line, and shift this week?           | `metrics_production_execution` | `MEASURE(total_downtime)` by `plant_name`, `line_name`, `shift_code` | No `dim_shift`                   |
| C20 | Which production lines are the execution risk this month (lowest OEE, highest downtime)?      | `metrics_production_execution` | `average_oee`, `total_downtime` by `line_name`                       |                                  |
| C21 | Are our go-to-market teams executing — campaign ROAS and cost per lead by channel last month? | `metrics_campaign_performance` | `weighted_roas`, `cost_per_lead` by `channel_name`                   | Weighted, not AVG                |
| C22 | Which dealers are under-executing on delivered revenue this quarter?                          | `metrics_sales_order`          | `delivered_order_revenue` by `dealer_name`                           | Bottom of ranking is a valid ask |




### 6. Risk & Compliance

No legal / SOX / safety incident views. Risk = stockout, quality PPM, COPQ, and chronic low OEE.


| #   | Question                                                                                            | Domain / view                  | Expected binding                                                                  | Pass notes                     |
| --- | --------------------------------------------------------------------------------------------------- | ------------------------------ | --------------------------------------------------------------------------------- | ------------------------------ |
| C23 | What is at operational risk right now — parts at high stockout on the current snapshot?             | `metrics_inventory_snapshot`   | `high_stockout` + `is_current_snapshot`                                           | Never SUM on-hand across dates |
| C24 | Which warehouses and parts have the thinnest days of supply today?                                  | `metrics_inventory_snapshot`   | `average_days_of_supply` + `is_current_snapshot` by `warehouse_name`, `part_name` | Point-in-time only             |
| C25 | Which suppliers are a quality / compliance risk this quarter (PPM and COPQ)?                        | `metrics_supplier_quality`     | `MEASURE(ppm)`, `MEASURE(copq)` by `supplier_name`                                | Lower PPM is better            |
| C26 | Do we have plants persistently below the 70% OEE operating standard this month?                     | `metrics_production_execution` | `oee_below_70` by `plant_name` for the month                                      | Certified threshold            |
| C27 | If someone asks for total inventory value across all dates, what should we do?                      | `metrics_inventory_snapshot`   | Refuse / correct: current snapshot only                                           | Snapshot summing trap          |
| C28 | Give me the board risk snapshot: high stockout now, OEE below 70% this week, and COPQ this quarter. | Cross                          | Three separate queries; no JOIN                                                   | Exec pack, certified KPIs only |




## Certified smoke (must not drift)

Run after Genie deploy (SQL warehouse and/or Genie UI):

1. OEE below 70% → threshold **70** on 0–100 scale (`oee_below_70`)
2. High stockout → current snapshot only
3. Revenue → `MEASURE(total_revenue)` on `metrics_sales_order`
4. ROAS → `MEASURE(weighted_roas)` (not AVG)
5. Conversions → marketing measure only (not DELIVERED)


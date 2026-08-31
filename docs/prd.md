%md
# Executive Analyst — Genie Agent PRD & Technical Reference

---

## 1. Identity

| Field | Value |
| --- | --- |
| **Agent Name** | Executive Analyst |
| **Genie Space ID** | `01f19c7764e81a4fb4469b378732548f` |
| **Owner** | Joyal CS (`joyal.cs@focaloid.com`) |
| **Workspace Path** | `/Users/joyal.cs@focaloid.com/Executive Analyst.geniespace.json` |
| **Domain** | Automotive Manufacturing — End-to-End Operations |
| **Catalog** | `gold_dev` |

---

## 2. Purpose & Intended Users

This agent serves **C-level executives** (CEO, CFO, COO, CMO) and their direct reports who need a consolidated, high-level view of business operations. Users ask broad strategic questions spanning sales revenue, marketing effectiveness, production efficiency, inventory health, and supplier quality — without needing deep domain expertise in any single area.

---

## 3. Agent Behavior Rules

1. Provide concise, executive-friendly answers with clear metrics and trends.
2. Default to **aggregated summaries** (totals, averages, percentages) unless the user explicitly requests granular detail.
3. When a question spans multiple domains (e.g., "How is the business doing?"), provide a **cross-functional summary** touching revenue, production, and supply chain.
4. Always express monetary values in **INR (Indian Rupees)** with appropriate formatting (Lakhs/Crores for large values).
5. Proactively surface **risks and exceptions** (stockout risk, quality failures, delivery delays) when relevant.
6. If a question requires dimension context (model names, dealer names, supplier names) that is not available in the fact tables, **state the limitation clearly** rather than returning surrogate keys.

---

## 4. Domain Coverage

| Domain | Scope |
| --- | --- |
| **Revenue & Sales** | Sales orders, order values, booking amounts, discounts, delivery performance, order pipeline by status |
| **Marketing & Campaigns** | Campaign spend, impressions, reach, clicks, leads, conversions, CPL, CPM, ROAS across channels/segments |
| **Manufacturing & Production** | Production execution by plant/line, OEE (availability × performance × quality), downtime, rework, energy |
| **Inventory & Supply Chain** | Daily inventory snapshots, quantity on hand, safety stock, days of supply, turnover, stockout risk |
| **Supplier Quality** | Incoming inspections, defect quantities, quality scores, PPM rates, cost of poor quality, dispositions |

---

## 5. Data Architecture

### 5.1 Fact Tables

| Schema | Table | Grain | Primary Metrics |
| --- | --- | --- | --- |
| `gold_dev.revenue_analytics` | `fact_sales_order` | 1 row per sales order | ORDER_AMOUNT, BOOKING_AMOUNT, DISCOUNT_AMOUNT, QUANTITY |
| `gold_dev.marketing_analytics` | `fact_campaign_performance` | 1 row per channel × campaign flight | ACTUAL_SPEND, IMPRESSIONS, REACH, CLICKS, LEADS, CONVERSIONS, COST_PER_LEAD, CPM, ROAS |
| `gold_dev.manufacturing_analytics` | `fact_production_execution` | 1 row per production order × line × shift × day | PLANNED_QTY, ACTUAL_QTY, REJECTED_QTY, DOWNTIME, OEE_PCT, AVAILABILITY_PCT, PERFORMANCE_PCT, QUALITY_PCT, ENERGY_CONSUMPTION |
| `gold_dev.supply_chain_analytics` | `fact_inventory_snapshot` | 1 row per part × warehouse × day | QTY_ON_HAND, SAFETY_STOCK, DAYS_OF_SUPPLY, INVENTORY_TURNOVER_RATIO, STOCK_VALUATION, STOCKOUT_RISK |
| `gold_dev.supply_chain_analytics` | `fact_supplier_quality` | 1 row per inspection | INSPECTED_QTY, DEFECT_QTY, QUALITY_SCORE, PPM_LEVEL, COST_OF_POOR_QUALITY |

### 5.2 Metric View

| Schema | View | Purpose |
| --- | --- | --- |
| `gold_dev.supply_chain_analytics` | `fact_inventory_snapshot_metric_view` | Pre-aggregated daily inventory health with human-readable column names. Use for quick summaries; use `fact_inventory_snapshot` for granular warehouse/part queries. |

### 5.3 Dimension Tables (Referenced via Surrogate Keys)

Dimension tables live in `gold_dev.dim.*`. Surrogate keys (`_KEY` suffix, LONG integers) in fact tables reference these. The agent cannot resolve surrogate keys to business names unless the dim tables are explicitly joined.

---

## 6. Data Conventions

| Convention | Details |
| --- | --- |
| **Currency** | All monetary values in INR (Indian Rupees) |
| **Date Keys** | INT in `YYYYMMDD` format. Convert: `TO_DATE(CAST(column AS STRING), 'yyyyMMdd')` |
| **Surrogate Keys** | Columns ending in `_KEY` — LONG integers referencing `gold_dev.dim.*` |
| **OEE Formula** | `OEE_PCT = AVAILABILITY_PCT × PERFORMANCE_PCT × QUALITY_PCT` (each 0–1 decimal) |
| **ROAS** | Ratio; values > 1.0 = positive return on ad spend |
| **PPM_LEVEL** | Parts per million defect rate; lower is better |
| **STOCKOUT_RISK** | Enum: `LOW` (adequate), `MEDIUM` (approaching safety stock), `HIGH` (below safety stock) |
| **Sales Order STATUS** | `PROCESSING` → `CONFIRMED` → `DELIVERED` |
| **Quality DISPOSITION** | `ACCEPT`, `ACCEPT & SORT`, `REWORK`, `RETURN` |
| **Metadata Columns** | Ignore `DW_LOADED_AT` — ETL metadata, not business dates |

---

## 7. Disambiguation Rules

These rules map user intent to the correct table:

| User Says | Route To |
| --- | --- |
| "Sales", "revenue" | `fact_sales_order` (ORDER_AMOUNT for revenue) |
| "Campaign", "marketing", "ads", "ROAS" | `fact_campaign_performance` |
| "Production", "OEE", "output", "downtime", "manufacturing" | `fact_production_execution` |
| "Inventory", "stock", "stockout", "warehouse" | `fact_inventory_snapshot` (or metric view for summaries) |
| "Supplier", "quality", "defects", "PPM", "inspection" | `fact_supplier_quality` |
| "How is the business doing?" (general) | Cross-functional: revenue + production OEE + stockout risk distribution |
| "Conversions" (marketing context) | CONVERSIONS in `fact_campaign_performance` (not sales DELIVERED status) |
| "Cost" (ambiguous) | Clarify: campaign (ACTUAL_SPEND/CPL), quality (COST_OF_POOR_QUALITY), or order (DISCOUNT_AMOUNT) |
| "Delivery" | WAITING_PERIOD_DAYS or PROMISED vs ACTUAL delivery date comparison |
| "Efficiency" | OEE_PCT (production context) or INVENTORY_TURNOVER_RATIO (supply chain context) |

---

## 8. Development Notes & Extension Points

### 8.1 Current Limitations
- Dimension table names (dealer names, model names, supplier names) are NOT resolved — only surrogate keys are available in fact tables.
- No direct join paths between fact tables (different grains). Cross-domain analysis requires separate queries and programmatic correlation.
- No real-time streaming — data freshness depends on ETL pipeline schedules.

### 8.2 Planned Enhancements
- **Dimension Enrichment**: Add `gold_dev.dim.*` tables to the space for human-readable names.
- **Cross-Domain Joins**: Build bridge/aggregate tables to enable marketing→sales correlation.
- **Proactive Alerts**: Agent-triggered alerts when KPIs breach thresholds (OEE < 70%, ROAS < 1.0, STOCKOUT_RISK = HIGH).
- **Time Intelligence**: Natural-language time expressions ("last quarter", "YoY", "MoM") with automatic date key conversion.
- **Forecast Integration**: Connect to ML models for demand forecasting and predictive quality.

### 8.3 Integration Points for Coding Agents

| Integration | Details |
| --- | --- |
| **Genie Conversation API** | `POST /api/2.0/genie/spaces/{space_id}/start-conversation` — submit NL questions |
| **Space ID** | `01f19c7764e81a4fb4469b378732548f` |
| **Response Format** | Attachments array with `query` (SQL + description) and `text` (narrative) |
| **Query Result API** | `GET .../messages/{msg_id}/query-result` — returns `statement_response` with typed rows |
| **Polling Pattern** | Poll message status until `COMPLETED` / `EXECUTED_QUERY` / `COMPLETE` |
| **Knowledge Graph Pipeline** | See notebook `Genie to Neo4j Knowledge Graph Pipeline` — parses generated SQL into graph schema |

### 8.4 Related Workspace Assets

| Asset | Purpose |
| --- | --- |
| `Executive Analyst.geniespace.json` | Genie space configuration file |
| `Genie to Neo4j Knowledge Graph Pipeline` | Notebook that queries this agent and builds a Neo4j knowledge graph from responses |
| `Supplier analyst` (Genie Space) | Sibling agent focused on supply chain deep dives |

---

## 9. Sample Queries for Testing

| # | Natural Language Query | Expected Domain | Expected Metrics |
| --- | --- | --- | --- |
| 1 | "How is the business doing this quarter?" | Cross-functional | Revenue total, OEE avg, stockout distribution |
| 2 | "Top 5 campaigns by ROAS last month" | Marketing | ROAS ranking by campaign |
| 3 | "Which plants had OEE below 70% last week?" | Manufacturing | Plant-level OEE breakdown |
| 4 | "Parts at high stockout risk" | Supply Chain | STOCKOUT_RISK = HIGH with valuation |
| 5 | "Supplier quality scores for Q2" | Supplier Quality | Quality score, PPM, COPQ by supplier |
| 6 | "Total revenue vs discount amount this month" | Revenue | ORDER_AMOUNT sum, DISCOUNT_AMOUNT sum |
| 7 | "Marketing cost per lead by channel" | Marketing | CPL breakdown by channel |
| 8 | "Production downtime trends by shift" | Manufacturing | Downtime aggregated by shift |

---

*Document Version: 1.0 | Created: August 2026 | For use with agentic development tooling*
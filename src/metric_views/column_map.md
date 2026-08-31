# Metric view column map (Phase 1 — dim joins enabled)

Confirmed against `gold_dev` via `information_schema.columns` (warehouse `d2533a75c1bd9265`, profile `gold`). Re-run [`discover_dims.sql`](discover_dims.sql) if schemas change.

## Dim tables in `gold_dev.dim`

| Table | Key | Display name column | Used by |
| --- | --- | --- | --- |
| `dim_dealer` | `DEALER_KEY` | `DEALER_NAME` | revenue |
| `dim_vehicle_model` | `MODEL_KEY` | `MODEL_NAME` | revenue, manufacturing |
| `dim_date` | `DATE_KEY` (INT) | `FULL_DATE` (DATE) | all five |
| `dim_campaign` | `CAMPAIGN_KEY` | `CAMPAIGN_NAME` | marketing |
| `dim_channel` | `CHANNEL_KEY` | `CHANNEL_NAME` | marketing |
| `dim_customer_segment` | `SEGMENT_KEY` | `SEGMENT_NAME` | marketing |
| `dim_plant` | `PLANT_KEY` | `PLANT_NAME` | manufacturing |
| `dim_production_line` | `LINE_KEY` | `LINE_NAME` | manufacturing |
| `dim_part` | `PART_KEY` | `PART_NAME` | inventory, supplier quality |
| `dim_warehouse` | `WAREHOUSE_KEY` | `WAREHOUSE_NAME` | inventory |
| `dim_supplier` | `SUPPLIER_KEY` | `SUPPLIER_NAME` | supplier quality |

Also present but **not** joined for Executive Analyst: `dim_customer`, `dim_employee`, `dim_request_status`, `dim_vehicle`.

**No `dim_shift`.** Manufacturing exposes `SHIFT_CODE` (STRING) from the fact as `shift_code`.

## Fact date / surrogate keys (confirmed)

| Fact | Date key (INT YYYYMMDD) | Surrogate keys joined |
| --- | --- | --- |
| `fact_sales_order` | `ORDER_DATE_KEY` | `DEALER_KEY`, `MODEL_KEY` |
| `fact_campaign_performance` | `START_DATE_KEY` (also `END_DATE_KEY`) | `CAMPAIGN_KEY`, `CHANNEL_KEY`, `SEGMENT_KEY` |
| `fact_production_execution` | `EXECUTION_DATE_KEY` | `PLANT_KEY`, `LINE_KEY`, `MODEL_KEY` |
| `fact_inventory_snapshot` | `SNAPSHOT_DATE_KEY` | `PART_KEY`, `WAREHOUSE_KEY` |
| `fact_supplier_quality` | `INSPECTION_DATE_KEY` | `SUPPLIER_KEY`, `PART_KEY` |

Date conversion when not using `dim_date.FULL_DATE`:

```sql
TO_DATE(CAST(<date_key> AS STRING), 'yyyyMMdd')
```

## Confirmed column renames (facts)

| Table | PRD / old name | Actual column |
| --- | --- | --- |
| `fact_production_execution` | `DOWNTIME` | `DOWNTIME_MIN` |
| `fact_production_execution` | `ENERGY_CONSUMPTION` | `ENERGY_CONSUMED_KWH` |
| `fact_inventory_snapshot` | `QTY_ON_HAND` | `QUANTITY_ON_HAND` |
| `fact_inventory_snapshot` | `SAFETY_STOCK` | `SAFETY_STOCK_QTY` |

## Enabled joins per metric view

| Metric view | Joins |
| --- | --- |
| `metrics_sales_order` | `dim_dealer`, `dim_vehicle_model`, `dim_date` on `ORDER_DATE_KEY` |
| `metrics_campaign_performance` | `dim_campaign`, `dim_channel`, `dim_customer_segment`, `dim_date` on `START_DATE_KEY` |
| `metrics_production_execution` | `dim_plant`, `dim_production_line`, `dim_vehicle_model`, `dim_date` on `EXECUTION_DATE_KEY` |
| `metrics_inventory_snapshot` | `dim_part`, `dim_warehouse`, `dim_date` on `SNAPSHOT_DATE_KEY` |
| `metrics_supplier_quality` | `dim_supplier`, `dim_part`, `dim_date` on `INSPECTION_DATE_KEY` |

All joins use `rely.at_most_one_match: true`.

## Inventory current snapshot

`is_current_snapshot` compares `SNAPSHOT_DATE_KEY` to `MAX(SNAPSHOT_DATE_KEY)` over the fact (scalar subquery with catalog concat). Prefer filtering `is_current_snapshot = true` for current stock / stockout. Never SUM on-hand across dates.

## How to re-discover

```bash
# PowerShell / CLI — see discover_dims.sql body, or:
databricks api post /api/2.0/sql/statements --profile gold --json @src/metric_views/_tmp_stmt.json
```

Then update this map and the `metrics_*.sql` join blocks before `./deploy.sh apply-metrics`.

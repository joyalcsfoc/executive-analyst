-- Executive Analyst — inventory metric view
-- Snapshot grain: never SUM on-hand / safety stock / valuation across dates.
-- Dim joins: part, warehouse, date. is_current_snapshot for latest SNAPSHOT_DATE_KEY.

EXECUTE IMMEDIATE
"CREATE OR REPLACE VIEW " || {{catalog}} || ".supply_chain_analytics.metrics_inventory_snapshot
WITH METRICS
LANGUAGE YAML
AS $$
version: 1.1
comment: >
  Executive inventory KPIs. Grain: 1 row per part × warehouse × day (point-in-time snapshot).
  For current inventory or stockout, filter is_current_snapshot = true (latest SNAPSHOT_DATE_KEY).
  Never SUM QUANTITY_ON_HAND, SAFETY_STOCK, or STOCK_VALUATION across multiple snapshot dates.
  Summing across parts/warehouses on a single date is valid. Currency INR.
  Joined dims: part, warehouse, snapshot date (FULL_DATE).
  Does not replace fact_inventory_snapshot_metric_view; this is the governed KPI contract.

source: " || {{catalog}} || ".supply_chain_analytics.fact_inventory_snapshot

joins:
  - name: dim_part
    source: " || {{catalog}} || ".dim.dim_part
    on: source.PART_KEY = dim_part.PART_KEY
    rely:
      at_most_one_match: true
  - name: dim_warehouse
    source: " || {{catalog}} || ".dim.dim_warehouse
    on: source.WAREHOUSE_KEY = dim_warehouse.WAREHOUSE_KEY
    rely:
      at_most_one_match: true
  - name: dim_date
    source: " || {{catalog}} || ".dim.dim_date
    on: source.SNAPSHOT_DATE_KEY = dim_date.DATE_KEY
    rely:
      at_most_one_match: true

fields:
  - expr: source.* EXCEPT (DW_LOADED_AT, STOCKOUT_RISK)
  - name: stockout_risk
    expr: STOCKOUT_RISK
    display_name: Stockout Risk
    comment: Point-in-time risk band. LOW = adequate; MEDIUM = approaching safety stock; HIGH = QUANTITY_ON_HAND below SAFETY_STOCK_QTY.
    synonyms: [stockout, stock out risk, stock risk]
  - name: high_stockout
    expr: CASE WHEN STOCKOUT_RISK = 'HIGH' THEN true ELSE false END
    display_name: High Stockout Risk
    comment: True when STOCKOUT_RISK = HIGH (on-hand below safety stock).
    synonyms: [high stockout, stockout risk high, parts at high stockout risk]
  - name: restock_candidate
    expr: CASE WHEN STOCKOUT_RISK IN ('HIGH', 'MEDIUM') THEN true ELSE false END
    display_name: Restock Candidate
    comment: HIGH is primary restock; MEDIUM is watchlist. Use on latest snapshot date only.
    synonyms: [restock, replenishment, reorder candidates]
  - name: is_current_snapshot
    expr: source.SNAPSHOT_DATE_KEY = (SELECT MAX(SNAPSHOT_DATE_KEY) FROM " || {{catalog}} || ".supply_chain_analytics.fact_inventory_snapshot)
    display_name: Is Current Snapshot
    comment: True for rows on the latest SNAPSHOT_DATE_KEY. Filter true for current stock / stockout / restock.
    synonyms: [current inventory, latest snapshot, current stock]
  - name: part_name
    expr: dim_part.PART_NAME
    display_name: Part Name
    comment: Part name from dim_part.
    synonyms: [part, part name, SKU name, component]
  - name: warehouse_name
    expr: dim_warehouse.WAREHOUSE_NAME
    display_name: Warehouse Name
    comment: Warehouse from dim_warehouse.
    synonyms: [warehouse, warehouse name, DC]
  - name: snapshot_date
    expr: dim_date.FULL_DATE
    display_name: Snapshot Date
    comment: Inventory snapshot date from dim_date (joined on SNAPSHOT_DATE_KEY).
    synonyms: [inventory date, stock date]

measures:
  - name: total_qty_on_hand
    expr: SUM(QUANTITY_ON_HAND)
    display_name: Total Qty On Hand
    comment: Sum of on-hand qty (column QUANTITY_ON_HAND). Valid across parts/warehouses on one snapshot date only. Never sum across dates.
    synonyms: [on hand, stock on hand, available qty, QTY_ON_HAND]
  - name: total_safety_stock
    expr: SUM(SAFETY_STOCK_QTY)
    display_name: Total Safety Stock
    comment: Sum of safety-stock targets (column SAFETY_STOCK_QTY). Single snapshot date only. Never sum across dates.
    synonyms: [min stock, buffer stock, SAFETY_STOCK]
  - name: total_stock_valuation
    expr: SUM(STOCK_VALUATION)
    display_name: Total Stock Valuation
    comment: Inventory value in INR. Single snapshot date only. Never sum across dates.
    synonyms: [inventory value, stock value, inventory valuation]
  - name: average_days_of_supply
    expr: AVG(DAYS_OF_SUPPLY)
    display_name: Average Days Of Supply
    comment: Point-in-time DOS. Do not treat as cumulative across dates.
    synonyms: [DOS, cover days, stock cover]
  - name: average_turnover
    expr: AVG(INVENTORY_TURNOVER_RATIO)
    display_name: Average Inventory Turnover
    comment: Point-in-time turnover. Do not average blindly across mixed dates.
    synonyms: [turnover, stock turns, inventory turns]
  - name: high_stockout_row_count
    expr: COUNT(1) FILTER (WHERE STOCKOUT_RISK = 'HIGH')
    display_name: High Stockout Row Count
    comment: Count of snapshot rows with STOCKOUT_RISK = HIGH. Filter to latest date for current status.
    synonyms: [high stockout count]
$$";

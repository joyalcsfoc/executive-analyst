-- Executive Analyst — manufacturing metric view
-- OEE_PCT and components are stored as 0–100 percent values (confirmed gold_dev).
-- "Below 70%" means OEE_PCT < 70. Dim joins: plant, production_line, vehicle_model, date.
-- No dim_shift — use SHIFT_CODE.

EXECUTE IMMEDIATE
"CREATE OR REPLACE VIEW " || {{catalog}} || ".manufacturing_analytics.metrics_production_execution
WITH METRICS
LANGUAGE YAML
AS $$
version: 1.1
comment: >
  Executive manufacturing KPIs. Grain: 1 row per production order × line × shift × day.
  OEE and components (availability, performance, quality) are stored as 0–100 percent values.
  Below 70% means OEE_PCT < 70. Joined dims: plant, production line, vehicle model, execution date.
  Shift is SHIFT_CODE on the fact (no dim_shift table).

source: " || {{catalog}} || ".manufacturing_analytics.fact_production_execution

joins:
  - name: dim_plant
    source: " || {{catalog}} || ".dim.dim_plant
    on: source.PLANT_KEY = dim_plant.PLANT_KEY
    rely:
      at_most_one_match: true
  - name: dim_production_line
    source: " || {{catalog}} || ".dim.dim_production_line
    on: source.LINE_KEY = dim_production_line.LINE_KEY
    rely:
      at_most_one_match: true
  - name: dim_vehicle_model
    source: " || {{catalog}} || ".dim.dim_vehicle_model
    on: source.MODEL_KEY = dim_vehicle_model.MODEL_KEY
    rely:
      at_most_one_match: true
  - name: dim_date
    source: " || {{catalog}} || ".dim.dim_date
    on: source.EXECUTION_DATE_KEY = dim_date.DATE_KEY
    rely:
      at_most_one_match: true

fields:
  - expr: source.* EXCEPT (DW_LOADED_AT, SHIFT_CODE)
  - name: oee_below_70
    expr: CASE WHEN OEE_PCT < 70 THEN true ELSE false END
    display_name: OEE Below 70 Percent
    comment: True when OEE_PCT < 70 (stored as 0–100 percent, not 0–1).
    synonyms: [low OEE, OEE under 70 percent, plants below 70% OEE]
  - name: plant_name
    expr: dim_plant.PLANT_NAME
    display_name: Plant Name
    comment: Manufacturing plant from dim_plant.
    synonyms: [plant, factory, plant name]
  - name: line_name
    expr: dim_production_line.LINE_NAME
    display_name: Line Name
    comment: Production line from dim_production_line.
    synonyms: [line, production line, assembly line]
  - name: model_name
    expr: dim_vehicle_model.MODEL_NAME
    display_name: Model Name
    comment: Vehicle model produced, from dim_vehicle_model.
    synonyms: [model, vehicle model]
  - name: shift_code
    expr: SHIFT_CODE
    display_name: Shift Code
    comment: Shift code on the fact (A/B/C etc). No dim_shift table exists.
    synonyms: [shift, production shift]
  - name: execution_date
    expr: dim_date.FULL_DATE
    display_name: Execution Date
    comment: Production execution date from dim_date (joined on EXECUTION_DATE_KEY).
    synonyms: [production date, run date]

measures:
  - name: average_oee
    expr: AVG(OEE_PCT)
    display_name: Average OEE
    comment: Overall equipment effectiveness as 0–100 percent. Below 70% means OEE_PCT < 70.
    synonyms: [OEE, average OEE, overall equipment effectiveness, efficiency]
  - name: average_availability
    expr: AVG(AVAILABILITY_PCT)
    display_name: Average Availability
    comment: OEE availability as 0–100 percent.
    synonyms: [availability]
  - name: average_performance
    expr: AVG(PERFORMANCE_PCT)
    display_name: Average Performance
    comment: OEE performance as 0–100 percent.
    synonyms: [performance]
  - name: average_quality
    expr: AVG(QUALITY_PCT)
    display_name: Average Quality Rate
    comment: OEE quality as 0–100 percent.
    synonyms: [quality rate]
  - name: total_downtime
    expr: SUM(DOWNTIME_MIN)
    display_name: Total Downtime
    comment: Sum of production downtime duration in minutes (column DOWNTIME_MIN).
    synonyms: [downtime hours, line downtime, stoppage, downtime, DOWNTIME]
  - name: total_planned_qty
    expr: SUM(PLANNED_QTY)
    display_name: Total Planned Quantity
    synonyms: [plan qty, target qty]
  - name: total_actual_qty
    expr: SUM(ACTUAL_QTY)
    display_name: Total Actual Quantity
    synonyms: [output, produced qty, actual output]
  - name: total_rejected_qty
    expr: SUM(REJECTED_QTY)
    display_name: Total Rejected Quantity
    synonyms: [rejects, scrap, rework qty]
  - name: total_energy
    expr: SUM(ENERGY_CONSUMED_KWH)
    display_name: Total Energy Consumption
    comment: Sum of energy consumed in kWh (column ENERGY_CONSUMED_KWH).
    synonyms: [energy use, power consumption, energy consumption, ENERGY_CONSUMPTION]
  - name: low_oee_row_count
    expr: COUNT(1) FILTER (WHERE OEE_PCT < 70)
    display_name: Rows With OEE Below 70 Percent
    comment: Count of production rows where OEE_PCT < 70.
    synonyms: [low OEE count]
$$";

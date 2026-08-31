-- Executive Analyst — supplier quality metric view
-- Do not SUM(PPM_LEVEL); roll up as SUM(DEFECT_QTY)/SUM(INSPECTED_QTY)*1e6.
-- Dim joins: supplier, part, date — see column_map.md.

EXECUTE IMMEDIATE
"CREATE OR REPLACE VIEW " || {{catalog}} || ".supply_chain_analytics.metrics_supplier_quality
WITH METRICS
LANGUAGE YAML
AS $$
version: 1.1
comment: >
  Executive supplier quality KPIs. Grain: 1 row per inspection.
  PPM lower is better. Do not SUM PPM_LEVEL or QUALITY_SCORE.
  Joined dims: supplier, part, inspection date (FULL_DATE).

source: " || {{catalog}} || ".supply_chain_analytics.fact_supplier_quality

joins:
  - name: dim_supplier
    source: " || {{catalog}} || ".dim.dim_supplier
    on: source.SUPPLIER_KEY = dim_supplier.SUPPLIER_KEY
    rely:
      at_most_one_match: true
  - name: dim_part
    source: " || {{catalog}} || ".dim.dim_part
    on: source.PART_KEY = dim_part.PART_KEY
    rely:
      at_most_one_match: true
  - name: dim_date
    source: " || {{catalog}} || ".dim.dim_date
    on: source.INSPECTION_DATE_KEY = dim_date.DATE_KEY
    rely:
      at_most_one_match: true

fields:
  - expr: source.* EXCEPT (DW_LOADED_AT)
  - name: supplier_name
    expr: dim_supplier.SUPPLIER_NAME
    display_name: Supplier Name
    comment: Supplier from dim_supplier.
    synonyms: [supplier, vendor, supplier name]
  - name: part_name
    expr: dim_part.PART_NAME
    display_name: Part Name
    comment: Inspected part from dim_part.
    synonyms: [part, part name, component]
  - name: inspection_date
    expr: dim_date.FULL_DATE
    display_name: Inspection Date
    comment: Inspection date from dim_date (joined on INSPECTION_DATE_KEY).
    synonyms: [quality date, inspection day]

measures:
  - name: copq
    expr: SUM(COST_OF_POOR_QUALITY)
    display_name: Cost Of Poor Quality
    comment: Cost of poor quality in INR.
    synonyms: [COPQ, quality cost, poor quality cost, cost of poor quality]
  - name: total_inspected_qty
    expr: SUM(INSPECTED_QTY)
    display_name: Total Inspected Quantity
    synonyms: [inspection qty, sample size]
  - name: total_defect_qty
    expr: SUM(DEFECT_QTY)
    display_name: Total Defect Quantity
    synonyms: [defects, rejected qty]
  - name: ppm
    expr: SUM(DEFECT_QTY) / NULLIF(SUM(INSPECTED_QTY), 0) * 1000000
    display_name: PPM Defect Rate
    comment: Parts-per-million defect rate. Lower is better. Never SUM(PPM_LEVEL).
    synonyms: [PPM, defect ppm, parts per million, PPM_LEVEL]
  - name: average_quality_score
    expr: AVG(QUALITY_SCORE)
    display_name: Average Quality Score
    comment: Do not SUM scores; AVG only at equal grain.
    synonyms: [supplier score, quality rating, quality score]
  - name: inspection_count
    expr: COUNT(1)
    display_name: Inspection Count
    synonyms: [inspections, inspection count]
$$";

-- Executive Analyst — revenue metric view
-- Job param {{catalog}} expands to a quoted string (e.g. 'gold_dev'); concatenate into DDL.
-- Dim joins: dim_dealer, dim_vehicle_model, dim_date — see column_map.md

EXECUTE IMMEDIATE
"CREATE OR REPLACE VIEW " || {{catalog}} || ".revenue_analytics.metrics_sales_order
WITH METRICS
LANGUAGE YAML
AS $$
version: 1.1
comment: >
  Executive revenue KPIs. Grain: 1 row per sales order.
  Default revenue is ORDER_AMOUNT (not BOOKING_AMOUNT). Amount measures are INR;
  discount_percent is a 0-100 percent and must not be formatted as currency.
  Joined dims: dealer (DEALER_NAME), vehicle model (MODEL_NAME), order date (FULL_DATE).

source: " || {{catalog}} || ".revenue_analytics.fact_sales_order

joins:
  - name: dim_dealer
    source: " || {{catalog}} || ".dim.dim_dealer
    on: source.DEALER_KEY = dim_dealer.DEALER_KEY
    rely:
      at_most_one_match: true
  - name: dim_vehicle_model
    source: " || {{catalog}} || ".dim.dim_vehicle_model
    on: source.MODEL_KEY = dim_vehicle_model.MODEL_KEY
    rely:
      at_most_one_match: true
  - name: dim_date
    source: " || {{catalog}} || ".dim.dim_date
    on: source.ORDER_DATE_KEY = dim_date.DATE_KEY
    rely:
      at_most_one_match: true

fields:
  - expr: source.* EXCEPT (DW_LOADED_AT, STATUS)
  - name: order_status
    expr: STATUS
    display_name: Order Status
    comment: Pipeline status. Sequence PROCESSING → CONFIRMED → DELIVERED.
    synonyms: [order status, pipeline status, status]
  - name: dealer_name
    expr: dim_dealer.DEALER_NAME
    display_name: Dealer Name
    comment: Human-readable dealer from dim_dealer.
    synonyms: [dealer, dealer name, dealership]
  - name: model_name
    expr: dim_vehicle_model.MODEL_NAME
    display_name: Model Name
    comment: Vehicle model name from dim_vehicle_model.
    synonyms: [model, vehicle model, car model]
  - name: order_date
    expr: dim_date.FULL_DATE
    display_name: Order Date
    comment: Calendar order date from dim_date (joined on ORDER_DATE_KEY).
    synonyms: [order date, sales date]

measures:
  - name: total_revenue
    expr: SUM(ORDER_AMOUNT)
    display_name: Total Revenue
    comment: Default revenue metric. INR. Do not substitute BOOKING_AMOUNT unless the user asks for bookings.
    synonyms: [revenue, sales, total sales, order value]
  - name: total_bookings
    expr: SUM(BOOKING_AMOUNT)
    display_name: Total Bookings
    comment: Booked / pipeline value in INR. Not recognized revenue.
    synonyms: [bookings, booking value, pipeline value]
  - name: total_discount
    expr: SUM(DISCOUNT_AMOUNT)
    display_name: Total Discount
    comment: Discount given on orders, INR.
    synonyms: [discount, discount amount, markdowns]
  - name: discount_percent
    expr: 100 * SUM(DISCOUNT_AMOUNT) / NULLIF(SUM(ORDER_AMOUNT), 0)
    display_name: Discount Percent
    comment: >
      Discount as a share of revenue, expressed 0-100 percent. Unit is percent, not INR —
      never format with a currency symbol. Never AVG per-order ratios.
    synonyms: [discount percent, discount rate, discount as percent of revenue, markdown rate]
  - name: total_quantity
    expr: SUM(QUANTITY)
    display_name: Total Quantity
    comment: Units on sales orders.
    synonyms: [units, order qty, volume]
  - name: delivered_order_revenue
    expr: SUM(ORDER_AMOUNT) FILTER (WHERE STATUS = 'DELIVERED')
    display_name: Delivered Order Revenue
    comment: Revenue for DELIVERED orders only. INR.
    synonyms: [delivered revenue, fulfilled revenue]
$$";

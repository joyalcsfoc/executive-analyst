-- Executive Analyst — marketing metric view
-- Job param {{catalog}} expands to a quoted string; concatenate into DDL.
-- Never AVG(ROAS) or AVG(COST_PER_LEAD). Dim joins: campaign, channel, segment, date — see column_map.md.

EXECUTE IMMEDIATE
"CREATE OR REPLACE VIEW " || {{catalog}} || ".marketing_analytics.metrics_campaign_performance
WITH METRICS
LANGUAGE YAML
AS $$
version: 1.1
comment: >
  Executive marketing KPIs. Grain: 1 row per channel × campaign flight.
  Use weighted ROAS and rolled-up CPL; never AVG precomputed ratios. Currency INR.
  Joined dims: campaign, channel, customer segment, flight start date (FULL_DATE on START_DATE_KEY).

source: " || {{catalog}} || ".marketing_analytics.fact_campaign_performance

joins:
  - name: dim_campaign
    source: " || {{catalog}} || ".dim.dim_campaign
    on: source.CAMPAIGN_KEY = dim_campaign.CAMPAIGN_KEY
    rely:
      at_most_one_match: true
  - name: dim_channel
    source: " || {{catalog}} || ".dim.dim_channel
    on: source.CHANNEL_KEY = dim_channel.CHANNEL_KEY
    rely:
      at_most_one_match: true
  - name: dim_customer_segment
    source: " || {{catalog}} || ".dim.dim_customer_segment
    on: source.SEGMENT_KEY = dim_customer_segment.SEGMENT_KEY
    rely:
      at_most_one_match: true
  - name: dim_date
    source: " || {{catalog}} || ".dim.dim_date
    on: source.START_DATE_KEY = dim_date.DATE_KEY
    rely:
      at_most_one_match: true

fields:
  - expr: source.* EXCEPT (DW_LOADED_AT, COST_PER_LEAD)
  - name: campaign_name
    expr: dim_campaign.CAMPAIGN_NAME
    display_name: Campaign Name
    comment: Campaign name from dim_campaign.
    synonyms: [campaign, campaign name, ad campaign]
  - name: channel_name
    expr: dim_channel.CHANNEL_NAME
    display_name: Channel Name
    comment: Marketing channel from dim_channel.
    synonyms: [channel, media channel, ad channel]
  - name: segment_name
    expr: dim_customer_segment.SEGMENT_NAME
    display_name: Segment Name
    comment: Customer segment from dim_customer_segment.
    synonyms: [segment, customer segment, audience]
  - name: flight_start_date
    expr: dim_date.FULL_DATE
    display_name: Flight Start Date
    comment: Campaign flight start date from dim_date (joined on START_DATE_KEY).
    synonyms: [start date, flight date, campaign date]

measures:
  - name: total_spend
    expr: SUM(ACTUAL_SPEND)
    display_name: Total Ad Spend
    comment: Actual campaign spend in INR.
    synonyms: [ad spend, media spend, campaign cost, marketing spend]
  - name: total_impressions
    expr: SUM(IMPRESSIONS)
    display_name: Total Impressions
    synonyms: [ad impressions, views]
  - name: total_clicks
    expr: SUM(CLICKS)
    display_name: Total Clicks
    synonyms: [ad clicks]
  - name: total_leads
    expr: SUM(LEADS)
    display_name: Total Leads
    synonyms: [marketing leads]
  - name: total_conversions
    expr: SUM(CONVERSIONS)
    display_name: Total Conversions
    comment: Marketing conversions. Not the same as sales-order DELIVERED status.
    synonyms: [campaign conversions, marketing conversions]
  - name: weighted_roas
    expr: SUM(ROAS * ACTUAL_SPEND) / NULLIF(SUM(ACTUAL_SPEND), 0)
    display_name: Weighted ROAS
    comment: Spend-weighted return on ad spend. Values > 1.0 are a positive return. Never AVG(ROAS).
    synonyms: [ROAS, return on ad spend, return on ads]
  - name: cost_per_lead
    expr: SUM(ACTUAL_SPEND) / NULLIF(SUM(LEADS), 0)
    display_name: Cost Per Lead
    comment: INR per lead. Never AVG(COST_PER_LEAD).
    synonyms: [CPL, cost per lead, marketing cost per lead]
$$";

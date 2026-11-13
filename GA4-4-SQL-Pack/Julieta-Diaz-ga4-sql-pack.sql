-- =====================================================================
-- GA4-4: SQL Pack (Individual) | Milestone 4
-- Author:  Julieta Diaz
-- Dataset: bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*
--          (GA4 export for the Google Merchandise Store, 2020-11-01 to 2021-01-31)
--          Used as a stand-in until the CPP Farm Store GA4 export is connected.
-- Focus:   AO3, paid vs. organic search and traffic-to-purchase conversion
-- Scope:   every query filters _TABLE_SUFFIX to a fixed window to limit cost
-- =====================================================================


-- ---------------------------------------------------------------------
-- Q1 | Filtering & scoping
-- Purchase transactions in one week (Dec 14-20, 2020), largest first.
-- ---------------------------------------------------------------------
SELECT
  event_date,
  ecommerce.transaction_id,
  user_pseudo_id,
  ecommerce.total_item_quantity,
  ecommerce.purchase_revenue_in_usd
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20201214' AND '20201220'   -- one week only
  AND event_name = 'purchase'                            -- purchase events only
ORDER BY ecommerce.purchase_revenue_in_usd DESC
LIMIT 25;


-- ---------------------------------------------------------------------
-- Q2 | Filtering & scoping + grouping
-- Funnel events in December 2020: events vs. distinct users per step.
-- ---------------------------------------------------------------------
SELECT
  event_name,
  COUNT(*)                                   AS events,  -- every event row
  COUNT(DISTINCT user_pseudo_id)             AS users,   -- unique browsers/devices
  ROUND(COUNT(*) / COUNT(DISTINCT user_pseudo_id), 2) AS events_per_user
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20201201' AND '20201231'
  AND event_name IN ('session_start', 'view_item', 'add_to_cart',
                     'begin_checkout', 'purchase')
GROUP BY event_name
ORDER BY users DESC;


-- ---------------------------------------------------------------------
-- Q3 | Grouping & aggregation (COUNT DISTINCT, SUM)
-- Revenue, transactions, and average order value by first-user medium.
-- ---------------------------------------------------------------------
SELECT
  traffic_source.medium                                  AS first_user_medium,
  COUNT(DISTINCT user_pseudo_id)                         AS purchasers,
  COUNT(DISTINCT ecommerce.transaction_id)               AS transactions,
  ROUND(SUM(ecommerce.purchase_revenue_in_usd), 2)       AS revenue_usd,
  ROUND(SAFE_DIVIDE(SUM(ecommerce.purchase_revenue_in_usd),
                    COUNT(DISTINCT ecommerce.transaction_id)), 2) AS avg_order_value_usd
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20201201' AND '20201231'
  AND event_name = 'purchase'
GROUP BY first_user_medium
ORDER BY revenue_usd DESC;


-- ---------------------------------------------------------------------
-- Q4 | UNNEST event_params (string_value)
-- Top 10 pages by page views, Dec 1-7, 2020 (query strings removed).
-- ---------------------------------------------------------------------
SELECT
  REGEXP_REPLACE(
    (SELECT value.string_value              -- page_location is a STRING
     FROM UNNEST(event_params)
     WHERE key = 'page_location'),
    r'\?.*$', '')                           -- strip ?utm=... so URLs group together
                                             AS page_url,
  COUNT(*)                                   AS page_views,
  COUNT(DISTINCT user_pseudo_id)             AS users
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20201201' AND '20201207'
  AND event_name = 'page_view'
GROUP BY page_url
ORDER BY page_views DESC
LIMIT 10;


-- ---------------------------------------------------------------------
-- Q5 | UNNEST (int_value) + CTE
-- Build sessions from ga_session_id, then summarize by day (Dec 1-14).
-- ---------------------------------------------------------------------
WITH session_events AS (
  SELECT
    user_pseudo_id,
    event_date,
    (SELECT value.int_value FROM UNNEST(event_params)
     WHERE key = 'ga_session_id')           AS session_id,      -- INT
    (SELECT value.int_value FROM UNNEST(event_params)
     WHERE key = 'engagement_time_msec')    AS engagement_msec  -- INT
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201201' AND '20201214'
),
sessions AS (
  SELECT
    user_pseudo_id,
    session_id,
    MIN(event_date)                          AS session_date,
    SUM(IFNULL(engagement_msec, 0)) / 1000   AS engaged_seconds
  FROM session_events
  WHERE session_id IS NOT NULL
  GROUP BY user_pseudo_id, session_id        -- session = user + session id
)
SELECT
  session_date,
  COUNT(*)                                   AS sessions,
  ROUND(AVG(engaged_seconds), 1)             AS avg_engaged_seconds,
  ROUND(SAFE_DIVIDE(COUNTIF(engaged_seconds >= 10), COUNT(*)) * 100, 1)
                                             AS pct_sessions_10s_plus
FROM sessions
GROUP BY session_date
ORDER BY session_date;


-- ---------------------------------------------------------------------
-- Q6 | UNNEST + JOIN
-- Page views joined to scroll events by page title: scroll rate per page.
-- ---------------------------------------------------------------------
WITH page_views AS (
  SELECT
    (SELECT value.string_value FROM UNNEST(event_params)
     WHERE key = 'page_title')               AS page_title,
    COUNT(*)                                 AS views
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201201' AND '20201207'
    AND event_name = 'page_view'
  GROUP BY page_title
),
scrolls AS (
  SELECT
    (SELECT value.string_value FROM UNNEST(event_params)
     WHERE key = 'page_title')               AS page_title,
    COUNT(*)                                 AS scrolls
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201201' AND '20201207'
    AND event_name = 'scroll'
  GROUP BY page_title
)
SELECT
  v.page_title,
  v.views,
  IFNULL(s.scrolls, 0)                       AS scrolls,
  ROUND(SAFE_DIVIDE(IFNULL(s.scrolls, 0), v.views) * 100, 1) AS scroll_rate_pct
FROM page_views AS v
LEFT JOIN scrolls AS s                        -- keep pages with no scrolls
  ON v.page_title = s.page_title
WHERE v.views >= 500                          -- ignore low-traffic pages
ORDER BY v.views DESC
LIMIT 15;


-- ---------------------------------------------------------------------
-- Q7 | Multiple CTEs: user-level funnel by first-user medium (AO3)
-- ---------------------------------------------------------------------
WITH user_steps AS (
  SELECT
    user_pseudo_id,
    ANY_VALUE(traffic_source.medium)                   AS medium,
    MAX(IF(event_name = 'view_item', 1, 0))            AS viewed_item,
    MAX(IF(event_name = 'add_to_cart', 1, 0))          AS added_to_cart,
    MAX(IF(event_name = 'begin_checkout', 1, 0))       AS began_checkout,
    MAX(IF(event_name = 'purchase', 1, 0))             AS purchased
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201201' AND '20201231'
  GROUP BY user_pseudo_id                              -- one row per user
),
channel_funnel AS (
  SELECT
    medium,
    COUNT(*)            AS users,
    SUM(viewed_item)    AS view_item_users,
    SUM(added_to_cart)  AS add_to_cart_users,
    SUM(began_checkout) AS checkout_users,
    SUM(purchased)      AS purchasers
  FROM user_steps
  WHERE medium IN ('organic', 'cpc', '(none)', 'referral')
  GROUP BY medium
)
SELECT
  medium,
  users,
  view_item_users,
  add_to_cart_users,
  checkout_users,
  purchasers,
  ROUND(SAFE_DIVIDE(add_to_cart_users, view_item_users) * 100, 1) AS view_to_cart_pct,
  ROUND(SAFE_DIVIDE(purchasers, checkout_users) * 100, 1)        AS checkout_to_purchase_pct,
  ROUND(SAFE_DIVIDE(purchasers, users) * 100, 2)                 AS user_conversion_pct
FROM channel_funnel
ORDER BY users DESC;


-- ---------------------------------------------------------------------
-- Q8 | UNNEST (int) + CTE: conversion by session number
-- Do first sessions or repeat sessions convert better?
-- ---------------------------------------------------------------------
WITH session_base AS (
  SELECT
    user_pseudo_id,
    event_name,
    (SELECT value.int_value FROM UNNEST(event_params)
     WHERE key = 'ga_session_id')            AS session_id,
    (SELECT value.int_value FROM UNNEST(event_params)
     WHERE key = 'ga_session_number')        AS session_number
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201201' AND '20201231'
),
sessions AS (
  SELECT
    user_pseudo_id,
    session_id,
    MAX(session_number)                      AS session_number,
    MAX(IF(event_name = 'purchase', 1, 0))   AS has_purchase
  FROM session_base
  WHERE session_id IS NOT NULL
  GROUP BY user_pseudo_id, session_id
)
SELECT
  CASE
    WHEN session_number IS NULL          THEN '4 Unknown'
    WHEN session_number = 1              THEN '1 First session'
    WHEN session_number BETWEEN 2 AND 3  THEN '2 Sessions 2-3'
    ELSE                                      '3 Session 4+'
  END                                        AS session_group,
  COUNT(*)                                   AS sessions,
  SUM(has_purchase)                          AS purchase_sessions,
  ROUND(SAFE_DIVIDE(SUM(has_purchase), COUNT(*)) * 100, 2) AS session_conversion_pct
FROM sessions
GROUP BY session_group
ORDER BY session_group;

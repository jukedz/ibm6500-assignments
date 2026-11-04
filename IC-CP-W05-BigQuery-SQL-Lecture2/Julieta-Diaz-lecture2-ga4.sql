-- =====================================================================
-- IC/CP-W05: BigQuery SQL Lecture 2 (Intermediate/Advanced BigQuery for GA4)
-- Author: Julieta Diaz
-- Course: IBM 6500, Cal Poly Pomona
-- Dataset: bigquery-public-data.ga4_obfuscated_sample_ecommerce
--          (GA4 export for the Google Merchandise Store, one table per day)
-- Schema reference: https://support.google.com/analytics/answer/7029846
-- =====================================================================


-- =====================================================================
-- 1) CTEs (WITH) to structure logic
-- A CTE creates a named "mini table" that the rest of the query can use.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1a) Total users + new users (November 2020)
-- Step 1 (CTE): one row per user, flagged 1 if they had a first visit.
-- Step 2: count all users and add up the new-user flags.
-- ---------------------------------------------------------------------
WITH UserInfo AS (
  SELECT
    user_pseudo_id,
    MAX(IF(event_name IN ('first_visit', 'first_open'), 1, 0)) AS is_new_user
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20201130'
  GROUP BY user_pseudo_id
)
SELECT
  COUNT(*) AS total_users,
  SUM(is_new_user) AS new_users
FROM UserInfo;


-- =====================================================================
-- 2) Arrays + UNNEST (the GA4 superpower)
-- GA4 stores many fields inside arrays:
--   event_params = key/value pairs (page_location, ga_session_id, ...)
--   items        = products in e-commerce events
-- =====================================================================

-- ---------------------------------------------------------------------
-- 2a) Pattern A: scalar subquery extraction (simple, safe)
-- Pulls ONE parameter out of event_params without adding rows.
-- ---------------------------------------------------------------------
SELECT
  TIMESTAMP_MICROS(event_timestamp) AS event_time,
  (
    SELECT value.string_value
    FROM UNNEST(event_params)
    WHERE key = 'page_location'
    LIMIT 1
  ) AS page_location
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE event_name = 'page_view'
  AND _TABLE_SUFFIX BETWEEN '20201201' AND '20201202'
LIMIT 50;


-- ---------------------------------------------------------------------
-- 2b) Pattern B: flattening (UNNEST in FROM) for item-level analysis
-- Multiplies rows: one purchase event can have many items.
-- Note: UNNEST changes the grain from "one row per event" to
-- "one row per item per event."
-- ---------------------------------------------------------------------
SELECT
  event_date,
  item.item_name,
  COUNT(*) AS item_rows
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` e,
  UNNEST(e.items) AS item
WHERE e.event_name = 'purchase'
  AND _TABLE_SUFFIX BETWEEN '20201201' AND '20201231'
GROUP BY event_date, item.item_name
ORDER BY item_rows DESC
LIMIT 20;


-- =====================================================================
-- 3) STRING_AGG and ARRAY_AGG (combine many values into one row)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 3a) STRING_AGG: list the event types seen each day (Dec 1 to 3, 2020)
-- Note: the lecture handout shows "RDER BY" (missing the O), which
-- causes a syntax error. Fixed to ORDER BY.
-- ---------------------------------------------------------------------
SELECT
  event_date,
  STRING_AGG(DISTINCT event_name, ', ' ORDER BY event_name) AS events_seen
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20201201' AND '20201203'
GROUP BY event_date
ORDER BY event_date;


-- ---------------------------------------------------------------------
-- 3b) ARRAY_AGG Use Case 1: list of items each user added to cart
-- (groups by user_pseudo_id, so this is one list per USER)
-- ---------------------------------------------------------------------
SELECT
  user_pseudo_id,
  ARRAY_AGG(item_name) AS items_added_to_cart
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`,
  UNNEST(items) AS item
WHERE event_name = 'add_to_cart'
  AND _TABLE_SUFFIX BETWEEN '20201201' AND '20201231'
GROUP BY user_pseudo_id
ORDER BY user_pseudo_id
LIMIT 10;


-- ---------------------------------------------------------------------
-- 3c) ARRAY_AGG Use Case 2: session-level "cart summary"
-- CTE pulls each add_to_cart item with its session ID; the main query
-- builds one row per session with up to 10 items stored as STRUCTs.
-- ---------------------------------------------------------------------
WITH add_to_cart AS (
  SELECT
    user_pseudo_id,
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS session_id,
    TIMESTAMP_MICROS(event_timestamp) AS event_timestamp,
    i.item_id,
    i.item_name,
    i.quantity,
    i.price
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`,
    UNNEST(items) AS i
  WHERE event_name = 'add_to_cart'
    AND _TABLE_SUFFIX BETWEEN '20210101' AND '20211231'  -- cost control
)
SELECT
  user_pseudo_id,
  session_id,
  COUNT(*) AS total_add_to_cart_events,                -- added insight
  ARRAY_AGG(
    STRUCT(item_id, item_name, quantity, price, event_timestamp)
    ORDER BY quantity DESC, event_timestamp ASC
    LIMIT 10
  ) AS cart_items
FROM add_to_cart
WHERE session_id IS NOT NULL                            -- filter nulls
GROUP BY user_pseudo_id, session_id;


-- =====================================================================
-- 4) Joins (INNER and LEFT)
-- Combines results from two CTEs that share a key (event_date).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 4a) Daily users LEFT JOIN daily purchases, plus conversion rate
-- ---------------------------------------------------------------------
WITH daily_users AS (
  SELECT
    event_date,
    COUNT(DISTINCT user_pseudo_id) AS users
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201201' AND '20201231'
  GROUP BY event_date
),
daily_purchases AS (
  SELECT
    event_date,
    COUNT(DISTINCT
      (SELECT value.string_value
       FROM UNNEST(event_params)
       WHERE key = 'transaction_id')
    ) AS purchases    -- distinct transactions
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE event_name = 'purchase'
    AND _TABLE_SUFFIX BETWEEN '20201201' AND '20201231'
  GROUP BY event_date
)
SELECT
  u.event_date,
  u.users,
  -- turns "no purchase row (NULL)" into 0 purchases for a daily time series
  IFNULL(p.purchases, 0) AS purchases,
  -- conversion rate: what % of daily users made a purchase
  ROUND(
    IFNULL(p.purchases, 0) / NULLIF(u.users, 0) * 100, 2
  ) AS conversion_rate_pct        -- NULLIF prevents division by zero
FROM daily_users u
LEFT JOIN daily_purchases p
  ON u.event_date = p.event_date
ORDER BY u.event_date;


-- =====================================================================
-- 5) Window functions + QUALIFY
-- Window functions calculate across rows WITHOUT collapsing them.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 5a) Top 3 event types per day (RANK) filtered with QUALIFY
-- ---------------------------------------------------------------------
WITH daily_event_counts AS (
  SELECT
    event_date,
    event_name,
    COUNT(*) AS events
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201201' AND '20201207'
  GROUP BY event_date, event_name
)
SELECT
  event_date,
  event_name,
  events,
  RANK() OVER (PARTITION BY event_date ORDER BY events DESC) AS rnk
FROM daily_event_counts
QUALIFY rnk <= 3
ORDER BY event_date, rnk;


-- ---------------------------------------------------------------------
-- 5b) Rolling 7-day average of daily purchases (December 2020)
-- ---------------------------------------------------------------------
WITH daily_purchases AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS dt,
    COUNT(*) AS purchases
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE event_name = 'purchase'
    AND _TABLE_SUFFIX BETWEEN '20201201' AND '20201231'
  GROUP BY dt
)
SELECT
  dt,
  purchases,
  AVG(purchases) OVER (
    ORDER BY dt
    ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
  ) AS purchases_7d_avg
FROM daily_purchases
ORDER BY dt;


-- =====================================================================
-- 6) Approximate functions (performance-minded)
-- Return "close enough" answers faster on huge datasets.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 6a) Approximate distinct users per event type (December 2020)
-- ---------------------------------------------------------------------
SELECT
  event_name,
  APPROX_COUNT_DISTINCT(user_pseudo_id) AS approx_users
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20201201' AND '20201231'
GROUP BY event_name
ORDER BY approx_users DESC
LIMIT 15;

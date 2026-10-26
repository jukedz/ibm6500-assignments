-- =====================================================================
-- IC/CP-W04: BigQuery SQL Lecture 1 (BigQuery SQL Basics)
-- Author: Julieta Diaz
-- Course: IBM 6500, Cal Poly Pomona
-- Dataset: bigquery-public-data.ga4_obfuscated_sample_ecommerce
--          (GA4 export for the Google Merchandise Store, one table per day)
-- Schema reference: https://support.google.com/analytics/answer/7029846
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1) SELECT / FROM / LIMIT
-- Picks columns from a table and returns a small number of rows.
-- ---------------------------------------------------------------------
SELECT event_date, event_name
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
LIMIT 20;


-- ---------------------------------------------------------------------
-- 2) WHERE filters rows
-- Keeps only rows that match a condition (here, purchase events).
-- ---------------------------------------------------------------------
SELECT event_date, event_name, user_pseudo_id
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE event_name = 'purchase'
LIMIT 50;


-- ---------------------------------------------------------------------
-- 3a) ORDER BY sorts results
-- Sorts purchase events from newest to oldest.
-- ---------------------------------------------------------------------
SELECT event_date, event_timestamp, event_name
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE event_name = 'purchase'
ORDER BY event_timestamp DESC
LIMIT 20;


-- ---------------------------------------------------------------------
-- 3b) Readable timestamps
-- GA4 timestamps are in microseconds; TIMESTAMP_MICROS() converts them.
-- Note: the lecture handout shows "event_timestampDESC" with no space,
-- which causes an error. A space is needed before DESC.
-- ---------------------------------------------------------------------
SELECT TIMESTAMP_MICROS(event_timestamp) AS event_time,
       event_name
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
ORDER BY event_timestamp DESC
LIMIT 10;


-- ---------------------------------------------------------------------
-- 4a) COUNT: total events in a date range (December 2020)
-- ---------------------------------------------------------------------
SELECT COUNT(*) AS event_count
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20201201' AND '20201231';


-- ---------------------------------------------------------------------
-- 4b) COUNT: purchase events in a date range (December 2020)
-- ---------------------------------------------------------------------
SELECT COUNT(*) AS purchase_events
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE event_name = 'purchase'
  AND _TABLE_SUFFIX BETWEEN '20201201' AND '20201231';


-- ---------------------------------------------------------------------
-- 5a) GROUP BY: events by day (one row per day in December 2020)
-- ---------------------------------------------------------------------
SELECT event_date, COUNT(*) AS events
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20201201' AND '20201231'
GROUP BY event_date
ORDER BY event_date;


-- ---------------------------------------------------------------------
-- 5b) GROUP BY: top 15 event types in December 2020
-- ---------------------------------------------------------------------
SELECT event_name, COUNT(*) AS events
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20201201' AND '20201231'
GROUP BY event_name
ORDER BY events DESC
LIMIT 15;


-- ---------------------------------------------------------------------
-- 6) HAVING filters after grouping
-- Keeps only event types with at least 50,000 events in December 2020.
-- ---------------------------------------------------------------------
SELECT event_name, COUNT(*) AS events
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20201201' AND '20201231'
GROUP BY event_name
HAVING COUNT(*) >= 50000
ORDER BY events DESC;


-- ---------------------------------------------------------------------
-- 7) Wildcard tables + _TABLE_SUFFIX
-- events_* covers every daily table; _TABLE_SUFFIX limits the scan to
-- the first week of December 2020 (faster and cheaper).
-- ---------------------------------------------------------------------
SELECT event_date, COUNT(*) AS events
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20201201' AND '20201207'
GROUP BY event_date
ORDER BY event_date;

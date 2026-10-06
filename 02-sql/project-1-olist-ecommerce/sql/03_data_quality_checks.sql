-- =====================================================================
-- 03_data_quality_checks.sql  |  Profile the data BEFORE analysing it
-- Each block starts with "-- Qnn" so run_queries.py can export results.
-- =====================================================================
SET search_path TO olist;

-- Q01 | Row counts per table
-- Technique: UNION ALL
SELECT 'customers' AS table_name, COUNT(*) AS row_count FROM customers
UNION ALL SELECT 'sellers',        COUNT(*) FROM sellers
UNION ALL SELECT 'products',       COUNT(*) FROM products
UNION ALL SELECT 'orders',         COUNT(*) FROM orders
UNION ALL SELECT 'order_items',    COUNT(*) FROM order_items
UNION ALL SELECT 'order_payments', COUNT(*) FROM order_payments
UNION ALL SELECT 'order_reviews',  COUNT(*) FROM order_reviews
UNION ALL SELECT 'category_translation', COUNT(*) FROM category_translation
ORDER BY row_count DESC;

-- Q02 | Order status mix and date range
-- Technique: GROUP BY, window function for percentage of total
SELECT order_status,
       COUNT(*)                                                    AS orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)          AS pct_of_orders,
       MIN(order_purchase_timestamp)::date                         AS first_order,
       MAX(order_purchase_timestamp)::date                         AS last_order
FROM orders
GROUP BY order_status
ORDER BY orders DESC;

-- Q03 | Orders per month (shows the thin start in 2016 and the data cut-off in Sep 2018)
-- Technique: date_trunc
SELECT TO_CHAR(DATE_TRUNC('month', order_purchase_timestamp), 'YYYY-MM') AS purchase_month,
       COUNT(*) AS orders
FROM orders
GROUP BY 1
ORDER BY 1;

-- Q04 | Customer identity: customer_id is per ORDER, customer_unique_id is per PERSON
-- Technique: COUNT DISTINCT
SELECT COUNT(*)                                  AS customer_id_rows,
       COUNT(DISTINCT customer_unique_id)        AS unique_people,
       COUNT(*) - COUNT(DISTINCT customer_unique_id) AS extra_ids_from_repeat_buyers
FROM customers;

-- Q05 | Orders with no items, by status (these can never produce revenue)
-- Technique: anti-join with NOT EXISTS
SELECT o.order_status, COUNT(*) AS orders_without_items
FROM orders o
WHERE NOT EXISTS (SELECT 1 FROM order_items i WHERE i.order_id = o.order_id)
GROUP BY o.order_status
ORDER BY orders_without_items DESC;

-- Q06 | Delivered orders that have no delivery date, and orders with impossible timestamps
-- Technique: conditional aggregation with FILTER
SELECT COUNT(*) FILTER (WHERE order_status = 'delivered' AND order_delivered_customer_date IS NULL)  AS delivered_but_no_date,
       COUNT(*) FILTER (WHERE order_delivered_customer_date < order_purchase_timestamp)              AS delivered_before_purchase,
       COUNT(*) FILTER (WHERE order_approved_at < order_purchase_timestamp)                          AS approved_before_purchase,
       COUNT(*) FILTER (WHERE order_delivered_customer_date < order_delivered_carrier_date)          AS delivered_before_carrier_pickup
FROM orders;

-- Q07 | Products whose category has no English translation, and products with no category at all
-- Technique: LEFT JOIN + IS NULL
SELECT COALESCE(p.product_category_name, '(no category)') AS product_category_name,
       COUNT(*) AS products,
       BOOL_AND(t.product_category_name IS NULL)          AS missing_translation
FROM products p
LEFT JOIN category_translation t USING (product_category_name)
WHERE t.product_category_name IS NULL
GROUP BY 1
ORDER BY products DESC;

-- Q08 | Orders with more than one review (needs de-duplication before joining to reviews)
-- Technique: GROUP BY ... HAVING
SELECT reviews_per_order, COUNT(*) AS orders
FROM (SELECT order_id, COUNT(*) AS reviews_per_order
      FROM order_reviews
      GROUP BY order_id) x
GROUP BY reviews_per_order
ORDER BY reviews_per_order;

-- Q09 | Payment rows with an undefined type or zero value
-- Technique: simple filter
SELECT payment_type, COUNT(*) AS payments, SUM(payment_value) AS total_value
FROM order_payments
GROUP BY payment_type
ORDER BY payments DESC;

-- Q10 | Does item price + freight add up to what customers paid? (reconciliation per order)
-- Technique: two separate aggregations joined together (avoids the join fan-out trap)
WITH items AS (
    SELECT order_id, SUM(price + freight_value) AS items_total
    FROM order_items GROUP BY order_id
), pay AS (
    SELECT order_id, SUM(payment_value) AS paid_total
    FROM order_payments GROUP BY order_id
)
SELECT COUNT(*)                                                         AS orders_compared,
       COUNT(*) FILTER (WHERE ABS(i.items_total - p.paid_total) <= 0.01) AS matches_within_1_cent,
       ROUND(100.0 * COUNT(*) FILTER (WHERE ABS(i.items_total - p.paid_total) <= 0.01) / COUNT(*), 2) AS pct_match
FROM items i
JOIN pay p USING (order_id);

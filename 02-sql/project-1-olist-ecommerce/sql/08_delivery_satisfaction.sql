-- =====================================================================
-- 08_delivery_satisfaction.sql  |  Does delivery performance drive reviews?
-- Uses delivered orders only. "Late" = delivered on a later day than estimated.
-- =====================================================================
SET search_path TO olist;

-- Q37 | Delivery performance overall
-- Technique: PERCENTILE_CONT, FILTER
SELECT COUNT(*)                                                                   AS delivered_orders,
       ROUND(AVG(delivery_days), 1)                                               AS avg_delivery_days,
       ROUND(PERCENTILE_CONT(0.5)  WITHIN GROUP (ORDER BY delivery_days)::numeric, 1) AS median_days,
       ROUND(PERCENTILE_CONT(0.9)  WITHIN GROUP (ORDER BY delivery_days)::numeric, 1) AS p90_days,
       ROUND(100.0 * AVG(is_late::int), 2)                                        AS pct_late,
       ROUND(AVG(days_vs_estimate), 1)                                            AS avg_days_vs_estimate
FROM v_order_summary
WHERE order_status = 'delivered' AND delivery_days IS NOT NULL;

-- Q38 | Late-delivery rate by month (shows the Black Friday and early-2018 problems)
-- Technique: GROUP BY month, boolean average
SELECT TO_CHAR(purchase_month, 'YYYY-MM')                  AS month,
       COUNT(*)                                            AS delivered_orders,
       ROUND(100.0 * AVG(is_late::int), 1)                 AS pct_late,
       ROUND(AVG(delivery_days), 1)                        AS avg_delivery_days
FROM v_order_summary
WHERE order_status = 'delivered' AND delivery_days IS NOT NULL
  AND purchase_month >= DATE '2017-01-01' AND purchase_month < DATE '2018-09-01'
GROUP BY purchase_month
ORDER BY purchase_month;

-- Q39 | Slowest and fastest states (min. 1,000 delivered orders)
-- Technique: HAVING, RANK()
SELECT RANK() OVER (ORDER BY AVG(delivery_days) DESC) AS slowest_rank,
       customer_state,
       COUNT(*)                                       AS delivered_orders,
       ROUND(AVG(delivery_days), 1)                   AS avg_delivery_days,
       ROUND(100.0 * AVG(is_late::int), 1)            AS pct_late
FROM v_order_summary
WHERE order_status = 'delivered' AND delivery_days IS NOT NULL
GROUP BY customer_state
HAVING COUNT(*) >= 1000
ORDER BY avg_delivery_days DESC;

-- Q40 | Review score distribution (latest review per order)
-- Technique: JOIN to the de-duplicated view, window percentage
SELECT r.review_score,
       COUNT(*)                                            AS orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)  AS pct_of_orders
FROM v_order_review r
JOIN orders o USING (order_id)
WHERE o.order_status = 'delivered'
GROUP BY r.review_score
ORDER BY r.review_score DESC;

-- Q41 | THE KEY QUESTION: how much does lateness hurt review scores?
-- Technique: CASE buckets on days_vs_estimate, JOIN, boolean average
SELECT CASE WHEN s.days_vs_estimate <= 0  THEN '1 On time or early'
            WHEN s.days_vs_estimate <= 3  THEN '2 Late by 1-3 days'
            WHEN s.days_vs_estimate <= 7  THEN '3 Late by 4-7 days'
            ELSE '4 Late by 8+ days' END                         AS delivery_outcome,
       COUNT(*)                                                  AS orders,
       ROUND(AVG(r.review_score), 2)                             AS avg_review_score,
       ROUND(100.0 * AVG((r.review_score <= 2)::int), 1)         AS pct_negative_reviews,
       ROUND(100.0 * AVG((r.review_score = 5)::int), 1)          AS pct_five_star
FROM v_order_summary s
JOIN v_order_review r USING (order_id)
WHERE s.order_status = 'delivered' AND s.days_vs_estimate IS NOT NULL
GROUP BY 1
ORDER BY 1;

-- Q42 | Does the actual delivery speed matter, even when on time?
-- Technique: CASE buckets on delivery_days, restricted to on-time orders
SELECT CASE WHEN s.delivery_days < 7  THEN '1 Under 1 week'
            WHEN s.delivery_days < 14 THEN '2 1-2 weeks'
            WHEN s.delivery_days < 21 THEN '3 2-3 weeks'
            ELSE '4 3+ weeks' END                                AS delivery_time,
       COUNT(*)                                                  AS orders,
       ROUND(AVG(r.review_score), 2)                             AS avg_review_score
FROM v_order_summary s
JOIN v_order_review r USING (order_id)
WHERE s.order_status = 'delivered' AND NOT s.is_late AND s.delivery_days IS NOT NULL
GROUP BY 1
ORDER BY 1;

-- Q43 | Late deliveries by seller state: where do promises get broken? (min. 1,000 orders)
-- Technique: JOIN items to the order summary at seller-state level
WITH order_seller_state AS (
    SELECT DISTINCT l.order_id, l.seller_state
    FROM v_sales_lines l
)
SELECT oss.seller_state,
       COUNT(*)                                         AS orders,
       ROUND(100.0 * AVG(s.is_late::int), 1)            AS pct_late,
       ROUND(AVG(s.delivery_days), 1)                   AS avg_delivery_days
FROM order_seller_state oss
JOIN v_order_summary s USING (order_id)
WHERE s.delivery_days IS NOT NULL
GROUP BY oss.seller_state
HAVING COUNT(*) >= 1000
ORDER BY pct_late DESC;

-- Q44 | Sellers whose late rate is far above the platform average (min. 100 orders)
-- Technique: CTE with a scalar subquery benchmark
WITH seller_orders AS (
    SELECT l.seller_id, l.order_id
    FROM (SELECT DISTINCT seller_id, order_id FROM v_sales_lines) l
), seller_perf AS (
    SELECT so.seller_id,
           COUNT(*)                              AS orders,
           100.0 * AVG(s.is_late::int)           AS pct_late,
           AVG(r.review_score)                   AS avg_review
    FROM seller_orders so
    JOIN v_order_summary s USING (order_id)
    JOIN v_order_review r  USING (order_id)
    WHERE s.delivery_days IS NOT NULL
    GROUP BY so.seller_id
    HAVING COUNT(*) >= 100
)
SELECT seller_id,
       orders,
       ROUND(pct_late, 1)                                                     AS pct_late,
       ROUND((SELECT 100.0 * AVG(is_late::int) FROM v_order_summary WHERE delivery_days IS NOT NULL), 1) AS platform_pct_late,
       ROUND(avg_review, 2)                                                   AS avg_review
FROM seller_perf
WHERE pct_late >= 2 * (SELECT 100.0 * AVG(is_late::int) FROM v_order_summary WHERE delivery_days IS NOT NULL)
ORDER BY pct_late DESC
LIMIT 10;

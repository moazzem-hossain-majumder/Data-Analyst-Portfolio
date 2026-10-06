-- =====================================================================
-- 05_sales_analysis.sql  |  How is the business performing?
-- Requires 04_views.sql. Revenue = item price of delivered orders.
-- =====================================================================
SET search_path TO olist;

-- Q11 | Headline KPIs
-- Technique: aggregate functions, COUNT DISTINCT
SELECT COUNT(DISTINCT order_id)                                   AS delivered_orders,
       COUNT(DISTINCT customer_unique_id)                         AS unique_customers,
       COUNT(*)                                                   AS items_sold,
       ROUND(SUM(price), 2)                                       AS revenue,
       ROUND(SUM(freight_value), 2)                               AS freight,
       ROUND(SUM(price) / COUNT(DISTINCT order_id), 2)            AS avg_order_value,
       MIN(order_purchase_timestamp)::date                        AS first_order,
       MAX(order_purchase_timestamp)::date                        AS last_order
FROM v_sales_lines;

-- Q12 | Monthly revenue, orders and average order value
-- Technique: GROUP BY on a truncated date
SELECT TO_CHAR(purchase_month, 'YYYY-MM')                 AS month,
       COUNT(DISTINCT order_id)                           AS orders,
       ROUND(SUM(price), 2)                               AS revenue,
       ROUND(SUM(price) / COUNT(DISTINCT order_id), 2)    AS avg_order_value
FROM v_sales_lines
GROUP BY purchase_month
ORDER BY purchase_month;

-- Q13 | Month-over-month growth and running total
-- Technique: CTE + LAG() and a running SUM() window
WITH monthly AS (
    SELECT purchase_month, SUM(price) AS revenue
    FROM v_sales_lines
    WHERE purchase_month >= DATE '2017-01-01' AND purchase_month < DATE '2018-09-01'   -- full months only
    GROUP BY purchase_month
)
SELECT TO_CHAR(purchase_month, 'YYYY-MM')                                          AS month,
       ROUND(revenue, 2)                                                            AS revenue,
       ROUND(100.0 * (revenue - LAG(revenue) OVER w) / LAG(revenue) OVER w, 1)      AS mom_growth_pct,
       ROUND(SUM(revenue) OVER (ORDER BY purchase_month), 2)                        AS running_total
FROM monthly
WINDOW w AS (ORDER BY purchase_month)
ORDER BY purchase_month;

-- Q14 | 3-month moving average (smooths the Black Friday spike)
-- Technique: window frame ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
WITH monthly AS (
    SELECT purchase_month, SUM(price) AS revenue
    FROM v_sales_lines
    WHERE purchase_month >= DATE '2017-01-01' AND purchase_month < DATE '2018-09-01'
    GROUP BY purchase_month
)
SELECT TO_CHAR(purchase_month, 'YYYY-MM') AS month,
       ROUND(revenue, 2) AS revenue,
       ROUND(AVG(revenue) OVER (ORDER BY purchase_month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2) AS moving_avg_3m
FROM monthly
ORDER BY purchase_month;

-- Q15 | Year-over-year growth, Jan-Aug 2018 vs Jan-Aug 2017
-- Technique: conditional aggregation with FILTER (a pivot without PIVOT)
SELECT EXTRACT(MONTH FROM purchase_month)::int AS month_no,
       TO_CHAR(purchase_month, 'Mon')           AS month_name,
       ROUND(SUM(price) FILTER (WHERE EXTRACT(YEAR FROM purchase_month) = 2017), 2) AS revenue_2017,
       ROUND(SUM(price) FILTER (WHERE EXTRACT(YEAR FROM purchase_month) = 2018), 2) AS revenue_2018,
       ROUND(100.0 * (SUM(price) FILTER (WHERE EXTRACT(YEAR FROM purchase_month) = 2018)
                    / SUM(price) FILTER (WHERE EXTRACT(YEAR FROM purchase_month) = 2017) - 1), 1) AS yoy_growth_pct
FROM v_sales_lines
WHERE EXTRACT(MONTH FROM purchase_month) BETWEEN 1 AND 8
  AND EXTRACT(YEAR FROM purchase_month) IN (2017, 2018)
GROUP BY 1, 2
ORDER BY 1;

-- Q16 | Top 10 product categories by revenue, with share and cumulative share
-- Technique: JOIN through the translation table, SUM() OVER for cumulative share
WITH cat AS (
    SELECT category, SUM(price) AS revenue, COUNT(DISTINCT order_id) AS orders
    FROM v_sales_lines
    GROUP BY category
)
SELECT category,
       orders,
       ROUND(revenue, 2)                                                    AS revenue,
       ROUND(100.0 * revenue / SUM(revenue) OVER (), 1)                     AS pct_of_revenue,
       ROUND(100.0 * SUM(revenue) OVER (ORDER BY revenue DESC) / SUM(revenue) OVER (), 1) AS cumulative_pct
FROM cat
ORDER BY revenue DESC
LIMIT 10;

-- Q17 | Revenue by customer state (top 10) with revenue per order
-- Technique: GROUP BY + window percentage + LIMIT
SELECT customer_state,
       COUNT(DISTINCT order_id)                                   AS orders,
       ROUND(SUM(price), 2)                                       AS revenue,
       ROUND(100.0 * SUM(price) / SUM(SUM(price)) OVER (), 1)     AS pct_of_revenue,
       ROUND(SUM(price) / COUNT(DISTINCT order_id), 2)            AS revenue_per_order
FROM v_sales_lines
GROUP BY customer_state
ORDER BY revenue DESC
LIMIT 10;

-- Q18 | Payment methods: orders, value and share (payments table, all delivered orders)
-- Technique: join to orders for the status filter; payments are NOT joined to items (no fan-out)
SELECT p.payment_type,
       COUNT(DISTINCT p.order_id)                                  AS orders,
       ROUND(SUM(p.payment_value), 2)                              AS paid_value,
       ROUND(100.0 * SUM(p.payment_value) / SUM(SUM(p.payment_value)) OVER (), 1) AS pct_of_value,
       ROUND(AVG(p.payment_value), 2)                              AS avg_payment
FROM order_payments p
JOIN orders o USING (order_id)
WHERE o.order_status = 'delivered'
GROUP BY p.payment_type
ORDER BY paid_value DESC;

-- Q19 | Credit-card installments: how do customers split bigger purchases?
-- Technique: CASE bucketing
SELECT CASE WHEN payment_installments = 1  THEN '1 (pay in full)'
            WHEN payment_installments <= 3 THEN '2-3'
            WHEN payment_installments <= 6 THEN '4-6'
            WHEN payment_installments <= 10 THEN '7-10'
            ELSE '11+' END                                    AS installments,
       COUNT(*)                                               AS payments,
       ROUND(AVG(payment_value), 2)                           AS avg_payment_value,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)     AS pct_of_payments
FROM order_payments p
JOIN orders o USING (order_id)
WHERE p.payment_type = 'credit_card' AND o.order_status = 'delivered'
GROUP BY 1
ORDER BY MIN(payment_installments);

-- Q20 | When do customers buy? Orders by weekday
-- Technique: EXTRACT(ISODOW), window percentage
SELECT TO_CHAR(order_purchase_timestamp, 'ID') || ' ' || TO_CHAR(order_purchase_timestamp, 'Dy') AS weekday,
       COUNT(*)                                                AS orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)      AS pct_of_orders
FROM orders
WHERE order_status = 'delivered'
GROUP BY 1
ORDER BY 1;

-- Q21 | When do customers buy? Orders by time of day
-- Technique: CASE on EXTRACT(HOUR)
SELECT CASE WHEN EXTRACT(HOUR FROM order_purchase_timestamp) BETWEEN 0  AND 5  THEN '1 Night (00-05)'
            WHEN EXTRACT(HOUR FROM order_purchase_timestamp) BETWEEN 6  AND 11 THEN '2 Morning (06-11)'
            WHEN EXTRACT(HOUR FROM order_purchase_timestamp) BETWEEN 12 AND 17 THEN '3 Afternoon (12-17)'
            ELSE '4 Evening (18-23)' END                       AS time_of_day,
       COUNT(*)                                                AS orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)      AS pct_of_orders
FROM orders
WHERE order_status = 'delivered'
GROUP BY 1
ORDER BY 1;

-- Q22 | Order value distribution (items + freight actually paid)
-- Technique: ordered-set aggregate PERCENTILE_CONT
SELECT COUNT(*)                                                       AS orders,
       ROUND(AVG(paid_value), 2)                                      AS mean,
       ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY paid_value)::numeric, 2) AS p25,
       ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY paid_value)::numeric, 2) AS median,
       ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY paid_value)::numeric, 2) AS p75,
       ROUND(PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY paid_value)::numeric, 2) AS p90,
       ROUND(PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY paid_value)::numeric, 2) AS p99
FROM v_order_summary
WHERE order_status = 'delivered' AND paid_value > 0;

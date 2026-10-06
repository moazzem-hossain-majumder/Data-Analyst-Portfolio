-- =====================================================================
-- 06_customer_analysis.sql  |  Who are the customers and do they come back?
-- A customer is a customer_unique_id (a person).
-- =====================================================================
SET search_path TO olist;

-- Q23 | How many orders does each customer place? (repeat-purchase rate)
-- Technique: two-level aggregation (orders per customer, then customers per order count)
WITH per_customer AS (
    SELECT customer_unique_id, COUNT(DISTINCT order_id) AS orders
    FROM v_sales_lines
    GROUP BY customer_unique_id
)
SELECT CASE WHEN orders >= 4 THEN '4+' ELSE orders::text END       AS orders_placed,
       COUNT(*)                                                    AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)          AS pct_of_customers
FROM per_customer
GROUP BY 1
ORDER BY 1;

-- Q24 | RFM segmentation: Recency, Frequency, Monetary value per customer
-- Technique: CTE chain, NTILE() scoring, CASE segment rules
WITH ref AS (
    SELECT MAX(order_purchase_timestamp)::date + 1 AS today FROM v_sales_lines
), cust AS (
    SELECT customer_unique_id,
           (SELECT today FROM ref) - MAX(order_purchase_timestamp)::date AS recency_days,
           COUNT(DISTINCT order_id)                                      AS frequency,
           SUM(price)                                                    AS monetary
    FROM v_sales_lines
    GROUP BY customer_unique_id
), scored AS (
    SELECT *,
           NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,      -- 5 = most recent
           NTILE(5) OVER (ORDER BY monetary)          AS m_score,      -- 5 = biggest spenders
           CASE WHEN frequency >= 3 THEN 3 WHEN frequency = 2 THEN 2 ELSE 1 END AS f_score
    FROM cust
), segmented AS (
    SELECT *,
           CASE WHEN f_score >= 2 AND r_score >= 4                 THEN 'Loyal / active repeat buyers'
                WHEN f_score >= 2                                  THEN 'Repeat buyers, cooling off'
                WHEN r_score = 5 AND m_score >= 4                  THEN 'New big spenders'
                WHEN r_score >= 4                                  THEN 'Recent one-time buyers'
                WHEN m_score >= 4                                  THEN 'Lapsed big spenders'
                ELSE 'Lapsed low spenders' END AS segment
    FROM scored
)
SELECT segment,
       COUNT(*)                                                    AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)          AS pct_of_customers,
       ROUND(AVG(recency_days), 0)                                 AS avg_recency_days,
       ROUND(AVG(monetary), 2)                                     AS avg_spend,
       ROUND(SUM(monetary), 2)                                     AS total_revenue,
       ROUND(100.0 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 1) AS pct_of_revenue
FROM segmented
GROUP BY segment
ORDER BY total_revenue DESC;

-- Q25 | Cohort retention: of customers whose FIRST order was in month X, how many ordered again N months later?
-- Technique: CTEs, MIN() per customer, month arithmetic, self-referencing cohort join
WITH orders_by_cust AS (
    SELECT DISTINCT customer_unique_id, purchase_month
    FROM v_sales_lines
), first_month AS (
    SELECT customer_unique_id, MIN(purchase_month) AS cohort_month
    FROM orders_by_cust
    GROUP BY customer_unique_id
), activity AS (
    SELECT f.cohort_month,
           (EXTRACT(YEAR FROM o.purchase_month) * 12 + EXTRACT(MONTH FROM o.purchase_month)
          - EXTRACT(YEAR FROM f.cohort_month)   * 12 - EXTRACT(MONTH FROM f.cohort_month))::int AS month_offset,
           COUNT(DISTINCT o.customer_unique_id) AS active_customers
    FROM first_month f
    JOIN orders_by_cust o USING (customer_unique_id)
    GROUP BY 1, 2
)
SELECT TO_CHAR(cohort_month, 'YYYY-MM') AS cohort,
       month_offset,
       active_customers,
       ROUND(100.0 * active_customers / FIRST_VALUE(active_customers) OVER (PARTITION BY cohort_month ORDER BY month_offset), 2) AS retention_pct
FROM activity
WHERE cohort_month BETWEEN DATE '2017-01-01' AND DATE '2017-12-01'
  AND month_offset BETWEEN 0 AND 6
ORDER BY cohort_month, month_offset;

-- Q26 | Average retention by months since first purchase (all 2017 cohorts)
-- Technique: weighted average from the cohort table
WITH orders_by_cust AS (
    SELECT DISTINCT customer_unique_id, purchase_month FROM v_sales_lines
), first_month AS (
    SELECT customer_unique_id, MIN(purchase_month) AS cohort_month FROM orders_by_cust GROUP BY 1
), activity AS (
    SELECT f.cohort_month,
           (EXTRACT(YEAR FROM o.purchase_month) * 12 + EXTRACT(MONTH FROM o.purchase_month)
          - EXTRACT(YEAR FROM f.cohort_month)   * 12 - EXTRACT(MONTH FROM f.cohort_month))::int AS month_offset,
           COUNT(DISTINCT o.customer_unique_id) AS active_customers
    FROM first_month f JOIN orders_by_cust o USING (customer_unique_id)
    GROUP BY 1, 2
), sizes AS (
    SELECT cohort_month, active_customers AS cohort_size FROM activity WHERE month_offset = 0
)
SELECT a.month_offset,
       SUM(a.active_customers)                                   AS returning_customers,
       SUM(s.cohort_size)                                        AS cohort_customers,
       ROUND(100.0 * SUM(a.active_customers) / SUM(s.cohort_size), 2) AS retention_pct
FROM activity a
JOIN sizes s USING (cohort_month)
WHERE a.cohort_month BETWEEN DATE '2017-01-01' AND DATE '2017-12-01'
  AND a.month_offset BETWEEN 0 AND 6
GROUP BY a.month_offset
ORDER BY a.month_offset;

-- Q27 | Customer concentration: share of revenue by spending decile
-- Technique: NTILE(10) over customers ordered by spend
WITH cust AS (
    SELECT customer_unique_id, SUM(price) AS spend
    FROM v_sales_lines
    GROUP BY customer_unique_id
), deciles AS (
    SELECT spend, NTILE(10) OVER (ORDER BY spend DESC) AS decile
    FROM cust
)
SELECT decile,
       COUNT(*)                                                    AS customers,
       ROUND(SUM(spend), 2)                                        AS revenue,
       ROUND(100.0 * SUM(spend) / SUM(SUM(spend)) OVER (), 1)      AS pct_of_revenue,
       ROUND(MIN(spend), 2)                                        AS min_spend,
       ROUND(MAX(spend), 2)                                        AS max_spend
FROM deciles
GROUP BY decile
ORDER BY decile;

-- Q28 | Where do repeat buyers live? Repeat rate by state (states with 1,000+ customers)
-- Technique: HAVING, conditional aggregation
WITH per_customer AS (
    SELECT customer_unique_id, MIN(customer_state) AS state, COUNT(DISTINCT order_id) AS orders
    FROM v_sales_lines
    GROUP BY customer_unique_id
)
SELECT state,
       COUNT(*)                                                     AS customers,
       COUNT(*) FILTER (WHERE orders >= 2)                          AS repeat_customers,
       ROUND(100.0 * COUNT(*) FILTER (WHERE orders >= 2) / COUNT(*), 2) AS repeat_rate_pct
FROM per_customer
GROUP BY state
HAVING COUNT(*) >= 1000
ORDER BY repeat_rate_pct DESC;

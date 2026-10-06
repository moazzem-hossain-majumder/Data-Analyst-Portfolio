-- =====================================================================
-- 07_seller_product_analysis.sql  |  Which sellers and products matter?
-- =====================================================================
SET search_path TO olist;

-- Q29 | Top 10 sellers by revenue, with order count and average review score
-- Technique: CTEs, JOIN to the de-duplicated review view
WITH seller_sales AS (
    SELECT seller_id, seller_state,
           COUNT(DISTINCT order_id) AS orders,
           SUM(price)               AS revenue
    FROM v_sales_lines
    GROUP BY seller_id, seller_state
), seller_reviews AS (
    SELECT l.seller_id, AVG(r.review_score) AS avg_review
    FROM (SELECT DISTINCT seller_id, order_id FROM v_sales_lines) l
    JOIN v_order_review r USING (order_id)
    GROUP BY l.seller_id
)
SELECT RANK() OVER (ORDER BY s.revenue DESC)            AS rank,
       s.seller_id,
       s.seller_state,
       s.orders,
       ROUND(s.revenue, 2)                              AS revenue,
       ROUND(100.0 * s.revenue / SUM(s.revenue) OVER (), 2) AS pct_of_revenue,
       ROUND(r.avg_review, 2)                           AS avg_review_score
FROM seller_sales s
JOIN seller_reviews r USING (seller_id)
ORDER BY s.revenue DESC
LIMIT 10;

-- Q30 | Seller concentration (Pareto): how many sellers generate 80% of revenue?
-- Technique: cumulative SUM() window over ranked sellers
WITH seller_rev AS (
    SELECT seller_id, SUM(price) AS revenue FROM v_sales_lines GROUP BY seller_id
), ranked AS (
    SELECT seller_id, revenue,
           ROW_NUMBER() OVER (ORDER BY revenue DESC)                                   AS seller_rank,
           SUM(revenue) OVER (ORDER BY revenue DESC) / SUM(revenue) OVER ()            AS cum_share,
           COUNT(*) OVER ()                                                            AS total_sellers
    FROM seller_rev
)
SELECT MIN(seller_rank) FILTER (WHERE cum_share >= 0.5)                                AS sellers_for_50pct,
       MIN(seller_rank) FILTER (WHERE cum_share >= 0.8)                                AS sellers_for_80pct,
       MAX(total_sellers)                                                              AS active_sellers,
       ROUND(100.0 * MIN(seller_rank) FILTER (WHERE cum_share >= 0.8) / MAX(total_sellers), 1) AS pct_of_sellers_for_80pct
FROM ranked;

-- Q31 | Seller geography: where are sellers and where is the money?
-- Technique: GROUP BY with window percentages
SELECT seller_state,
       COUNT(DISTINCT seller_id)                                   AS sellers,
       ROUND(100.0 * COUNT(DISTINCT seller_id) / SUM(COUNT(DISTINCT seller_id)) OVER (), 1) AS pct_of_sellers,
       ROUND(SUM(price), 2)                                        AS revenue,
       ROUND(100.0 * SUM(price) / SUM(SUM(price)) OVER (), 1)      AS pct_of_revenue
FROM v_sales_lines
GROUP BY seller_state
ORDER BY revenue DESC
LIMIT 5;

-- Q32 | Best-selling category in every customer state
-- Technique: DENSE_RANK() PARTITION BY state, filter on rank = 1 via a subquery
SELECT customer_state, category, orders, revenue, pct_of_state_revenue
FROM (
    SELECT customer_state,
           category,
           COUNT(DISTINCT order_id)                                                    AS orders,
           ROUND(SUM(price), 2)                                                        AS revenue,
           ROUND(100.0 * SUM(price) / SUM(SUM(price)) OVER (PARTITION BY customer_state), 1) AS pct_of_state_revenue,
           DENSE_RANK() OVER (PARTITION BY customer_state ORDER BY SUM(price) DESC)    AS rnk
    FROM v_sales_lines
    GROUP BY customer_state, category
) x
WHERE rnk = 1
ORDER BY revenue DESC
LIMIT 10;

-- Q33 | Price bands: where does revenue come from?
-- Technique: CASE bucketing
SELECT CASE WHEN price < 50  THEN '1  Under R$50'
            WHEN price < 100 THEN '2  R$50-99'
            WHEN price < 200 THEN '3  R$100-199'
            WHEN price < 500 THEN '4  R$200-499'
            ELSE '5  R$500+' END                                    AS price_band,
       COUNT(*)                                                     AS items,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)           AS pct_of_items,
       ROUND(SUM(price), 2)                                         AS revenue,
       ROUND(100.0 * SUM(price) / SUM(SUM(price)) OVER (), 1)       AS pct_of_revenue,
       ROUND(100.0 * SUM(freight_value) / SUM(price), 1)            AS freight_pct_of_price
FROM v_sales_lines
GROUP BY 1
ORDER BY 1;

-- Q34 | Categories where freight eats the price (min. 500 items sold)
-- Technique: HAVING, ratio of sums (not average of ratios)
SELECT category,
       COUNT(*)                                          AS items,
       ROUND(AVG(price), 2)                              AS avg_price,
       ROUND(AVG(freight_value), 2)                      AS avg_freight,
       ROUND(100.0 * SUM(freight_value) / SUM(price), 1) AS freight_pct_of_price
FROM v_sales_lines
GROUP BY category
HAVING COUNT(*) >= 500
ORDER BY freight_pct_of_price DESC
LIMIT 10;

-- Q35 | Categories with the best and worst customer reviews (min. 500 orders)
-- Technique: UNION ALL of two ranked subqueries
WITH cat_reviews AS (
    SELECT l.category,
           COUNT(DISTINCT l.order_id)                                     AS orders,
           ROUND(AVG(r.review_score), 2)                                  AS avg_review_score,
           ROUND(100.0 * AVG((r.review_score <= 2)::int), 1)              AS pct_negative
    FROM (SELECT DISTINCT order_id, category FROM v_sales_lines) l
    JOIN v_order_review r USING (order_id)
    GROUP BY l.category
    HAVING COUNT(DISTINCT l.order_id) >= 500
)
(SELECT 'Best' AS group_, * FROM cat_reviews ORDER BY avg_review_score DESC, orders DESC LIMIT 5)
UNION ALL
(SELECT 'Worst', * FROM cat_reviews ORDER BY avg_review_score ASC, orders DESC LIMIT 5);

-- Q36 | Multi-item orders: how many items per order, and does basket size change order value?
-- Technique: grouping on a derived column
SELECT CASE WHEN n_items >= 4 THEN '4+' ELSE n_items::text END   AS items_in_order,
       COUNT(*)                                                  AS orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)        AS pct_of_orders,
       ROUND(AVG(items_value), 2)                                AS avg_items_value
FROM v_order_summary
WHERE order_status = 'delivered' AND n_items > 0
GROUP BY 1
ORDER BY 1;

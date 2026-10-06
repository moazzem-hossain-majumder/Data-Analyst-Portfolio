-- =====================================================================
-- 04_views.sql  |  Reusable building blocks for the analysis
-- Business rules used throughout the project:
--   * "Revenue" = SUM(price) of items in DELIVERED orders (freight excluded)
--   * "Customer" = customer_unique_id (a person), not customer_id (one per order)
--   * An order is "late" when it arrives on a later calendar day than the estimate
-- =====================================================================
SET search_path TO olist;

-- Latest review per order (some orders have more than one review)
CREATE OR REPLACE VIEW v_order_review AS
SELECT DISTINCT ON (order_id)
       order_id,
       review_score,
       review_comment_message IS NOT NULL AS has_comment
FROM order_reviews
ORDER BY order_id, review_answer_timestamp DESC NULLS LAST, review_creation_date DESC NULLS LAST;

-- One row per order with items, payment and delivery measures
-- (items and payments are aggregated separately first, so rows never multiply)
CREATE OR REPLACE VIEW v_order_summary AS
WITH items AS (
    SELECT order_id,
           COUNT(*)                    AS n_items,
           SUM(price)                  AS items_value,
           SUM(freight_value)          AS freight_value
    FROM order_items
    GROUP BY order_id
), pay AS (
    SELECT order_id, SUM(payment_value) AS paid_value
    FROM order_payments
    GROUP BY order_id
)
SELECT o.order_id,
       c.customer_unique_id,
       c.customer_state,
       o.order_status,
       o.order_purchase_timestamp,
       DATE_TRUNC('month', o.order_purchase_timestamp)::date AS purchase_month,
       COALESCE(i.n_items, 0)        AS n_items,
       COALESCE(i.items_value, 0)    AS items_value,
       COALESCE(i.freight_value, 0)  AS freight_value,
       COALESCE(p.paid_value, 0)     AS paid_value,
       ROUND(EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_purchase_timestamp)) / 86400.0, 1) AS delivery_days,
       (o.order_delivered_customer_date::date - o.order_estimated_delivery_date::date)                      AS days_vs_estimate,
       (o.order_delivered_customer_date::date > o.order_estimated_delivery_date::date)                      AS is_late
FROM orders o
JOIN customers c USING (customer_id)
LEFT JOIN items i USING (order_id)
LEFT JOIN pay   p USING (order_id);

-- Item-level sales fact table for delivered orders (the "revenue" base)
CREATE OR REPLACE VIEW v_sales_lines AS
SELECT oi.order_id,
       oi.order_item_id,
       o.order_purchase_timestamp,
       DATE_TRUNC('month', o.order_purchase_timestamp)::date AS purchase_month,
       c.customer_unique_id,
       c.customer_state,
       oi.seller_id,
       s.seller_state,
       oi.product_id,
       COALESCE(t.product_category_name_english, p.product_category_name, 'unknown') AS category,
       oi.price,
       oi.freight_value
FROM order_items oi
JOIN orders    o ON o.order_id    = oi.order_id
JOIN customers c ON c.customer_id = o.customer_id
JOIN sellers   s ON s.seller_id   = oi.seller_id
JOIN products  p ON p.product_id  = oi.product_id
LEFT JOIN category_translation t ON t.product_category_name = p.product_category_name
WHERE o.order_status = 'delivered';

-- Pre-computed monthly sales (a materialized view stores the result on disk)
DROP MATERIALIZED VIEW IF EXISTS mv_monthly_sales;
CREATE MATERIALIZED VIEW mv_monthly_sales AS
SELECT purchase_month,
       COUNT(DISTINCT order_id) AS orders,
       SUM(price)               AS revenue
FROM v_sales_lines
GROUP BY purchase_month;

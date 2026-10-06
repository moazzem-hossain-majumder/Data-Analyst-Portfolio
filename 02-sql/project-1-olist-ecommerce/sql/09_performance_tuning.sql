-- =====================================================================
-- 09_performance_tuning.sql  |  Does an index actually help?
-- Compares the query plan for a date-range filter with and without an index.
-- Everything runs inside a transaction that is rolled back, so nothing changes.
-- Look for "Seq Scan" (reads the whole table) vs "Index Scan / Bitmap Index Scan".
-- Timings differ per machine; focus on the plan shape and the rows/buffers read.
-- =====================================================================
SET search_path TO olist;

BEGIN;

-- 1) Without the index on order_purchase_timestamp
DROP INDEX idx_orders_purchase;
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT order_id, order_status
FROM orders
WHERE order_purchase_timestamp >= DATE '2018-08-01'
  AND order_purchase_timestamp <  DATE '2018-08-08';

-- 2) With the index
CREATE INDEX idx_orders_purchase ON orders (order_purchase_timestamp);
ANALYZE orders;
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT order_id, order_status
FROM orders
WHERE order_purchase_timestamp >= DATE '2018-08-01'
  AND order_purchase_timestamp <  DATE '2018-08-08';

ROLLBACK;

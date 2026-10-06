-- =====================================================================
-- 02_load_data.sql  |  Loads the Kaggle CSVs with psql's \copy
-- Run from the PROJECT ROOT so the relative data/ paths resolve:
--   psql -d olist -f sql/02_load_data.sql
-- (\copy reads the files on YOUR machine, so it works with any server.)
-- =====================================================================
SET search_path TO olist;

\copy category_translation FROM 'data/product_category_name_translation.csv' WITH (FORMAT csv, HEADER true)
\copy customers            FROM 'data/olist_customers_dataset.csv'            WITH (FORMAT csv, HEADER true)
\copy sellers              FROM 'data/olist_sellers_dataset.csv'              WITH (FORMAT csv, HEADER true)
\copy products             FROM 'data/olist_products_dataset.csv'             WITH (FORMAT csv, HEADER true)
\copy orders               FROM 'data/olist_orders_dataset.csv'               WITH (FORMAT csv, HEADER true)
\copy order_items          FROM 'data/olist_order_items_dataset.csv'          WITH (FORMAT csv, HEADER true)
\copy order_payments       FROM 'data/olist_order_payments_dataset.csv'       WITH (FORMAT csv, HEADER true)
\copy order_reviews        FROM 'data/olist_order_reviews_dataset.csv'        WITH (FORMAT csv, HEADER true, FORCE_NULL (review_comment_title, review_comment_message))

ANALYZE;

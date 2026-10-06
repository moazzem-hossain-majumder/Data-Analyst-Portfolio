-- =====================================================================
-- 01_schema.sql  |  Olist Brazilian E-Commerce  |  PostgreSQL 14+
-- Creates the database objects. Run from the project root:
--   createdb olist
--   psql -d olist -f sql/01_schema.sql
-- =====================================================================

DROP SCHEMA IF EXISTS olist CASCADE;
CREATE SCHEMA olist;
SET search_path TO olist;

-- Lookup: Portuguese category name -> English
CREATE TABLE category_translation (
    product_category_name          TEXT PRIMARY KEY,
    product_category_name_english  TEXT NOT NULL
);

CREATE TABLE customers (
    customer_id               TEXT PRIMARY KEY,   -- one per order (changes every order)
    customer_unique_id        TEXT NOT NULL,      -- identifies the real person
    customer_zip_code_prefix  TEXT,
    customer_city             TEXT,
    customer_state            CHAR(2)
);

CREATE TABLE sellers (
    seller_id                 TEXT PRIMARY KEY,
    seller_zip_code_prefix    TEXT,
    seller_city               TEXT,
    seller_state              CHAR(2)
);

CREATE TABLE products (
    product_id                  TEXT PRIMARY KEY,
    product_category_name       TEXT,
    product_name_lenght         INT,              -- spelling as in the source file
    product_description_lenght  INT,
    product_photos_qty          INT,
    product_weight_g            INT,
    product_length_cm           INT,
    product_height_cm           INT,
    product_width_cm            INT
);

CREATE TABLE orders (
    order_id                       TEXT PRIMARY KEY,
    customer_id                    TEXT NOT NULL REFERENCES customers (customer_id),
    order_status                   TEXT NOT NULL,
    order_purchase_timestamp       TIMESTAMP NOT NULL,
    order_approved_at              TIMESTAMP,
    order_delivered_carrier_date   TIMESTAMP,
    order_delivered_customer_date  TIMESTAMP,
    order_estimated_delivery_date  TIMESTAMP NOT NULL
);

CREATE TABLE order_items (
    order_id             TEXT NOT NULL REFERENCES orders (order_id),
    order_item_id        INT  NOT NULL,           -- 1, 2, 3 ... within the order
    product_id           TEXT NOT NULL REFERENCES products (product_id),
    seller_id            TEXT NOT NULL REFERENCES sellers (seller_id),
    shipping_limit_date  TIMESTAMP,
    price                NUMERIC(10,2) NOT NULL,
    freight_value        NUMERIC(10,2) NOT NULL,
    PRIMARY KEY (order_id, order_item_id)
);

CREATE TABLE order_payments (
    order_id              TEXT NOT NULL REFERENCES orders (order_id),
    payment_sequential    INT  NOT NULL,
    payment_type          TEXT NOT NULL,
    payment_installments  INT  NOT NULL,
    payment_value         NUMERIC(10,2) NOT NULL,
    PRIMARY KEY (order_id, payment_sequential)
);

-- review_id is NOT unique in the source file, so no primary key here
CREATE TABLE order_reviews (
    review_id                TEXT NOT NULL,
    order_id                 TEXT NOT NULL REFERENCES orders (order_id),
    review_score             INT  NOT NULL CHECK (review_score BETWEEN 1 AND 5),
    review_comment_title     TEXT,
    review_comment_message   TEXT,
    review_creation_date     TIMESTAMP,
    review_answer_timestamp  TIMESTAMP
);

-- Indexes for the joins and filters used in the analysis
CREATE INDEX idx_orders_customer   ON orders (customer_id);
CREATE INDEX idx_orders_purchase   ON orders (order_purchase_timestamp);
CREATE INDEX idx_orders_status     ON orders (order_status);
CREATE INDEX idx_items_product     ON order_items (product_id);
CREATE INDEX idx_items_seller      ON order_items (seller_id);
CREATE INDEX idx_reviews_order     ON order_reviews (order_id);
CREATE INDEX idx_customers_unique  ON customers (customer_unique_id);

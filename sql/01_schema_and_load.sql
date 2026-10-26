-- =====================================================================
-- E-commerce Sales & Promotion Analysis  |  Akriti Kushwaha
-- File 1 of 2: create database, tables and load the cleaned CSVs
-- Tested for: MySQL 8.0+ (window functions and CTEs need 8.0 or newer)
-- =====================================================================

CREATE DATABASE IF NOT EXISTS ecommerce_analysis;
USE ecommerce_analysis;

DROP TABLE IF EXISTS fact_sales;
DROP TABLE IF EXISTS dim_customers;
DROP TABLE IF EXISTS dim_products;
DROP TABLE IF EXISTS dim_promotions;

CREATE TABLE dim_customers (
    customer_id    INT PRIMARY KEY,
    customer_name  VARCHAR(60) NOT NULL,
    city           VARCHAR(40) NOT NULL,
    state          VARCHAR(40) NOT NULL,
    country        VARCHAR(20) NOT NULL,
    pincode        INT
);

CREATE TABLE dim_products (
    product_id    VARCHAR(10) PRIMARY KEY,
    product_name  VARCHAR(60) NOT NULL,
    product_line  VARCHAR(40) NOT NULL,
    list_price    INT NOT NULL            -- price in INR
);

CREATE TABLE dim_promotions (
    promotion_id    VARCHAR(10) PRIMARY KEY,   -- PR000 = no promotion
    promotion_name  VARCHAR(40) NOT NULL,
    ad_type         VARCHAR(30),
    coupon_code     VARCHAR(30),
    reduction_type  VARCHAR(30)
);

CREATE TABLE fact_sales (
    order_id        INT PRIMARY KEY,
    order_date      DATE NOT NULL,
    customer_id     INT NOT NULL,
    product_id      VARCHAR(10) NOT NULL,
    promotion_id    VARCHAR(10) NOT NULL,
    units_sold      INT NOT NULL,
    price_per_unit  INT NOT NULL,
    gross_sales     DECIMAL(12,2) NOT NULL,   -- units_sold * price_per_unit
    discount_pct    INT NOT NULL,
    discount_value  DECIMAL(12,2) NOT NULL,
    net_sales       DECIMAL(12,2) NOT NULL,   -- gross_sales - discount_value
    profit          DECIMAL(12,2) NOT NULL,   -- fixed 10% of net_sales in this dataset
    FOREIGN KEY (customer_id)  REFERENCES dim_customers(customer_id),
    FOREIGN KEY (product_id)   REFERENCES dim_products(product_id),
    FOREIGN KEY (promotion_id) REFERENCES dim_promotions(promotion_id)
);

-- ---------------------------------------------------------------------
-- LOAD THE DATA
-- Option A (easiest, MySQL Workbench): right-click each table in the left
--   panel > "Table Data Import Wizard" > pick the matching CSV from /data.
--   Load in this order: dim_customers, dim_products, dim_promotions, fact_sales.
--
-- Option B (script): change the path below, then run. If you get error 3948,
--   run  SET GLOBAL local_infile = 1;  once and reconnect with local_infile on.
-- ---------------------------------------------------------------------
-- LOAD DATA LOCAL INFILE 'C:/path/to/data/dim_customers.csv'
-- INTO TABLE dim_customers FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
-- LINES TERMINATED BY '\n' IGNORE 1 LINES;
-- (repeat for dim_products.csv, dim_promotions.csv, fact_sales.csv)

-- After loading, this should return 50, 30, 6, 3510
SELECT (SELECT COUNT(*) FROM dim_customers)  AS customers,
       (SELECT COUNT(*) FROM dim_products)   AS products,
       (SELECT COUNT(*) FROM dim_promotions) AS promotions,
       (SELECT COUNT(*) FROM fact_sales)     AS orders;

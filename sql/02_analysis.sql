-- =====================================================================
-- E-commerce Sales & Promotion Analysis  |  Akriti Kushwaha
-- File 2 of 2: analysis queries (MySQL 8.0+)
-- Currency: INR. "Net sales" = gross sales minus discount.
-- Each query lists the business question it answers.
-- =====================================================================
USE ecommerce_analysis;

-- ---------------------------------------------------------------------
-- A. DATA QUALITY
-- ---------------------------------------------------------------------

-- Q1. Is the data trustworthy? Check for orphan keys, duplicate orders,
--     arithmetic errors and the date range before analysing anything.
SELECT
    COUNT(*)                                                       AS total_orders,
    COUNT(DISTINCT order_id)                                       AS unique_orders,
    MIN(order_date)                                                AS first_order,
    MAX(order_date)                                                AS last_order,
    SUM(CASE WHEN gross_sales <> units_sold * price_per_unit THEN 1 ELSE 0 END) AS gross_math_errors,
    SUM(CASE WHEN ROUND(gross_sales - discount_value - net_sales, 2) <> 0 THEN 1 ELSE 0 END) AS net_math_errors,
    SUM(CASE WHEN c.customer_id IS NULL THEN 1 ELSE 0 END)         AS orphan_customers,
    COUNT(DISTINCT ROUND(100.0 * profit / net_sales, 2))           AS distinct_profit_margins
FROM fact_sales f
LEFT JOIN dim_customers c ON f.customer_id = c.customer_id;
-- Finding: no errors, but profit is exactly 10% of net sales on every row
-- (distinct_profit_margins = 1). Profit carries no extra information here,
-- so this project analyses revenue and discount cost, not margin.

-- ---------------------------------------------------------------------
-- B. BUSINESS OVERVIEW
-- ---------------------------------------------------------------------

-- Q2. Headline numbers for the dashboard KPI cards.
SELECT
    COUNT(*)                                        AS orders,
    SUM(units_sold)                                 AS units_sold,
    ROUND(SUM(gross_sales), 0)                      AS gross_sales,
    ROUND(SUM(discount_value), 0)                   AS total_discount,
    ROUND(SUM(net_sales), 0)                        AS net_sales,
    ROUND(100.0 * SUM(discount_value) / SUM(gross_sales), 2) AS discount_pct_of_gross,
    ROUND(SUM(net_sales) / COUNT(*), 0)             AS avg_net_per_order
FROM fact_sales;

-- Q3. Is the business growing? Year-over-year net sales (2024 has a single
--     order on 1 Jan, so it is excluded).
WITH yearly AS (
    SELECT YEAR(order_date) AS yr, SUM(net_sales) AS net_sales
    FROM fact_sales
    WHERE order_date < '2024-01-01'
    GROUP BY YEAR(order_date)
)
SELECT yr,
       ROUND(net_sales, 0) AS net_sales,
       ROUND(100.0 * (net_sales - LAG(net_sales) OVER (ORDER BY yr))
             / LAG(net_sales) OVER (ORDER BY yr), 1) AS yoy_growth_pct
FROM yearly
ORDER BY yr;

-- Q4. Which quarters are strongest? Rank all 16 quarters.
WITH quarterly AS (
    SELECT YEAR(order_date) AS yr, QUARTER(order_date) AS qtr, SUM(net_sales) AS net_sales
    FROM fact_sales
    WHERE order_date < '2024-01-01'
    GROUP BY YEAR(order_date), QUARTER(order_date)
)
SELECT yr, qtr,
       ROUND(net_sales, 0) AS net_sales,
       RANK() OVER (ORDER BY net_sales DESC) AS sales_rank
FROM quarterly
ORDER BY sales_rank
LIMIT 5;

-- Q5. Monthly trend with month-over-month change and a 3-month moving average
--     (smooths out noise; this is the series used for the dashboard line chart).
WITH monthly AS (
    SELECT DATE_FORMAT(order_date, '%Y-%m') AS ym, SUM(net_sales) AS net_sales
    FROM fact_sales
    WHERE order_date < '2024-01-01'
    GROUP BY DATE_FORMAT(order_date, '%Y-%m')
)
SELECT ym,
       ROUND(net_sales, 0) AS net_sales,
       ROUND(100.0 * (net_sales - LAG(net_sales) OVER (ORDER BY ym))
             / LAG(net_sales) OVER (ORDER BY ym), 1) AS mom_pct,
       ROUND(AVG(net_sales) OVER (ORDER BY ym ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 0) AS moving_avg_3m
FROM monthly
ORDER BY ym;

-- ---------------------------------------------------------------------
-- C. PRODUCTS AND CITIES
-- ---------------------------------------------------------------------

-- Q6. How much does each product line contribute?
SELECT p.product_line,
       COUNT(*)                                             AS orders,
       ROUND(SUM(f.net_sales), 0)                           AS net_sales,
       ROUND(100.0 * SUM(f.net_sales) / SUM(SUM(f.net_sales)) OVER (), 1) AS share_pct
FROM fact_sales f
JOIN dim_products p ON f.product_id = p.product_id
GROUP BY p.product_line
ORDER BY net_sales DESC;

-- Q7. How concentrated is revenue? Top 10 products with cumulative share
--     (Pareto view).
WITH product_sales AS (
    SELECT p.product_name, p.product_line, SUM(f.net_sales) AS net_sales
    FROM fact_sales f
    JOIN dim_products p ON f.product_id = p.product_id
    GROUP BY p.product_name, p.product_line
)
SELECT product_name, product_line,
       ROUND(net_sales, 0) AS net_sales,
       ROUND(100.0 * net_sales / SUM(net_sales) OVER (), 1) AS share_pct,
       ROUND(100.0 * SUM(net_sales) OVER (ORDER BY net_sales DESC ROWS UNBOUNDED PRECEDING)
             / SUM(net_sales) OVER (), 1) AS cumulative_share_pct
FROM product_sales
ORDER BY net_sales DESC
LIMIT 10;

-- Q8. Best 2 products inside every product line.
WITH ranked AS (
    SELECT p.product_line, p.product_name,
           SUM(f.net_sales) AS net_sales,
           ROW_NUMBER() OVER (PARTITION BY p.product_line ORDER BY SUM(f.net_sales) DESC) AS rn
    FROM fact_sales f
    JOIN dim_products p ON f.product_id = p.product_id
    GROUP BY p.product_line, p.product_name
)
SELECT product_line, product_name, ROUND(net_sales, 0) AS net_sales, rn AS rank_in_line
FROM ranked
WHERE rn <= 2
ORDER BY product_line, rn;

-- Q9. Five weakest products overall (candidates for review or bundling).
SELECT p.product_name, p.product_line, ROUND(SUM(f.net_sales), 0) AS net_sales
FROM fact_sales f
JOIN dim_products p ON f.product_id = p.product_id
GROUP BY p.product_name, p.product_line
ORDER BY SUM(f.net_sales) ASC
LIMIT 5;

-- Q10. Which cities drive sales, and is that because of more customers or
--      higher spend per customer? (The dataset has only 50 customers, so a
--      city's rank is mostly decided by how many customers it has.)
SELECT c.city, c.state,
       COUNT(DISTINCT c.customer_id)                           AS customers,
       COUNT(*)                                                AS orders,
       ROUND(SUM(f.net_sales), 0)                              AS net_sales,
       ROUND(100.0 * SUM(f.net_sales) / SUM(SUM(f.net_sales)) OVER (), 1) AS share_pct,
       ROUND(SUM(f.net_sales) / COUNT(DISTINCT c.customer_id), 0) AS net_per_customer,
       RANK() OVER (ORDER BY SUM(f.net_sales) DESC)            AS city_rank
FROM fact_sales f
JOIN dim_customers c ON f.customer_id = c.customer_id
GROUP BY c.city, c.state
ORDER BY city_rank;

-- ---------------------------------------------------------------------
-- D. PROMOTIONS
-- ---------------------------------------------------------------------

-- Q11. Promotion scorecard. discount_per_rupee_net shows how many rupees of
--      discount were given for every rupee of net revenue collected.
SELECT pr.promotion_name,
       pr.reduction_type,
       COUNT(*)                                                   AS orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)         AS pct_of_orders,
       ROUND(SUM(f.gross_sales), 0)                               AS gross_sales,
       ROUND(SUM(f.discount_value), 0)                            AS discount_given,
       ROUND(SUM(f.net_sales), 0)                                 AS net_sales,
       ROUND(SUM(f.discount_value) / SUM(f.net_sales), 2)         AS discount_per_rupee_net
FROM fact_sales f
JOIN dim_promotions pr ON f.promotion_id = pr.promotion_id
GROUP BY pr.promotion_name, pr.reduction_type
ORDER BY net_sales DESC;

-- Q12. Do promo orders look different from regular orders?
--      (A comparison only. It cannot prove a promotion caused extra sales,
--      because the data has no control group.)
SELECT CASE WHEN promotion_id = 'PR000' THEN 'No promotion' ELSE 'On promotion' END AS order_type,
       COUNT(*)                          AS orders,
       ROUND(AVG(units_sold), 2)         AS avg_units_per_order,
       ROUND(AVG(gross_sales), 0)        AS avg_gross_per_order,
       ROUND(AVG(net_sales), 0)          AS avg_net_per_order
FROM fact_sales
GROUP BY CASE WHEN promotion_id = 'PR000' THEN 'No promotion' ELSE 'On promotion' END;

-- Q13. Where does the discount money go? Discount cost by product line.
WITH line_discount AS (
    SELECT p.product_line,
           SUM(f.discount_value) AS discount_given,
           SUM(f.gross_sales)    AS gross_sales,
           SUM(CASE WHEN f.promotion_id <> 'PR000' THEN 1 ELSE 0 END) AS promo_orders,
           COUNT(*)              AS orders
    FROM fact_sales f
    JOIN dim_products p ON f.product_id = p.product_id
    GROUP BY p.product_line
)
SELECT product_line,
       ROUND(discount_given, 0)                                       AS discount_given,
       ROUND(100.0 * discount_given / SUM(discount_given) OVER (), 1) AS share_of_all_discount_pct,
       ROUND(100.0 * promo_orders / orders, 1)                        AS pct_orders_on_promo
FROM line_discount
ORDER BY discount_given DESC;

-- ---------------------------------------------------------------------
-- E. CUSTOMERS
-- ---------------------------------------------------------------------

-- Q14. Is revenue dependent on a few customers? Top 10 with cumulative share.
WITH customer_sales AS (
    SELECT c.customer_name, c.city, COUNT(*) AS orders, SUM(f.net_sales) AS net_sales
    FROM fact_sales f
    JOIN dim_customers c ON f.customer_id = c.customer_id
    GROUP BY c.customer_id, c.customer_name, c.city
)
SELECT customer_name, city, orders,
       ROUND(net_sales, 0) AS net_sales,
       ROUND(100.0 * SUM(net_sales) OVER (ORDER BY net_sales DESC ROWS UNBOUNDED PRECEDING)
             / SUM(net_sales) OVER (), 1) AS cumulative_share_pct
FROM customer_sales
ORDER BY net_sales DESC
LIMIT 10;

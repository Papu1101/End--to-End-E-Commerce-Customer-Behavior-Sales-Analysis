SELECT * FROM customers LIMIT 10;

--For each customer, calculate their total lifetime revenue, total orders, and average order value.?

SELECT
    "Customer_ID",
    COUNT("Order_ID") AS total_orders,
    SUM("Total_Amount") AS lifetime_revenue,
    SUM("Total_Amount") / COUNT("Order_ID") AS avg_order_value
FROM customers
GROUP BY "Customer_ID"
ORDER BY lifetime_revenue DESC;

--Identify the top 10% highest-value customers based on lifetime spend??

WITH customer_lifetime AS (
    SELECT
        "Customer_ID",
        SUM("Total_Amount") AS lifetime_revenue
    FROM customers
    GROUP BY "Customer_ID"
),
revenue_threshold AS (
    SELECT
        PERCENTILE_CONT(0.9)
        WITHIN GROUP (ORDER BY lifetime_revenue) AS cutoff_revenue
    FROM customer_lifetime
)
SELECT
    cl."Customer_ID",
    cl.lifetime_revenue
FROM customer_lifetime cl
JOIN revenue_threshold rt
    ON cl.lifetime_revenue >= rt.cutoff_revenue
ORDER BY cl.lifetime_revenue DESC;

--Calculate recency for each customer as the number of days since their last order??

SELECT
    "Customer_ID",
    CURRENT_DATE - MAX("Date") AS recency_days
FROM customers
GROUP BY "Customer_ID"
ORDER BY recency_days;

--Classify customers into New, Active, and Inactive segments based on recency and order frequency??

WITH customer_metrics AS (
    SELECT
        "Customer_ID",
        COUNT("Order_ID") AS total_orders,
        EXTRACT(DAY FROM CURRENT_DATE - MAX("Date")) AS recency_days
    FROM customers
    GROUP BY "Customer_ID"
)
SELECT
    "Customer_ID",
    total_orders,
    recency_days,
    CASE
        WHEN total_orders = 1 THEN 'New'
        WHEN total_orders > 1 AND recency_days <= 90 THEN 'Active'
        ELSE 'Inactive'
    END AS customer_segment
FROM customer_metrics
ORDER BY customer_segment, recency_days;


--Calculate the retention rate of customers who placed at least one repeat order??

WITH customer_orders AS (
    SELECT
        "Customer_ID",
        COUNT("Order_ID") AS total_orders
    FROM customers
    GROUP BY "Customer_ID"
),
retention_summary AS (
    SELECT
        COUNT(*) AS total_customers,
        COUNT(CASE WHEN total_orders > 1 THEN 1 END) AS retained_customers
    FROM customer_orders
)
SELECT
    retained_customers,
    total_customers,
    ROUND(
        (retained_customers::DECIMAL / total_customers) * 100,
        2
    ) AS retention_rate_percentage
FROM retention_summary;

--For each customer’s first purchase month, calculate how many customers returned in subsequent months (cohort analysis)??

WITH first_purchase AS (
    SELECT
        "Customer_ID",
        DATE_TRUNC('month', MIN("Date")) AS cohort_month
    FROM customers
    GROUP BY "Customer_ID"
),
customer_orders AS (
    SELECT
        c."Customer_ID",
        DATE_TRUNC('month', c."Date") AS order_month,
        fp.cohort_month
    FROM customers c
    JOIN first_purchase fp
        ON c."Customer_ID" = fp."Customer_ID"
),
cohort_indexed AS (
    SELECT
        cohort_month,
        order_month,
        EXTRACT(
            YEAR FROM AGE(order_month, cohort_month)
        ) * 12
        +
        EXTRACT(
            MONTH FROM AGE(order_month, cohort_month)
        ) AS month_number,
        "Customer_ID"
    FROM customer_orders
)
SELECT
    cohort_month,
    month_number,
    COUNT(DISTINCT "Customer_ID") AS returning_customers
FROM cohort_indexed
GROUP BY cohort_month, month_number
ORDER BY cohort_month, month_number;

--Compute month-over-month revenue growth using window functions??

WITH monthly_revenue AS (
    SELECT
        DATE_TRUNC('month', "Date") AS month,
        SUM("Total_Amount") AS revenue
    FROM customers
    GROUP BY DATE_TRUNC('month', "Date")
)
SELECT
    month,
    revenue,
    LAG(revenue) OVER (ORDER BY month) AS previous_month_revenue,
    ROUND(
        (
            (revenue - LAG(revenue) OVER (ORDER BY month))
            / LAG(revenue) OVER (ORDER BY month)
        )::NUMERIC * 100,
        2
    ) AS mom_growth_percentage
FROM monthly_revenue
ORDER BY month;

--Calculate a rolling 3-month average of total revenue??

WITH monthly_revenue AS (
    SELECT
        DATE_TRUNC('month', "Date") AS month,
        SUM("Total_Amount")::NUMERIC AS monthly_revenue
    FROM customers
    GROUP BY DATE_TRUNC('month', "Date")
)
SELECT
    month,
    monthly_revenue,
    ROUND(
        AVG(monthly_revenue) OVER (
            ORDER BY month
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ),
        2
    ) AS rolling_3_month_avg_revenue
FROM monthly_revenue
ORDER BY month;

--Identify customers who made only one purchase and never returned.

SELECT
    "Customer_ID",
    COUNT("Order_ID") AS total_orders
FROM customers
GROUP BY "Customer_ID"
HAVING COUNT("Order_ID") = 1
ORDER BY "Customer_ID";

--For each customer, calculate the time gap between consecutive orders and identify customers with increasing gaps??

WITH order_gaps AS (
    SELECT
        "Customer_ID",
        "Date",
        "Date" - LAG("Date") OVER (
            PARTITION BY "Customer_ID"
            ORDER BY "Date"
        ) AS gap_between_orders
    FROM customers
),
gap_comparison AS (
    SELECT
        "Customer_ID",
        "Date",
        EXTRACT(DAY FROM gap_between_orders) AS gap_days,
        LAG(EXTRACT(DAY FROM gap_between_orders)) OVER (
            PARTITION BY "Customer_ID"
            ORDER BY "Date"
        ) AS previous_gap_days
    FROM order_gaps
)
SELECT
    "Customer_ID",
    "Date",
    gap_days,
    previous_gap_days
FROM gap_comparison
WHERE previous_gap_days IS NOT NULL
  AND gap_days > previous_gap_days
ORDER BY "Customer_ID", "Date";

--Recommend the top product category for each customer based on their historical purchases??

WITH category_stats AS (
    SELECT
        "Customer_ID",
        "Product_Category",
        COUNT("Order_ID") AS order_count,
        SUM("Total_Amount")::NUMERIC AS total_spent
    FROM customers
    GROUP BY "Customer_ID", "Product_Category"
),
ranked_categories AS (
    SELECT
        "Customer_ID",
        "Product_Category",
        order_count,
        total_spent,
        ROW_NUMBER() OVER (
            PARTITION BY "Customer_ID"
            ORDER BY order_count DESC, total_spent DESC
        ) AS rn
    FROM category_stats
)
SELECT
    "Customer_ID",
    "Product_Category" AS recommended_category,
    order_count,
    total_spent
FROM ranked_categories
WHERE rn = 1
ORDER BY "Customer_ID";

--Identify pairs of product categories frequently purchased by the same customers.??

WITH customer_categories AS (
    SELECT DISTINCT
        "Customer_ID",
        "Product_Category"
    FROM customers
),
category_pairs AS (
    SELECT
        c1."Product_Category" AS category_1,
        c2."Product_Category" AS category_2,
        c1."Customer_ID"
    FROM customer_categories c1
    JOIN customer_categories c2
        ON c1."Customer_ID" = c2."Customer_ID"
       AND c1."Product_Category" < c2."Product_Category"
)
SELECT
    category_1,
    category_2,
    COUNT(DISTINCT "Customer_ID") AS common_customers
FROM category_pairs
GROUP BY category_1, category_2
ORDER BY common_customers DESC;

--For each city, calculate the average delivery time and the percentage of late deliveries??

WITH city_delivery AS (
    SELECT
        "City",
        "Delivery_Time_Days",
        CASE
            WHEN "Delivery_Time_Days" > 7 THEN 1
            ELSE 0
        END AS is_late
    FROM customers
)
SELECT
    "City",
    ROUND(AVG("Delivery_Time_Days")::NUMERIC, 2) AS avg_delivery_time_days,
    ROUND(
        (SUM(is_late)::NUMERIC / COUNT(*)::NUMERIC) * 100,
        2
    ) AS late_delivery_percentage
FROM city_delivery
GROUP BY "City"
ORDER BY late_delivery_percentage DESC;

--Analyze the relationship between delivery time and customer ratings at a city level??

SELECT
    "City",
    ROUND(AVG("Delivery_Time_Days")::NUMERIC, 2) AS avg_delivery_time_days,
    ROUND(AVG("Customer_Rating")::NUMERIC, 2) AS avg_customer_rating,
    COUNT("Order_ID") AS total_orders
FROM customers
GROUP BY "City"
HAVING COUNT("Order_ID") >= 10
ORDER BY avg_delivery_time_days DESC;

--Identify cities with high order volume but low average ratings??

WITH city_metrics AS (
    SELECT
        "City",
        COUNT("Order_ID") AS total_orders,
        AVG("Customer_Rating")::NUMERIC AS avg_rating
    FROM customers
    GROUP BY "City"
),
benchmarks AS (
    SELECT
        AVG(total_orders)::NUMERIC AS avg_orders_benchmark,
        AVG(avg_rating)::NUMERIC AS avg_rating_benchmark
    FROM city_metrics
)
SELECT
    cm."City",
    cm.total_orders,
    ROUND(cm.avg_rating, 2) AS avg_rating
FROM city_metrics cm
CROSS JOIN benchmarks b
WHERE cm.total_orders > b.avg_orders_benchmark
  AND cm.avg_rating < b.avg_rating_benchmark
ORDER BY cm.total_orders DESC;


--Calculate the churn rate based on customers inactive for more than a defined period??
WITH max_date AS (
    SELECT MAX("Date") AS reference_date
    FROM customers
),
customer_activity AS (
    SELECT
        c."Customer_ID",
        EXTRACT(
            DAY FROM md.reference_date - MAX(c."Date")
        ) AS recency_days
    FROM customers c
    CROSS JOIN max_date md
    GROUP BY c."Customer_ID", md.reference_date
),
churn_summary AS (
    SELECT
        COUNT(*) AS total_customers,
        COUNT(
            CASE
                WHEN recency_days > 90 THEN 1
            END
        ) AS churned_customers
    FROM customer_activity
)
SELECT
    churned_customers,
    total_customers,
    ROUND(
        (churned_customers::NUMERIC / total_customers::NUMERIC) * 100,
        2
    ) AS churn_rate_percentage
FROM churn_summary;


--Compare CLV of returning vs non-returning customers??

WITH customer_clv AS (
    SELECT
        "Customer_ID",
        CASE
            WHEN COUNT("Order_ID") > 1 THEN 'Returning'
            ELSE 'Non-Returning'
        END AS customer_type,
        SUM("Total_Amount")::NUMERIC AS clv
    FROM customers
    GROUP BY "Customer_ID"
)
SELECT
    customer_type,
    COUNT("Customer_ID") AS total_customers,
    ROUND(AVG(clv), 2) AS avg_clv,
    ROUND(SUM(clv), 2) AS total_clv
FROM customer_clv
GROUP BY customer_type;


--Rank customers within each city based on lifetime value??

WITH customer_clv AS (
    SELECT
        "Customer_ID",
        "City",
        SUM("Total_Amount")::NUMERIC AS lifetime_value
    FROM customers
    GROUP BY "Customer_ID", "City"
)
SELECT
    "City",
    "Customer_ID",
    lifetime_value,
    RANK() OVER (
        PARTITION BY "City"
        ORDER BY lifetime_value DESC
    ) AS city_clv_rank
FROM customer_clv
ORDER BY "City", city_clv_rank;

--Identify customers whose spending trend is declining over their recent orders??

WITH ordered_spend AS (
    SELECT
        "Customer_ID",
        "Date",
        "Total_Amount",
        LAG("Total_Amount") OVER (
            PARTITION BY "Customer_ID"
            ORDER BY "Date"
        ) AS prev_amount
    FROM customers
),
declining_orders AS (
    SELECT
        "Customer_ID",
        "Date",
        "Total_Amount",
        prev_amount
    FROM ordered_spend
    WHERE prev_amount IS NOT NULL
      AND "Total_Amount" < prev_amount
)
SELECT
    "Customer_ID",
    COUNT(*) AS declining_order_count
FROM declining_orders
GROUP BY "Customer_ID"
HAVING COUNT(*) >= 2
ORDER BY declining_order_count DESC;

SELECT
    COUNT(DISTINCT "Customer_ID") AS total_customers,
    COUNT(DISTINCT CASE WHEN "Is_Returning_Customer" = true THEN "Customer_ID" END) AS returning_customers
FROM customers;


























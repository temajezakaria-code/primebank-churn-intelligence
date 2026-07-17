-- =============================================================================
-- PrimeBank Customer Retention Intelligence — SQL Analysis
-- 8 queries covering segmentation, risk scoring, and churn-driver analysis.
-- Tested and verified against primebank.db (SQLite).
-- =============================================================================

-- =============================================================================
-- QUERY 1: CHURN RATE BY GEOGRAPHY, RANKED
-- Techniques: aggregate functions, window function (RANK)
-- =============================================================================
-- WHY: The single highest-level question retention leadership asks first —
-- "where are we losing customers fastest?" Ranking (not just listing) makes
-- the worst-performing market immediately obvious.
-- BUSINESS VALUE: Directly informs where to prioritize a retention campaign
-- budget geographically.
-- =============================================================================
SELECT
    geography,
    COUNT(*)                                              AS total_customers,
    SUM(exited)                                            AS churned_customers,
    ROUND(SUM(exited) * 100.0 / COUNT(*), 2)                AS churn_rate_pct,
    RANK() OVER (ORDER BY SUM(exited) * 1.0 / COUNT(*) DESC) AS churn_risk_rank
FROM customers
GROUP BY geography
ORDER BY churn_rate_pct DESC;


-- =============================================================================
-- QUERY 2: CHURN RATE BY NUMBER OF PRODUCTS HELD (CASE BUCKETING)
-- Techniques: CASE, aggregate functions
-- =============================================================================
-- WHY: Product depth has a famously non-linear relationship with churn in this
-- kind of data — customers with too FEW or too MANY products both churn more.
-- CASE bucketing surfaces that pattern instead of a flat correlation number.
-- BUSINESS VALUE: Tells product/cross-sell teams the "sweet spot" number of
-- products to cross-sell toward, and flags 3-4 product holders as a hidden
-- risk segment worth investigating (often counter-intuitive to leadership).
-- =============================================================================
SELECT
    num_products,
    CASE
        WHEN num_products = 1 THEN 'Single product — under-engaged'
        WHEN num_products = 2 THEN 'Two products — healthy'
        ELSE '3+ products — red flag segment'
    END AS product_segment,
    COUNT(*)                                   AS customers,
    SUM(exited)                                 AS churned,
    ROUND(SUM(exited) * 100.0 / COUNT(*), 2)     AS churn_rate_pct
FROM customers
GROUP BY num_products
ORDER BY num_products;


-- =============================================================================
-- QUERY 3: CUSTOMER VALUE QUARTILES VS. CHURN RATE (RFM-STYLE, NO TRANSACTIONS)
-- Techniques: CTE, window function (NTILE), aggregate
-- =============================================================================
-- WHY: Without transaction history, account balance is the best available
-- proxy for customer value. Quartiling (not fixed thresholds) keeps this
-- robust regardless of the underlying balance distribution.
-- BUSINESS VALUE: Answers "are we losing our most valuable customers, or our
-- least valuable ones?" — a materially different retention strategy follows
-- from each answer.
-- =============================================================================
WITH value_quartiles AS (
    SELECT
        customer_id, balance, exited,
        NTILE(4) OVER (ORDER BY balance) AS value_quartile
    FROM customers
)
SELECT
    value_quartile,
    CASE value_quartile WHEN 1 THEN 'Lowest balance' WHEN 4 THEN 'Highest balance' ELSE 'Mid-tier' END AS segment_label,
    COUNT(*)                               AS customers,
    ROUND(AVG(balance), 2)                 AS avg_balance,
    SUM(exited)                             AS churned,
    ROUND(SUM(exited) * 100.0 / COUNT(*), 2) AS churn_rate_pct
FROM value_quartiles
GROUP BY value_quartile
ORDER BY value_quartile;


-- =============================================================================
-- QUERY 4: TENURE-BASED RETENTION CURVE
-- Techniques: aggregate, CASE, date/tenure analysis
-- =============================================================================
-- WHY: Approximates a survival/retention curve using tenure_years as a proxy
-- for "how long since acquisition" — the closest thing to cohort analysis
-- this snapshot (non-transactional) dataset supports.
-- BUSINESS VALUE: Identifies the specific tenure window where churn risk
-- peaks, so retention outreach can be timed around that window rather than
-- applied uniformly across the whole customer base.
-- =============================================================================
SELECT
    tenure_years,
    COUNT(*)                                 AS customers,
    SUM(exited)                               AS churned,
    ROUND(SUM(exited) * 100.0 / COUNT(*), 2)   AS churn_rate_pct
FROM customers
GROUP BY tenure_years
ORDER BY tenure_years;


-- =============================================================================
-- QUERY 5: COMPOUND RISK SCORE (MULTI-FACTOR CASE LOGIC)
-- Techniques: CASE, CTE, subquery, aggregate
-- =============================================================================
-- WHY: No single factor predicts churn well alone: this builds a simple,
-- fully transparent point-based risk score directly in SQL — the kind of
-- interim business rule a retention team could deploy immediately, even
-- before a machine learning model is built and approved.
-- BUSINESS VALUE: A rule-based scorecard that ops/retention teams can
-- action on day one, and a natural baseline to later compare the ML model
-- against ("did the model actually beat simple business rules?").
-- =============================================================================
WITH risk_scored AS (
    SELECT
        customer_id, geography, age, num_products, is_active_member, exited,
        (CASE WHEN is_active_member = 0 THEN 2 ELSE 0 END) +
        (CASE WHEN num_products >= 3 THEN 2 ELSE 0 END) +
        (CASE WHEN age >= 50 THEN 1 ELSE 0 END) +
        (CASE WHEN geography = 'Germany' THEN 1 ELSE 0 END) AS risk_score
    FROM customers
)
SELECT
    risk_score,
    COUNT(*)                                 AS customers,
    SUM(exited)                               AS churned,
    ROUND(SUM(exited) * 100.0 / COUNT(*), 2)   AS churn_rate_pct
FROM risk_scored
GROUP BY risk_score
ORDER BY risk_score DESC;


-- =============================================================================
-- QUERY 6: INACTIVE MEMBER FLAG — SIMPLE HIGH-SIGNAL CHECK
-- Techniques: CASE, aggregate
-- =============================================================================
-- WHY: Tests the single strongest simple predictor before layering complexity —
-- good analytical discipline is checking the easy signal before reaching for
-- multi-factor scores.
-- BUSINESS VALUE: If activity status alone separates churn risk this cleanly,
-- it justifies an immediate, low-cost intervention (a re-engagement email
-- trigger) that doesn't require waiting on a full ML model to ship.
-- =============================================================================
SELECT
    CASE WHEN is_active_member = 1 THEN 'Active' ELSE 'Inactive' END AS activity_status,
    COUNT(*)                                 AS customers,
    SUM(exited)                               AS churned,
    ROUND(SUM(exited) * 100.0 / COUNT(*), 2)   AS churn_rate_pct
FROM customers
GROUP BY is_active_member
ORDER BY churn_rate_pct DESC;


-- =============================================================================
-- QUERY 7: TOP 100 HIGHEST-VALUE AT-RISK CUSTOMERS (RANKING + FILTERING)
-- Techniques: window function (ROW_NUMBER), subquery, filtering
-- =============================================================================
-- WHY: Translates analysis into an actioned list — exactly the kind of output
-- a retention team would load into their CRM outreach queue today.
-- BUSINESS VALUE: This is the query that turns "insight" into "action" —
-- it's a ready-to-use target list, not just a statistic.
-- =============================================================================
SELECT * FROM (
    SELECT
        customer_id, geography, balance, num_products, is_active_member,
        ROW_NUMBER() OVER (ORDER BY balance DESC) AS value_rank
    FROM customers
    WHERE is_active_member = 0 AND num_products >= 2  -- proxy "at risk" filter
) ranked
WHERE value_rank <= 100;


-- =============================================================================
-- QUERY 8: GENDER x GEOGRAPHY CHURN CROSS-TAB
-- Techniques: CASE, aggregate, multi-dimensional GROUP BY
-- =============================================================================
-- WHY: Checks for an interaction effect (does the geography effect differ by
-- gender?) rather than assuming each dimension acts independently — a common
-- oversimplification in single-variable analysis.
-- BUSINESS VALUE: If the pattern differs by gender within a region, a single
-- generic regional campaign would be less effective than a segmented one.
-- =============================================================================
SELECT
    geography,
    gender,
    COUNT(*)                                 AS customers,
    SUM(exited)                               AS churned,
    ROUND(SUM(exited) * 100.0 / COUNT(*), 2)   AS churn_rate_pct
FROM customers
GROUP BY geography, gender
ORDER BY geography, gender;

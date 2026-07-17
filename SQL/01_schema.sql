-- =============================================================================
-- PrimeBank Customer Retention Intelligence — Database Schema
-- =============================================================================
-- Source: public bank customer churn dataset (10,000 customers, 3 markets:
-- France, Germany, Spain). Grain: one row per customer (snapshot, not
-- transactional) — this is a customer master table with a churn outcome flag,
-- not a star schema, since the source data has no transaction-level history.
-- =============================================================================

CREATE TABLE customers (
    customer_id       INTEGER PRIMARY KEY,   -- unique bank customer ID
    credit_score      INTEGER NOT NULL,      -- 300-850 credit score
    geography         VARCHAR(20) NOT NULL,  -- France / Germany / Spain
    gender            VARCHAR(10) NOT NULL,
    age               INTEGER NOT NULL,
    tenure_years      INTEGER NOT NULL,      -- years as a bank customer
    balance           DECIMAL(12,2) NOT NULL,-- account balance
    num_products      INTEGER NOT NULL,      -- number of bank products held (1-4)
    has_credit_card   BOOLEAN NOT NULL,
    is_active_member  BOOLEAN NOT NULL,      -- bank's own activity flag
    estimated_salary  DECIMAL(12,2) NOT NULL,
    exited            BOOLEAN NOT NULL       -- TARGET: did the customer churn?
);

CREATE INDEX idx_customers_geography ON customers(geography);
CREATE INDEX idx_customers_exited ON customers(exited);
CREATE INDEX idx_customers_products ON customers(num_products);

-- =============================================================================
-- Note: RowNumber (a load artifact) and Surname (customer PII, even if
-- fictional test data) were dropped during loading — never included here.
-- =============================================================================

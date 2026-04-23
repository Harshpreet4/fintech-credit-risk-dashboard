-- ================================================================
-- 07_CREATE_STAR_SCHEMA.SQL
-- Fintech Credit Risk & Collections Intelligence Dashboard
-- Author: Harshpreet Kour
-- Description: Creates all dimension and fact tables for the
--              star schema data warehouse and loads data from
--              loan_data.csv
-- ================================================================

USE fintech_credit_db;
GO

-- ================================================================
-- STEP 1: DROP TABLES IF THEY EXIST (clean slate every time)
-- ================================================================

IF OBJECT_ID('fact_loan_payments', 'U') IS NOT NULL DROP TABLE fact_loan_payments;
IF OBJECT_ID('dim_customer',       'U') IS NOT NULL DROP TABLE dim_customer;
IF OBJECT_ID('dim_product',        'U') IS NOT NULL DROP TABLE dim_product;
IF OBJECT_ID('dim_date',           'U') IS NOT NULL DROP TABLE dim_date;
IF OBJECT_ID('dim_branch',         'U') IS NOT NULL DROP TABLE dim_branch;
IF OBJECT_ID('loan_data_staging',  'U') IS NOT NULL DROP TABLE loan_data_staging;
GO

-- ================================================================
-- STEP 2: CREATE STAGING TABLE (raw CSV data lands here first)
-- ================================================================

CREATE TABLE loan_data_staging (
    loan_id           VARCHAR(20),
    customer_id       VARCHAR(20),
    customer_name     VARCHAR(100),
    age               INT,
    gender            VARCHAR(10),
    city              VARCHAR(50),
    product_type      VARCHAR(50),
    loan_amount       FLOAT,
    interest_rate     FLOAT,
    tenure_months     INT,
    disbursement_date DATE,
    due_date          DATE,
    payment_date      DATE NULL,
    emi_amount        FLOAT,
    amount_paid       FLOAT,
    dpd               INT,
    branch_id         VARCHAR(10),
    branch_name       VARCHAR(100),
    agent_id          VARCHAR(20),
    agent_name        VARCHAR(100),
    loan_status       VARCHAR(20)
);
GO

-- ================================================================
-- STEP 3: LOAD CSV INTO STAGING TABLE
-- ================================================================

BULK INSERT loan_data_staging
FROM 'C:/Users/hkour/Desktop/fintech-credit-risk-dashboard/data/loan_data.csv'
WITH (
    FIRSTROW        = 2,          -- Skip header row
    FIELDTERMINATOR = ',',        -- CSV comma separator
    ROWTERMINATOR   = '\n',       -- New line per row
    TABLOCK                       -- Lock table for faster load
);
GO

-- Verify staging load
SELECT COUNT(*) AS staging_row_count FROM loan_data_staging;
-- Expected: 5000
GO

-- ================================================================
-- STEP 4: CREATE DIMENSION TABLES
-- ================================================================

-- ── dim_customer ─────────────────────────────────────────────────
CREATE TABLE dim_customer (
    customer_id    VARCHAR(20)  NOT NULL,
    customer_name  VARCHAR(100) NOT NULL,
    age            INT          NOT NULL,
    gender         VARCHAR(10)  NOT NULL,
    city           VARCHAR(50)  NOT NULL,
    CONSTRAINT PK_dim_customer PRIMARY KEY (customer_id)
);
GO

-- ── dim_product ──────────────────────────────────────────────────
CREATE TABLE dim_product (
    product_id     INT          NOT NULL IDENTITY(1,1),
    product_type   VARCHAR(50)  NOT NULL,
    risk_category  VARCHAR(20)  NOT NULL,
    CONSTRAINT PK_dim_product PRIMARY KEY (product_id)
);
GO

-- ── dim_branch ───────────────────────────────────────────────────
CREATE TABLE dim_branch (
    branch_id    VARCHAR(10)  NOT NULL,
    branch_name  VARCHAR(100) NOT NULL,
    region       VARCHAR(20)  NOT NULL,
    CONSTRAINT PK_dim_branch PRIMARY KEY (branch_id)
);
GO

-- ── dim_date ─────────────────────────────────────────────────────
CREATE TABLE dim_date (
    date_id     INT         NOT NULL,
    full_date   DATE        NOT NULL,
    day         INT         NOT NULL,
    month       INT         NOT NULL,
    month_name  VARCHAR(20) NOT NULL,
    quarter     INT         NOT NULL,
    year        INT         NOT NULL,
    is_weekend  BIT         NOT NULL,
    CONSTRAINT PK_dim_date PRIMARY KEY (date_id)
);
GO

-- ── fact_loan_payments ───────────────────────────────────────────
CREATE TABLE fact_loan_payments (
    loan_id              VARCHAR(20)  NOT NULL,
    customer_id          VARCHAR(20)  NOT NULL,
    product_id           INT          NOT NULL,
    branch_id            VARCHAR(10)  NOT NULL,
    due_date_id          INT          NOT NULL,
    disbursement_date_id INT          NOT NULL,
    loan_amount          FLOAT        NOT NULL,
    emi_amount           FLOAT        NOT NULL,
    amount_paid          FLOAT        NOT NULL,
    dpd                  INT          NOT NULL,
    loan_status          VARCHAR(20)  NOT NULL,
    agent_id             VARCHAR(20)  NOT NULL,
    agent_name           VARCHAR(100) NOT NULL,
    CONSTRAINT PK_fact_loan_payments PRIMARY KEY (loan_id),
    CONSTRAINT FK_fact_customer  FOREIGN KEY (customer_id)          REFERENCES dim_customer(customer_id),
    CONSTRAINT FK_fact_product   FOREIGN KEY (product_id)           REFERENCES dim_product(product_id),
    CONSTRAINT FK_fact_branch    FOREIGN KEY (branch_id)            REFERENCES dim_branch(branch_id),
    CONSTRAINT FK_fact_due_date  FOREIGN KEY (due_date_id)          REFERENCES dim_date(date_id),
    CONSTRAINT FK_fact_disb_date FOREIGN KEY (disbursement_date_id) REFERENCES dim_date(date_id)
);
GO

-- ================================================================
-- STEP 5: POPULATE DIMENSION TABLES FROM STAGING
-- ================================================================

-- ── Populate dim_customer ────────────────────────────────────────
-- DISTINCT ensures one row per customer even if they have
-- multiple loans in the dataset
INSERT INTO dim_customer (customer_id, customer_name, age, gender, city)
SELECT
    customer_id,
    customer_name,
    age,
    gender,
    city
FROM (
    SELECT
        customer_id,
        customer_name,
        age,
        gender,
        city,
        ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY loan_id) AS rn
    FROM loan_data_staging
) ranked
WHERE rn = 1;
GO

-- ── Populate dim_product ─────────────────────────────────────────
-- Manually insert 5 product types with risk categories
-- Risk category is business logic — not in raw data
INSERT INTO dim_product (product_type, risk_category)
VALUES
    ('Personal Loan', 'High'),
    ('Auto Loan',     'Medium'),
    ('Home Loan',     'Low'),
    ('Business Loan', 'High'),
    ('Gold Loan',     'Medium');
GO

SELECT COUNT(*) AS dim_product_count FROM dim_product;
GO

-- ── Populate dim_branch ──────────────────────────────────────────
-- Assign regions based on city geography
INSERT INTO dim_branch (branch_id, branch_name, region)
VALUES
    ('BR-01', 'Mumbai Central', 'West'),
    ('BR-02', 'Delhi North',    'North'),
    ('BR-03', 'Bangalore East', 'South'),
    ('BR-04', 'Chennai South',  'South'),
    ('BR-05', 'Hyderabad West', 'South'),
    ('BR-06', 'Pune Central',   'West'),
    ('BR-07', 'Kolkata North',  'East'),
    ('BR-08', 'Ahmedabad East', 'West'),
    ('BR-09', 'Mumbai West',    'West'),
    ('BR-10', 'Delhi South',    'North');
GO

SELECT COUNT(*) AS dim_branch_count FROM dim_branch;
GO

-- ── Populate dim_date ────────────────────────────────────────────
-- Generate one row for every date between Jan 2022 and Dec 2024
-- This covers all disbursement and due dates in the dataset
WITH date_sequence AS (
    SELECT CAST('2022-01-01' AS DATE) AS full_date
    UNION ALL
    SELECT DATEADD(DAY, 1, full_date)
    FROM date_sequence
    WHERE full_date < '2024-12-31'
)
INSERT INTO dim_date (date_id, full_date, day, month, month_name, quarter, year, is_weekend)
SELECT
    CAST(CONVERT(VARCHAR, full_date, 112) AS INT) AS date_id,
    full_date,
    DAY(full_date)                                AS day,
    MONTH(full_date)                              AS month,
    DATENAME(MONTH, full_date)                    AS month_name,
    DATEPART(QUARTER, full_date)                  AS quarter,
    YEAR(full_date)                               AS year,
    CASE WHEN DATEPART(WEEKDAY, full_date)
         IN (1, 7) THEN 1 ELSE 0 END              AS is_weekend
FROM date_sequence
OPTION (MAXRECURSION 1500);
GO

SELECT COUNT(*) AS dim_date_count FROM dim_date;
-- Expected: ~1095 rows (3 years of dates)
GO

-- ================================================================
-- STEP 6: POPULATE FACT TABLE
-- ================================================================

INSERT INTO fact_loan_payments (
    loan_id,
    customer_id,
    product_id,
    branch_id,
    due_date_id,
    disbursement_date_id,
    loan_amount,
    emi_amount,
    amount_paid,
    dpd,
    loan_status,
    agent_id,
    agent_name
)
SELECT
    s.loan_id,
    s.customer_id,
    p.product_id,
    s.branch_id,
    CAST(CONVERT(VARCHAR, s.due_date, 112) AS INT)           AS due_date_id,
    CAST(CONVERT(VARCHAR, s.disbursement_date, 112) AS INT)  AS disbursement_date_id,
    s.loan_amount,
    s.emi_amount,
    s.amount_paid,
    s.dpd,
    s.loan_status,
    s.agent_id,
    s.agent_name
FROM loan_data_staging s
JOIN dim_product p ON s.product_type = p.product_type;
GO

SELECT COUNT(*) AS fact_row_count FROM fact_loan_payments;
-- Expected: 5000
GO

-- ================================================================
-- STEP 7: FINAL VERIFICATION — ALL TABLE ROW COUNTS
-- ================================================================

SELECT 'dim_customer'      AS table_name, COUNT(*) AS row_count FROM dim_customer
UNION ALL
SELECT 'dim_product',                     COUNT(*)              FROM dim_product
UNION ALL
SELECT 'dim_branch',                      COUNT(*)              FROM dim_branch
UNION ALL
SELECT 'dim_date',                        COUNT(*)              FROM dim_date
UNION ALL
SELECT 'fact_loan_payments',              COUNT(*)              FROM fact_loan_payments;
GO

-- ================================================================
-- STEP 8: SAMPLE DATA CHECK — MAKE SURE JOINS WORK
-- ================================================================

SELECT TOP 10
    f.loan_id,
    c.customer_name,
    c.city,
    p.product_type,
    p.risk_category,
    b.branch_name,
    b.region,
    d.month_name,
    d.year,
    f.loan_amount,
    f.dpd,
    f.loan_status
FROM fact_loan_payments   f
JOIN dim_customer         c ON f.customer_id = c.customer_id
JOIN dim_product          p ON f.product_id  = p.product_id
JOIN dim_branch           b ON f.branch_id   = b.branch_id
JOIN dim_date             d ON f.due_date_id = d.date_id;
GO
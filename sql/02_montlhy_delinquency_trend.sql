-- ================================================================
-- 02_MONTHLY_DELINQUENCY_TREND.SQL
-- Fintech Credit Risk & Collections Intelligence Dashboard
-- Author: Harshpreet Kour
-- Description: Tracks delinquency rate month over month across
--              the entire portfolio. Uses CTE for monthly
--              aggregation and LAG() window function to calculate
--              month over month change in delinquency rate.
-- ================================================================

USE fintech_credit_db;
GO

-- ================================================================
-- QUERY 2A: MONTHLY DELINQUENCY TREND — FULL PORTFOLIO
-- ================================================================
WITH monthly_summary AS (
    SELECT
        YEAR(d.full_date)                            AS yr,
        MONTH(d.full_date)                           AS mth,

        -- Create display label like "2022-01", "2022-02" etc.
        CAST(YEAR(d.full_date) AS VARCHAR(4))
        + '-'
        + RIGHT('0' + CAST(MONTH(d.full_date) AS VARCHAR(2)), 2)
                                                     AS year_month,

        COUNT(f.loan_id)                             AS total_loans,

        -- Count loans where DPD > 0 as delinquent
        SUM(CASE WHEN f.dpd > 0 THEN 1 ELSE 0 END)  AS delinquent_loans,

        -- Total portfolio value this month
        SUM(f.loan_amount)                           AS total_exposure,

        -- Delinquent exposure = loans at risk
        SUM(CASE WHEN f.dpd > 0
            THEN f.loan_amount ELSE 0 END)           AS delinquent_exposure

    FROM fact_loan_payments f
    JOIN dim_date           d ON f.due_date_id = d.date_id

    GROUP BY
        YEAR(d.full_date),
        MONTH(d.full_date),
        CAST(YEAR(d.full_date) AS VARCHAR(4))
        + '-'
        + RIGHT('0' + CAST(MONTH(d.full_date) AS VARCHAR(2)), 2)

),

monthly_with_rates AS (

    -- Step 2: Calculate rates and apply LAG() window function
    -- LAG() looks back 1 row (previous month) to get prior rate
    -- OVER (ORDER BY yr, mth) ensures correct chronological order

    SELECT
        year_month,
        yr,
        mth,
        total_loans,
        delinquent_loans,
        total_exposure,
        delinquent_exposure,

        -- Delinquency rate = delinquent loans / total loans
        ROUND(
            delinquent_loans * 100.0 / NULLIF(total_loans, 0)
        , 2)                                         AS delinquency_rate_pct,

        -- PAR = delinquent exposure / total exposure
        ROUND(
            delinquent_exposure * 100.0 / NULLIF(total_exposure, 0)
        , 2)                                         AS par_pct,

        -- LAG() fetches the delinquency rate from the prior month
        -- The first month will show NULL — that is expected
        LAG(
            ROUND(delinquent_loans * 100.0 / NULLIF(total_loans, 0), 2)
        , 1) OVER (ORDER BY yr, mth)                 AS prev_month_rate

    FROM monthly_summary

)

-- ── Main SELECT ──────────────────────────────────────────────────
SELECT
    year_month,
    total_loans,
    delinquent_loans,
    delinquency_rate_pct,
    par_pct,
    prev_month_rate,

    -- Month over month change in delinquency rate
    -- NULL for first month since there is no prior month
    -- Positive = delinquency getting worse
    -- Negative = delinquency improving
    ROUND(
        delinquency_rate_pct - ISNULL(prev_month_rate, delinquency_rate_pct)
    , 2)                                             AS mom_change_pct,

    -- Direction label for dashboard tooltip
    CASE
        WHEN prev_month_rate IS NULL                         THEN 'Baseline'
        WHEN delinquency_rate_pct > prev_month_rate          THEN 'Worsening'
        WHEN delinquency_rate_pct < prev_month_rate          THEN 'Improving'
        ELSE                                                      'Stable'
    END                                              AS trend_direction

FROM monthly_with_rates

ORDER BY yr, mth;
GO

-- ================================================================
-- QUERY 2B: QUARTERLY DELINQUENCY SUMMARY
-- ================================================================
WITH quarterly_summary AS (

    SELECT
        YEAR(d.full_date)                            AS yr,
        DATEPART(QUARTER, d.full_date)               AS qtr,

        -- Create display label like "2022-Q1", "2022-Q2" etc.
        CAST(YEAR(d.full_date) AS VARCHAR(4))
        + '-Q'
        + CAST(DATEPART(QUARTER, d.full_date) AS VARCHAR(1))
                                                     AS year_quarter,

        COUNT(f.loan_id)                             AS total_loans,
        SUM(CASE WHEN f.dpd > 0 THEN 1 ELSE 0 END)  AS delinquent_loans,
        SUM(CASE WHEN f.dpd >= 91 THEN 1 ELSE 0 END) AS npa_loans,
        SUM(f.loan_amount)                           AS total_exposure,
        SUM(CASE WHEN f.dpd > 0
            THEN f.loan_amount ELSE 0 END)           AS delinquent_exposure

    FROM fact_loan_payments f
    JOIN dim_date           d ON f.due_date_id = d.date_id

    GROUP BY
        YEAR(d.full_date),
        DATEPART(QUARTER, d.full_date),
        CAST(YEAR(d.full_date) AS VARCHAR(4))
        + '-Q'
        + CAST(DATEPART(QUARTER, d.full_date) AS VARCHAR(1))

)

SELECT
    year_quarter,
    total_loans,
    delinquent_loans,
    npa_loans,
    ROUND(delinquent_loans * 100.0 / NULLIF(total_loans, 0), 2)   AS delinquency_rate_pct,
    ROUND(npa_loans        * 100.0 / NULLIF(total_loans, 0), 2)   AS npa_rate_pct,
    ROUND(delinquent_exposure * 100.0 / NULLIF(total_exposure, 0), 2) AS par_pct,

    -- Quarter over quarter delinquency change
    LAG(ROUND(delinquent_loans * 100.0 / NULLIF(total_loans, 0), 2), 1)
        OVER (ORDER BY yr, qtr)                                    AS prev_quarter_rate

FROM quarterly_summary

ORDER BY yr, qtr;
GO

-- ================================================================
-- QUERY 2C: WORST PERFORMING MONTHS
-- ================================================================
WITH monthly_rates AS (

    SELECT
        CAST(YEAR(d.full_date) AS VARCHAR(4))
        + '-'
        + RIGHT('0' + CAST(MONTH(d.full_date) AS VARCHAR(2)), 2) AS year_month,
        DATENAME(MONTH, d.full_date)                              AS month_name,
        YEAR(d.full_date)                                         AS yr,
        COUNT(f.loan_id)                                          AS total_loans,
        SUM(CASE WHEN f.dpd > 0 THEN 1 ELSE 0 END)               AS delinquent_loans,
        ROUND(
            SUM(CASE WHEN f.dpd > 0 THEN 1.0 ELSE 0 END)
            / NULLIF(COUNT(f.loan_id), 0) * 100
        , 2)                                                      AS delinquency_rate_pct

    FROM fact_loan_payments f
    JOIN dim_date           d ON f.due_date_id = d.date_id

    GROUP BY
        YEAR(d.full_date),
        MONTH(d.full_date),
        DATENAME(MONTH, d.full_date),
        CAST(YEAR(d.full_date) AS VARCHAR(4))
        + '-'
        + RIGHT('0' + CAST(MONTH(d.full_date) AS VARCHAR(2)), 2)

)

SELECT
    year_month,
    month_name,
    yr,
    total_loans,
    delinquent_loans,
    delinquency_rate_pct,
    RANK() OVER (ORDER BY delinquency_rate_pct DESC) AS worst_month_rank

FROM monthly_rates

ORDER BY delinquency_rate_pct DESC;
GO

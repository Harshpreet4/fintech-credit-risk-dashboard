-- ================================================================
-- 06_NPA_EARLY_WARNING.SQL
-- Fintech Credit Risk & Collections Intelligence Dashboard
-- Author: Harshpreet Kour
-- Description: Identifies all loans currently in SMA-2 bucket
--              (DPD 61-90) that are at immediate risk of becoming
--              NPA. Calculates days remaining before NPA threshold
--              and provides complete actionable list for the
--              collections team ordered by urgency.
-- ================================================================

USE fintech_credit_db;
GO

-- ================================================================
-- QUERY 6A: NPA EARLY WARNING 
-- ================================================================

WITH sma2_loans AS (


    SELECT
        f.loan_id,
        f.customer_id,
        f.branch_id,
        f.agent_id,
        f.agent_name,
        f.loan_amount,
        f.emi_amount,
        f.dpd,
        f.loan_status,
        f.due_date_id,

        -- days_to_npa = how many days before this loan hits 91 DPD
        (90 - f.dpd)                                 AS days_to_npa,

        CASE
            WHEN (90 - f.dpd) <= 5   THEN 'CRITICAL'   -- 5 days or less
            WHEN (90 - f.dpd) <= 15  THEN 'HIGH'        -- 6-15 days
            WHEN (90 - f.dpd) <= 25  THEN 'MEDIUM'      -- 16-25 days
            ELSE                          'WATCH'        -- 26-29 days
        END                                          AS urgency_tier

    FROM fact_loan_payments f

    WHERE f.dpd BETWEEN 61 AND 90   -- SMA-2 bucket only

),

sma2_enriched AS (

    SELECT
        s.loan_id,
        c.customer_name,
        c.city,
        c.age,
        c.gender,
        p.product_type,
        p.risk_category,
        b.branch_name,
        b.region,
        s.agent_id,
        s.agent_name,
        s.loan_amount,
        s.emi_amount,
        s.dpd,
        s.days_to_npa,
        s.urgency_tier,
        s.loan_status,

        ROUND(s.loan_amount * 0.60, 0)               AS potential_loss_if_npa

    FROM sma2_loans        s
    JOIN dim_customer      c ON s.customer_id = c.customer_id
    JOIN dim_product       p ON
        -- Join product via fact table
        s.loan_id IN (
            SELECT loan_id FROM fact_loan_payments
            WHERE product_id = p.product_id
        )
    JOIN dim_branch        b ON s.branch_id   = b.branch_id

)

SELECT
    loan_id,
    customer_name,
    city,
    product_type,
    risk_category,
    branch_name,
    region,
    agent_name,
    ROUND(loan_amount, 0)            AS loan_amount,
    ROUND(emi_amount, 0)             AS emi_amount,
    dpd,
    days_to_npa,
    urgency_tier,
    potential_loss_if_npa,
    loan_status

FROM sma2_enriched

ORDER BY days_to_npa ASC;
GO

-- ================================================================
-- QUERY 6B: SMA-2 SUMMARY BY BRANCH
-- ================================================================


SELECT
    b.branch_name,
    b.region,
    COUNT(f.loan_id)                                 AS sma2_loan_count,
    ROUND(SUM(f.loan_amount), 0)                     AS sma2_exposure,
    ROUND(AVG(CAST(f.dpd AS FLOAT)), 1)              AS avg_dpd,
    MIN(90 - f.dpd)                                  AS min_days_to_npa,
    MAX(90 - f.dpd)                                  AS max_days_to_npa,

    -- Critical loans (5 days or less to NPA)
    SUM(CASE WHEN (90 - f.dpd) <= 5
        THEN 1 ELSE 0 END)                           AS critical_count,

    -- Potential loss exposure assuming 40% recovery
    ROUND(SUM(f.loan_amount) * 0.60, 0)              AS potential_loss_exposure

FROM fact_loan_payments f
JOIN dim_branch         b ON f.branch_id = b.branch_id

WHERE f.dpd BETWEEN 61 AND 90

GROUP BY
    b.branch_name,
    b.region

ORDER BY sma2_exposure DESC;
GO

-- ================================================================
-- QUERY 6C: SMA-2 SUMMARY BY PRODUCT TYPE
-- ================================================================

SELECT
    p.product_type,
    p.risk_category,
    COUNT(f.loan_id)                                 AS sma2_loan_count,
    ROUND(SUM(f.loan_amount), 0)                     AS sma2_exposure,
    ROUND(AVG(CAST(f.dpd AS FLOAT)), 1)              AS avg_dpd,
    ROUND(AVG(90 - CAST(f.dpd AS FLOAT)), 1)         AS avg_days_to_npa,

    SUM(CASE WHEN (90 - f.dpd) <= 5
        THEN 1 ELSE 0 END)                           AS critical_count,

    ROUND(SUM(f.loan_amount) * 0.60, 0)              AS potential_loss_exposure

FROM fact_loan_payments f
JOIN dim_product        p ON f.product_id = p.product_id

WHERE f.dpd BETWEEN 61 AND 90

GROUP BY
    p.product_type,
    p.risk_category

ORDER BY sma2_exposure DESC;
GO

-- ================================================================
-- QUERY 6D: COMPLETE PORTFOLIO RISK SUMMARY
-- ================================================================

SELECT
    risk_tier,
    loan_count,
    ROUND(total_exposure, 0)         AS total_exposure,
    ROUND(avg_dpd, 1)                AS avg_dpd,
    ROUND(portfolio_share_pct, 1)    AS portfolio_share_pct,
    ROUND(exposure_share_pct, 1)     AS exposure_share_pct,
    action_required

FROM (

    SELECT
        CASE
            WHEN dpd = 0                THEN '1 - Current'
            WHEN dpd BETWEEN 1  AND 30  THEN '2 - SMA-0 Watch'
            WHEN dpd BETWEEN 31 AND 60  THEN '3 - SMA-1 Stressed'
            WHEN dpd BETWEEN 61 AND 90  THEN '4 - SMA-2 Critical'
            WHEN dpd >= 91              THEN '5 - NPA Loss Asset'
        END                                          AS risk_tier,

        COUNT(loan_id)                               AS loan_count,
        SUM(loan_amount)                             AS total_exposure,
        AVG(CAST(dpd AS FLOAT))                      AS avg_dpd,

        COUNT(loan_id) * 100.0
        / SUM(COUNT(loan_id)) OVER ()                AS portfolio_share_pct,

        SUM(loan_amount) * 100.0
        / SUM(SUM(loan_amount)) OVER ()              AS exposure_share_pct,

        CASE
            WHEN dpd = 0                THEN 'No action needed'
            WHEN dpd BETWEEN 1  AND 30  THEN 'Soft reminder calls'
            WHEN dpd BETWEEN 31 AND 60  THEN 'Field collection visit'
            WHEN dpd BETWEEN 61 AND 90  THEN 'URGENT - Legal notice + calls'
            WHEN dpd >= 91              THEN 'Legal recovery / write-off'
        END                                          AS action_required

    FROM fact_loan_payments

    GROUP BY
        CASE
            WHEN dpd = 0                THEN '1 - Current'
            WHEN dpd BETWEEN 1  AND 30  THEN '2 - SMA-0 Watch'
            WHEN dpd BETWEEN 31 AND 60  THEN '3 - SMA-1 Stressed'
            WHEN dpd BETWEEN 61 AND 90  THEN '4 - SMA-2 Critical'
            WHEN dpd >= 91              THEN '5 - NPA Loss Asset'
        END,
        CASE
            WHEN dpd = 0                THEN 'No action needed'
            WHEN dpd BETWEEN 1  AND 30  THEN 'Soft reminder calls'
            WHEN dpd BETWEEN 31 AND 60  THEN 'Field collection visit'
            WHEN dpd BETWEEN 61 AND 90  THEN 'URGENT - Legal notice + calls'
            WHEN dpd >= 91              THEN 'Legal recovery / write-off'
        END

) final_summary

ORDER BY risk_tier;
GO
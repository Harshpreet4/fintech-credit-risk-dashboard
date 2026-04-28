-- ================================================================
-- 04_BRANCH_COLLECTION_EFFICIENCY.SQL
-- Fintech Credit Risk & Collections Intelligence Dashboard
-- Author: Harshpreet Kour
-- Description: Ranks all branches by collection performance.
--              Calculates collection efficiency %, PAR % per
--              branch, and uses RANK() window function to identify
--              top and bottom performing branches.
-- ================================================================

USE fintech_credit_db;
GO

-- ================================================================
-- QUERY 4A: BRANCH COLLECTION EFFICIENCY RANKING
-- ================================================================

WITH branch_metrics AS (

    SELECT
        b.branch_id,
        b.branch_name,
        b.region,

        COUNT(f.loan_id)                             AS total_loans,

        SUM(CASE WHEN f.amount_paid > 0
            THEN 1 ELSE 0 END)                       AS collected_loans,

        SUM(CASE WHEN f.dpd > 0
            THEN 1 ELSE 0 END)                       AS delinquent_loans,

        SUM(CASE WHEN f.dpd >= 91
            THEN 1 ELSE 0 END)                       AS npa_loans,

        SUM(f.loan_amount)                           AS total_exposure,
        SUM(f.amount_paid)                           AS total_collected,
        SUM(f.emi_amount)                            AS total_emi_due,

        SUM(CASE WHEN f.dpd > 0
            THEN f.loan_amount ELSE 0 END)           AS delinquent_exposure,

        SUM(CASE WHEN f.dpd >= 91
            THEN f.loan_amount ELSE 0 END)           AS npa_exposure,

        AVG(CASE WHEN f.dpd > 0
            THEN CAST(f.dpd AS FLOAT) END)           AS avg_dpd_delinquent

    FROM fact_loan_payments f
    JOIN dim_branch         b ON f.branch_id = b.branch_id

    GROUP BY
        b.branch_id,
        b.branch_name,
        b.region

),

branch_with_rates AS (

    SELECT
        branch_id,
        branch_name,
        region,
        total_loans,
        collected_loans,
        delinquent_loans,
        npa_loans,
        total_exposure,
        total_collected,
        total_emi_due,
        delinquent_exposure,
        npa_exposure,
        ROUND(avg_dpd_delinquent, 1)                 AS avg_dpd_delinquent,

        ROUND(
            collected_loans * 100.0 / NULLIF(total_loans, 0)
        , 2)                                         AS collection_efficiency_pct,

        ROUND(
            delinquent_loans * 100.0 / NULLIF(total_loans, 0)
        , 2)                                         AS par_pct,

        ROUND(
            npa_loans * 100.0 / NULLIF(total_loans, 0)
        , 2)                                         AS npa_rate_pct,

        ROUND(
            total_collected * 100.0 / NULLIF(total_emi_due, 0)
        , 2)                                         AS emi_collection_rate_pct,

        ROUND(
            delinquent_exposure * 100.0 / NULLIF(total_exposure, 0)
        , 2)                                         AS exposure_at_risk_pct

    FROM branch_metrics

)

SELECT
    branch_name,
    region,
    total_loans,
    collected_loans,
    delinquent_loans,
    npa_loans,
    ROUND(total_exposure, 0)         AS total_exposure,
    ROUND(total_collected, 0)        AS total_collected,
    collection_efficiency_pct,
    emi_collection_rate_pct,
    par_pct,
    npa_rate_pct,
    exposure_at_risk_pct,
    avg_dpd_delinquent,

    RANK() OVER (
        ORDER BY collection_efficiency_pct DESC
    )                                                AS efficiency_rank,

    RANK() OVER (
        ORDER BY par_pct ASC
    )                                                AS par_rank,

    CASE
        WHEN RANK() OVER (ORDER BY collection_efficiency_pct DESC) <= 3
            THEN 'Top Performer'
        WHEN RANK() OVER (ORDER BY collection_efficiency_pct DESC) >= 8
            THEN 'Needs Attention'
        ELSE 'Average'
    END                                              AS performance_label

FROM branch_with_rates

ORDER BY efficiency_rank;
GO

-- ================================================================
-- QUERY 4B: BRANCH PERFORMANCE BY PRODUCT TYPE
-- ================================================================

SELECT
    b.branch_name,
    b.region,
    p.product_type,
    COUNT(f.loan_id)                                 AS total_loans,

    SUM(CASE WHEN f.amount_paid > 0
        THEN 1 ELSE 0 END)                           AS collected_loans,

    ROUND(
        SUM(CASE WHEN f.amount_paid > 0 THEN 1.0 ELSE 0 END)
        / NULLIF(COUNT(f.loan_id), 0) * 100
    , 2)                                             AS collection_efficiency_pct,

    ROUND(
        SUM(CASE WHEN f.dpd > 0 THEN 1.0 ELSE 0 END)
        / NULLIF(COUNT(f.loan_id), 0) * 100
    , 2)                                             AS par_pct,

    SUM(CASE WHEN f.dpd >= 91
        THEN 1 ELSE 0 END)                           AS npa_count

FROM fact_loan_payments f
JOIN dim_branch         b ON f.branch_id  = b.branch_id
JOIN dim_product        p ON f.product_id = p.product_id

GROUP BY
    b.branch_name,
    b.region,
    p.product_type

ORDER BY
    b.branch_name,
    collection_efficiency_pct DESC;
GO

-- ================================================================
-- QUERY 4C: REGION LEVEL ROLLUP
-- ================================================================

WITH branch_metrics AS (

    SELECT
        b.region,
        b.branch_name,
        COUNT(f.loan_id)                             AS total_loans,
        SUM(CASE WHEN f.amount_paid > 0
            THEN 1 ELSE 0 END)                       AS collected_loans,
        SUM(CASE WHEN f.dpd > 0
            THEN 1 ELSE 0 END)                       AS delinquent_loans,
        SUM(f.loan_amount)                           AS total_exposure,
        SUM(f.amount_paid)                           AS total_collected

    FROM fact_loan_payments f
    JOIN dim_branch         b ON f.branch_id = b.branch_id

    GROUP BY
        b.region,
        b.branch_name

)

SELECT
    region,
    COUNT(branch_name)                               AS branch_count,
    SUM(total_loans)                                 AS total_loans,
    SUM(collected_loans)                             AS collected_loans,
    SUM(delinquent_loans)                            AS delinquent_loans,
    ROUND(SUM(total_exposure), 0)                    AS total_exposure,
    ROUND(SUM(total_collected), 0)                   AS total_collected,

    ROUND(
        SUM(collected_loans) * 100.0
        / NULLIF(SUM(total_loans), 0)
    , 2)                                             AS region_collection_efficiency_pct,

    ROUND(
        SUM(delinquent_loans) * 100.0
        / NULLIF(SUM(total_loans), 0)
    , 2)                                             AS region_par_pct,

    RANK() OVER (
        ORDER BY
            SUM(collected_loans) * 100.0
            / NULLIF(SUM(total_loans), 0) DESC
    )                                                AS region_rank

FROM branch_metrics

GROUP BY region

ORDER BY region_rank;
GO
-- ================================================================
-- 05_AGENT_PERFORMANCE.SQL
-- Fintech Credit Risk & Collections Intelligence Dashboard
-- Author: Harshpreet Kour
-- Description: Scores every collections agent on recovery rate,
--              assigns performance quartiles using NTILE(4), and
--              identifies top and bottom performers by branch.
-- ================================================================

USE fintech_credit_db;
GO

-- ================================================================
-- QUERY 5A: AGENT PERFORMANCE WITH NTILE QUARTILE RANKING
-- ================================================================

WITH agent_metrics AS (

    SELECT
        f.agent_id,
        f.agent_name,
        b.branch_name,
        b.region,

        COUNT(f.loan_id)                             AS assigned_loans,
        
        -- Delinquent loans assigned to this agent
        SUM(CASE WHEN f.dpd > 0
            THEN 1 ELSE 0 END)                       AS delinquent_loans,

        -- NPA loans assigned to this agent
        SUM(CASE WHEN f.dpd >= 91
            THEN 1 ELSE 0 END)                       AS npa_loans,

        -- Total EMI due across all assigned loans
        SUM(f.emi_amount)                            AS total_emi_due,

        -- Total amount actually recovered
        SUM(f.amount_paid)                           AS recovered_amount,

        -- Total loan value assigned
        SUM(f.loan_amount)                           AS total_loan_value,

        -- Loan value of delinquent accounts
        SUM(CASE WHEN f.dpd > 0
            THEN f.loan_amount ELSE 0 END)           AS delinquent_exposure,

        -- Average DPD on delinquent loans only
        AVG(CASE WHEN f.dpd > 0
            THEN CAST(f.dpd AS FLOAT) END)           AS avg_dpd_on_delinquent

    FROM fact_loan_payments f
    JOIN dim_branch         b ON f.branch_id = b.branch_id

    GROUP BY
        f.agent_id,
        f.agent_name,
        b.branch_name,
        b.region

),

agent_with_rates AS (

    SELECT
        agent_id,
        agent_name,
        branch_name,
        region,
        assigned_loans,
        delinquent_loans,
        npa_loans,
        ROUND(recovered_amount, 0)                   AS recovered_amount,
        ROUND(total_loan_value, 0)                   AS total_loan_value,
        ROUND(total_emi_due, 0)                      AS total_emi_due,
        ROUND(delinquent_exposure, 0)                AS delinquent_exposure,
        ROUND(avg_dpd_on_delinquent, 1)              AS avg_dpd_on_delinquent,

        -- Recovery rate = amount recovered / total EMI due
        ROUND(
            recovered_amount * 100.0 / NULLIF(total_emi_due, 0)
        , 2)                                         AS recovery_rate_pct,
        ROUND(
            npa_loans * 100.0 / NULLIF(assigned_loans, 0)
        , 2)                                         AS agent_npa_rate_pct,
        ROUND(
            delinquent_loans * 100.0 / NULLIF(assigned_loans, 0)
        , 2)                                         AS agent_delinquency_rate_pct

    FROM agent_metrics

),

agent_ranked AS (

    SELECT
        agent_id,
        agent_name,
        branch_name,
        region,
        assigned_loans,
        delinquent_loans,
        npa_loans,
        recovered_amount,
        total_emi_due,
        recovery_rate_pct,
        agent_npa_rate_pct,
        agent_delinquency_rate_pct,
        avg_dpd_on_delinquent,
        NTILE(4) OVER (
            ORDER BY recovery_rate_pct DESC
        )                                            AS performance_quartile,
        RANK() OVER (
            ORDER BY recovery_rate_pct DESC
        )                                            AS overall_rank

    FROM agent_with_rates

)

SELECT
    agent_id,
    agent_name,
    branch_name,
    region,
    assigned_loans,
    delinquent_loans,
    npa_loans,
    recovered_amount,
    total_emi_due,
    recovery_rate_pct,
    agent_npa_rate_pct,
    agent_delinquency_rate_pct,
    avg_dpd_on_delinquent,
    performance_quartile,
    overall_rank,
    CASE performance_quartile
        WHEN 1 THEN 'Q1 - Top Performer'
        WHEN 2 THEN 'Q2 - Above Average'
        WHEN 3 THEN 'Q3 - Below Average'
        WHEN 4 THEN 'Q4 - Needs Coaching'
    END                                              AS performance_label

FROM agent_ranked

ORDER BY overall_rank;
GO

-- ================================================================
-- QUERY 5B: AGENT PERFORMANCE BY BRANCH
-- ================================================================
-- Shows how agents within the same branch compare to each other
-- Useful for branch managers to identify coaching needs

WITH agent_branch_metrics AS (

    SELECT
        f.agent_id,
        f.agent_name,
        b.branch_name,
        b.region,
        COUNT(f.loan_id)                             AS assigned_loans,
        SUM(f.amount_paid)                           AS recovered_amount,
        SUM(f.emi_amount)                            AS total_emi_due,
        SUM(CASE WHEN f.dpd >= 91
            THEN 1 ELSE 0 END)                       AS npa_loans

    FROM fact_loan_payments f
    JOIN dim_branch         b ON f.branch_id = b.branch_id

    GROUP BY
        f.agent_id,
        f.agent_name,
        b.branch_name,
        b.region

)

SELECT
    branch_name,
    agent_name,
    assigned_loans,
    ROUND(recovered_amount, 0)                       AS recovered_amount,
    npa_loans,

    ROUND(
        recovered_amount * 100.0 / NULLIF(total_emi_due, 0)
    , 2)                                             AS recovery_rate_pct,

    -- Rank within the same branch only
    RANK() OVER (
        PARTITION BY branch_name
        ORDER BY
            recovered_amount * 100.0
            / NULLIF(total_emi_due, 0) DESC
    )                                                AS rank_within_branch,

    -- NTILE within branch — Q1 = best in that branch
    NTILE(4) OVER (
        PARTITION BY branch_name
        ORDER BY
            recovered_amount * 100.0
            / NULLIF(total_emi_due, 0) DESC
    )                                                AS branch_quartile

FROM agent_branch_metrics

ORDER BY
    branch_name,
    rank_within_branch;
GO

-- ================================================================
-- QUERY 5C: TOP 5 AND BOTTOM 5 AGENTS OVERALL
-- ================================================================

WITH agent_recovery AS (

    SELECT
        f.agent_id,
        f.agent_name,
        b.branch_name,
        COUNT(f.loan_id)                             AS assigned_loans,
        ROUND(SUM(f.amount_paid), 0)                 AS recovered_amount,
        ROUND(SUM(f.emi_amount), 0)                  AS total_emi_due,
        ROUND(
            SUM(f.amount_paid) * 100.0
            / NULLIF(SUM(f.emi_amount), 0)
        , 2)                                         AS recovery_rate_pct,
        RANK() OVER (
            ORDER BY
                SUM(f.amount_paid) * 100.0
                / NULLIF(SUM(f.emi_amount), 0) DESC
        )                                            AS agent_rank

    FROM fact_loan_payments f
    JOIN dim_branch         b ON f.branch_id = b.branch_id

    GROUP BY
        f.agent_id,
        f.agent_name,
        b.branch_name

)

-- Top 5 performers
SELECT TOP 5
    'Top 5'          AS category,
    agent_rank,
    agent_name,
    branch_name,
    assigned_loans,
    recovered_amount,
    recovery_rate_pct
FROM agent_recovery
ORDER BY agent_rank ASC;
GO

-- Bottom 5 performers
WITH agent_recovery AS (

    SELECT
        f.agent_id,
        f.agent_name,
        b.branch_name,
        COUNT(f.loan_id)                             AS assigned_loans,
        ROUND(SUM(f.amount_paid), 0)                 AS recovered_amount,
        ROUND(SUM(f.emi_amount), 0)                  AS total_emi_due,
        ROUND(
            SUM(f.amount_paid) * 100.0
            / NULLIF(SUM(f.emi_amount), 0)
        , 2)                                         AS recovery_rate_pct,
        RANK() OVER (
            ORDER BY
                SUM(f.amount_paid) * 100.0
                / NULLIF(SUM(f.emi_amount), 0) ASC
        )                                            AS agent_rank

    FROM fact_loan_payments f
    JOIN dim_branch         b ON f.branch_id = b.branch_id

    GROUP BY
        f.agent_id,
        f.agent_name,
        b.branch_name

)

SELECT TOP 5
    'Bottom 5'       AS category,
    agent_rank,
    agent_name,
    branch_name,
    assigned_loans,
    recovered_amount,
    recovery_rate_pct
FROM agent_recovery
ORDER BY agent_rank ASC;
GO
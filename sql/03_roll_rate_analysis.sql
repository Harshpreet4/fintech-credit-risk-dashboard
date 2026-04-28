-- ================================================================
-- 03_ROLL_RATE_ANALYSIS.SQL
-- Fintech Credit Risk & Collections Intelligence Dashboard
-- Author: Harshpreet Kour
-- Description: Tracks how loans migrate between DPD buckets
--              month over month. Uses two CTEs and LAG() window
--              function to compare each loan's current bucket
--              against its prior month bucket and classify the
--              movement type.
-- ================================================================

USE fintech_credit_db;
GO

-- ================================================================
-- QUERY 3A: LOAN LEVEL ROLL RATE MOVEMENT
-- ================================================================

WITH monthly_buckets AS (

    SELECT
        f.loan_id,
        f.loan_amount,
        f.dpd,
        d.[year]                                         AS yr,
        d.[month]                                        AS mth,

        -- Sortable year-month integer for LAG ordering
        (d.[year] * 100) + d.[month]                     AS yr_mth_sort,

        -- Display label
        CAST(d.[year] AS VARCHAR(4))
        + '-'
        + RIGHT('0' + CAST(d.[month] AS VARCHAR(2)), 2)  AS year_month,

        -- Assign DPD bucket
        CASE
            WHEN f.dpd = 0                THEN 'Current'
            WHEN f.dpd BETWEEN 1  AND 30  THEN 'SMA-0'
            WHEN f.dpd BETWEEN 31 AND 60  THEN 'SMA-1'
            WHEN f.dpd BETWEEN 61 AND 90  THEN 'SMA-2'
            WHEN f.dpd >= 91              THEN 'NPA'
        END                                              AS dpd_bucket,

        -- Numeric bucket rank for movement direction logic
        CASE
            WHEN f.dpd = 0                THEN 1
            WHEN f.dpd BETWEEN 1  AND 30  THEN 2
            WHEN f.dpd BETWEEN 31 AND 60  THEN 3
            WHEN f.dpd BETWEEN 61 AND 90  THEN 4
            WHEN f.dpd >= 91              THEN 5
        END                                              AS bucket_rank

    FROM fact_loan_payments f
    JOIN dim_date           d ON f.due_date_id = d.date_id

),

roll_rate_base AS (

    SELECT
        loan_id,
        loan_amount,
        dpd,
        year_month,
        yr,
        mth,
        yr_mth_sort,
        dpd_bucket                                       AS current_bucket,
        bucket_rank                                      AS current_rank,

        -- Prior month bucket label
        LAG(dpd_bucket, 1)
            OVER (
                PARTITION BY loan_id
                ORDER BY yr_mth_sort
            )                                            AS prior_bucket,

        -- Prior month bucket rank number
        LAG(bucket_rank, 1)
            OVER (
                PARTITION BY loan_id
                ORDER BY yr_mth_sort
            )                                            AS prior_rank

    FROM monthly_buckets

)

SELECT
    loan_id,
    year_month,
    loan_amount,
    dpd,
    ISNULL(prior_bucket, 'New Entry')                    AS prior_bucket,
    current_bucket,

    CASE
        WHEN prior_bucket IS NULL
            THEN 'New Entry'
        WHEN current_bucket = 'NPA'
         AND prior_bucket  != 'NPA'
            THEN 'New NPA'
        WHEN current_rank < prior_rank
            THEN 'Cured'
        WHEN current_rank = prior_rank
            THEN 'Stable'
        WHEN current_rank > prior_rank
         AND current_bucket != 'NPA'
            THEN 'Rolled'
        ELSE 'Stable'
    END                                                  AS movement_type

FROM roll_rate_base
WHERE prior_bucket IS NOT NULL

ORDER BY
    year_month,
    loan_id;
GO

-- ================================================================
-- QUERY 3B: ROLL RATE SUMMARY — MOVEMENT COUNT BY MONTH
-- ================================================================

WITH monthly_buckets AS (

    SELECT
        f.loan_id,
        f.dpd,
        f.loan_amount,
        d.[year]                                         AS yr,
        d.[month]                                        AS mth,
        (d.[year] * 100) + d.[month]                     AS yr_mth_sort,

        CAST(d.[year] AS VARCHAR(4))
        + '-'
        + RIGHT('0' + CAST(d.[month] AS VARCHAR(2)), 2)  AS year_month,

        CASE
            WHEN f.dpd = 0                THEN 'Current'
            WHEN f.dpd BETWEEN 1  AND 30  THEN 'SMA-0'
            WHEN f.dpd BETWEEN 31 AND 60  THEN 'SMA-1'
            WHEN f.dpd BETWEEN 61 AND 90  THEN 'SMA-2'
            WHEN f.dpd >= 91              THEN 'NPA'
        END                                              AS dpd_bucket,

        CASE
            WHEN f.dpd = 0                THEN 1
            WHEN f.dpd BETWEEN 1  AND 30  THEN 2
            WHEN f.dpd BETWEEN 31 AND 60  THEN 3
            WHEN f.dpd BETWEEN 61 AND 90  THEN 4
            WHEN f.dpd >= 91              THEN 5
        END                                              AS bucket_rank

    FROM fact_loan_payments f
    JOIN dim_date           d ON f.due_date_id = d.date_id

),

roll_rate_base AS (

    SELECT
        loan_id,
        loan_amount,
        year_month,
        yr,
        mth,
        dpd_bucket                                       AS current_bucket,
        bucket_rank                                      AS current_rank,

        LAG(dpd_bucket,  1) OVER (
            PARTITION BY loan_id ORDER BY yr_mth_sort
        )                                                AS prior_bucket,

        LAG(bucket_rank, 1) OVER (
            PARTITION BY loan_id ORDER BY yr_mth_sort
        )                                                AS prior_rank

    FROM monthly_buckets

),

movement_classified AS (

    SELECT
        loan_id,
        loan_amount,
        year_month,
        yr,
        mth,
        ISNULL(prior_bucket, 'New Entry')                AS prior_bucket,
        current_bucket,

        CASE
            WHEN prior_bucket IS NULL                    THEN 'New Entry'
            WHEN current_bucket = 'NPA'
             AND prior_bucket  != 'NPA'                  THEN 'New NPA'
            WHEN current_rank < prior_rank               THEN 'Cured'
            WHEN current_rank = prior_rank               THEN 'Stable'
            WHEN current_rank > prior_rank
             AND current_bucket != 'NPA'                 THEN 'Rolled'
            ELSE                                              'Stable'
        END                                              AS movement_type

    FROM roll_rate_base
    WHERE prior_bucket IS NOT NULL

)

SELECT
    year_month,
    movement_type,
    COUNT(loan_id)                  AS loan_count,
    ROUND(SUM(loan_amount), 0)      AS total_exposure

FROM movement_classified

GROUP BY
    year_month,
    yr,
    mth,
    movement_type

ORDER BY
    yr,
    mth,
    movement_type;
GO

-- ================================================================
-- QUERY 3C: ROLL RATE MATRIX — FROM BUCKET TO BUCKET
-- ================================================================

WITH monthly_buckets AS (

    SELECT
        f.loan_id,
        d.[year]                                         AS yr,
        d.[month]                                        AS mth,
        (d.[year] * 100) + d.[month]                     AS yr_mth_sort,

        CASE
            WHEN f.dpd = 0                THEN 'Current'
            WHEN f.dpd BETWEEN 1  AND 30  THEN 'SMA-0'
            WHEN f.dpd BETWEEN 31 AND 60  THEN 'SMA-1'
            WHEN f.dpd BETWEEN 61 AND 90  THEN 'SMA-2'
            WHEN f.dpd >= 91              THEN 'NPA'
        END                                              AS dpd_bucket,

        CASE
            WHEN f.dpd = 0                THEN 1
            WHEN f.dpd BETWEEN 1  AND 30  THEN 2
            WHEN f.dpd BETWEEN 31 AND 60  THEN 3
            WHEN f.dpd BETWEEN 61 AND 90  THEN 4
            WHEN f.dpd >= 91              THEN 5
        END                                              AS bucket_rank

    FROM fact_loan_payments f
    JOIN dim_date           d ON f.due_date_id = d.date_id

),

transitions AS (

    SELECT
        loan_id,
        dpd_bucket                                       AS current_bucket,
        LAG(dpd_bucket, 1) OVER (
            PARTITION BY loan_id
            ORDER BY yr_mth_sort
        )                                                AS prior_bucket

    FROM monthly_buckets

)

SELECT
    prior_bucket                                         AS from_bucket,
    current_bucket                                       AS to_bucket,
    COUNT(loan_id)                                       AS loan_count,

    ROUND(
        COUNT(loan_id) * 100.0
        / SUM(COUNT(loan_id)) OVER (PARTITION BY prior_bucket)
    , 1)                                                 AS transition_pct

FROM transitions
WHERE prior_bucket IS NOT NULL

GROUP BY
    prior_bucket,
    current_bucket

ORDER BY
    prior_bucket,
    current_bucket;
GO
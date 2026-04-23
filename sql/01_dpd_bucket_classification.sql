USE fintech_credit_db;
GO
-- ================================================================
-- QUERY 1A: DPD BUCKET CLASSIFICATION — PORTFOLIO SUMMARY
-- ================================================================
WITH dpd_classified AS (

    SELECT
        loan_id,
        loan_amount,
        dpd,
        loan_status,

        -- Assign DPD bucket using CASE WHEN
        -- This is the RBI classification standard used by all
        -- Indian banks and NBFCs
        CASE
            WHEN dpd = 0          THEN 'Current'
            WHEN dpd BETWEEN 1  AND 30  THEN 'SMA-0'
            WHEN dpd BETWEEN 31 AND 60  THEN 'SMA-1'
            WHEN dpd BETWEEN 61 AND 90  THEN 'SMA-2'
            WHEN dpd >= 91        THEN 'NPA'
            ELSE 'Unknown'
        END AS dpd_bucket,

        -- Assign sort order so results display in risk order
        -- not alphabetical order
        CASE
            WHEN dpd = 0                THEN 1
            WHEN dpd BETWEEN 1  AND 30  THEN 2
            WHEN dpd BETWEEN 31 AND 60  THEN 3
            WHEN dpd BETWEEN 61 AND 90  THEN 4
            WHEN dpd >= 91              THEN 5
            ELSE 6
        END AS bucket_sort_order

    FROM fact_loan_payments

),

-- Second CTE calculates total portfolio value
-- We need this separately to calculate portfolio_share_pct
-- without using a subquery inside the main SELECT
portfolio_totals AS (

    SELECT
        SUM(loan_amount) AS total_portfolio_value,
        COUNT(loan_id)   AS total_loan_count
    FROM fact_loan_payments

)

-- ── Main SELECT ──────────────────────────────────────────────────
SELECT
    d.dpd_bucket,
    COUNT(d.loan_id)                                        AS loan_count,
    SUM(d.loan_amount)                                      AS total_exposure,
    ROUND(AVG(CAST(d.dpd AS FLOAT)), 1)                     AS avg_dpd,
    ROUND(
        COUNT(d.loan_id) * 100.0 / p.total_loan_count
    , 1)                                                    AS portfolio_share_pct,
    ROUND(
        SUM(d.loan_amount) * 100.0 / p.total_portfolio_value
    , 1)                                                    AS exposure_share_pct,
    MIN(d.dpd)                                              AS min_dpd,
    MAX(d.dpd)                                              AS max_dpd

FROM dpd_classified    d
CROSS JOIN portfolio_totals p   -- CROSS JOIN because portfolio_totals
                                -- has exactly 1 row — every bucket row
                                -- needs access to the same total
GROUP BY
    d.dpd_bucket,
    d.bucket_sort_order,
    p.total_loan_count,
    p.total_portfolio_value

ORDER BY d.bucket_sort_order;
GO
-- ================================================================
-- QUERY 1B: DPD BUCKET BREAKDOWN BY PRODUCT TYPE
-- ================================================================
WITH dpd_by_product AS (

    SELECT
        f.loan_id,
        f.loan_amount,
        f.dpd,
        p.product_type,

        CASE
            WHEN f.dpd = 0                THEN 'Current'
            WHEN f.dpd BETWEEN 1  AND 30  THEN 'SMA-0'
            WHEN f.dpd BETWEEN 31 AND 60  THEN 'SMA-1'
            WHEN f.dpd BETWEEN 61 AND 90  THEN 'SMA-2'
            WHEN f.dpd >= 91              THEN 'NPA'
        END AS dpd_bucket,

        CASE
            WHEN f.dpd = 0                THEN 1
            WHEN f.dpd BETWEEN 1  AND 30  THEN 2
            WHEN f.dpd BETWEEN 31 AND 60  THEN 3
            WHEN f.dpd BETWEEN 61 AND 90  THEN 4
            WHEN f.dpd >= 91              THEN 5
        END AS bucket_sort_order

    FROM fact_loan_payments f
    JOIN dim_product        p ON f.product_id = p.product_id

)

SELECT
    product_type,
    dpd_bucket,
    COUNT(loan_id)         AS loan_count,
    ROUND(SUM(loan_amount), 0) AS total_exposure

FROM dpd_by_product

GROUP BY
    product_type,
    dpd_bucket,
    bucket_sort_order

ORDER BY
    product_type,
    bucket_sort_order;
GO
-- ================================================================
-- QUERY 1C: NPA DEEP DIVE
-- ================================================================
SELECT
    b.branch_name,
    b.region,
    p.product_type,
    COUNT(f.loan_id)               AS npa_loan_count,
    ROUND(SUM(f.loan_amount), 0)   AS npa_exposure,
    ROUND(AVG(CAST(f.dpd AS FLOAT)), 0) AS avg_dpd_in_npa

FROM fact_loan_payments f
JOIN dim_branch         b ON f.branch_id  = b.branch_id
JOIN dim_product        p ON f.product_id = p.product_id

WHERE f.dpd >= 91   -- NPA threshold per RBI guidelines

GROUP BY
    b.branch_name,
    b.region,
    p.product_type

ORDER BY
    npa_exposure DESC;
GO
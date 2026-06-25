-- =============================================================================
-- 11  Loan delinquency rate and Days-Past-Due (DPD) buckets
-- -----------------------------------------------------------------------------
-- Business question:
--   What share of the loan portfolio is delinquent, and how does outstanding
--   past-due exposure distribute across standard DPD aging buckets
--   (Current, 1-29, 30-59, 60-89, 90+)? This is core credit-risk reporting.
--
-- Approach:
--   1) For every installment, compute its DPD as of the reporting date:
--        - if paid late: paid_date - due_date
--        - if unpaid and overdue: as_of_date - due_date
--        - else 0 (current / paid on time).
--   2) Take each loan's WORST (max) DPD as its current delinquency status.
--   3) Map to aging buckets and aggregate counts, the delinquency rate, and the
--      past-due dollar exposure per bucket.
--
-- Technique: loan portfolio metrics - delinquency rate + DPD buckets
--            (conditional aggregation / CASE bucketing)
--
-- Dialect notes:
--   * GREATEST is supported by DuckDB/Postgres. T-SQL lacks GREATEST pre-2022;
--     use CASE or IIF. Date subtraction -> DATEDIFF(DAY, due_date, COALESCE(...)).
-- =============================================================================

WITH bounds AS (
    SELECT MAX(due_date) AS as_of_date FROM loan_payments
),
installment_dpd AS (
    SELECT
        lp.loan_id,
        lp.amount_due,
        lp.amount_paid,
        CASE
            WHEN lp.paid_date IS NOT NULL
                THEN GREATEST(CAST(lp.paid_date - lp.due_date AS INTEGER), 0)
            WHEN lp.due_date < (SELECT as_of_date FROM bounds)
                THEN CAST((SELECT as_of_date FROM bounds) - lp.due_date AS INTEGER)
            ELSE 0
        END AS dpd,
        -- past-due dollars still owed on this installment
        CASE WHEN lp.paid_date IS NULL
             THEN lp.amount_due - lp.amount_paid ELSE 0 END AS past_due_amount
    FROM loan_payments AS lp
),
loan_status AS (
    SELECT
        loan_id,
        MAX(dpd)              AS worst_dpd,
        SUM(past_due_amount)  AS total_past_due
    FROM installment_dpd
    GROUP BY loan_id
),
bucketed AS (
    SELECT
        l.loan_id,
        l.loan_type,
        l.principal_amount,
        ls.worst_dpd,
        ls.total_past_due,
        CASE
            WHEN ls.worst_dpd = 0               THEN '0 - Current'
            WHEN ls.worst_dpd BETWEEN 1  AND 29 THEN '1 - DPD 1-29'
            WHEN ls.worst_dpd BETWEEN 30 AND 59 THEN '2 - DPD 30-59'
            WHEN ls.worst_dpd BETWEEN 60 AND 89 THEN '3 - DPD 60-89'
            ELSE '4 - DPD 90+'
        END AS dpd_bucket
    FROM loans       AS l
    JOIN loan_status AS ls ON ls.loan_id = l.loan_id
)
SELECT
    dpd_bucket,
    COUNT(*)                                                   AS loan_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)         AS pct_of_portfolio,
    ROUND(SUM(principal_amount), 2)                            AS principal_exposure,
    ROUND(SUM(total_past_due), 2)                              AS past_due_exposure
FROM bucketed
GROUP BY dpd_bucket
ORDER BY dpd_bucket;

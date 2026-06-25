-- =============================================================================
-- 12  Loan vintage analysis (cumulative delinquency by months-on-book)
-- -----------------------------------------------------------------------------
-- Business question:
--   Do loans originated in different quarters (vintages) deteriorate at
--   different speeds? We compare the cumulative share of each vintage that has
--   EVER been 30+ days past due, by months-on-book (MOB). This is how credit
--   teams catch a worsening origination quality trend early.
--
-- Approach:
--   1) Tag each loan with its origination quarter (the vintage) and total loans
--      in that vintage.
--   2) For each installment compute DPD and its months-on-book (installment_no
--      is effectively MOB). Flag installments that hit 30+ DPD.
--   3) For each (vintage, MOB), count DISTINCT loans that were 30+ DPD at or
--      before that MOB (cumulative) and divide by the vintage size.
--
-- Technique: vintage analysis (cohort by origination + cumulative window)
--
-- Dialect notes:
--   * Quarter label: DuckDB/Postgres EXTRACT(QUARTER FROM d). T-SQL DATEPART(QUARTER, d).
--   * The cumulative DISTINCT-loan count uses a window COUNT over an ordered MOB.
-- =============================================================================

WITH loan_vintage AS (
    SELECT
        l.loan_id,
        CAST(EXTRACT(YEAR FROM l.origination_date) AS INTEGER)             AS orig_year,
        CAST(EXTRACT(QUARTER FROM l.origination_date) AS INTEGER)          AS orig_quarter
    FROM loans AS l
),
vintage_label AS (
    SELECT
        loan_id,
        (CAST(orig_year AS VARCHAR) || '-Q' || CAST(orig_quarter AS VARCHAR)) AS vintage
    FROM loan_vintage
),
vintage_size AS (
    SELECT vintage, COUNT(*) AS vintage_loans
    FROM vintage_label
    GROUP BY vintage
),
installment_flags AS (
    SELECT
        v.vintage,
        lp.loan_id,
        lp.installment_no AS mob,                 -- months-on-book
        CASE
            WHEN lp.paid_date IS NOT NULL AND CAST(lp.paid_date - lp.due_date AS INTEGER) >= 30 THEN 1
            WHEN lp.paid_date IS NULL THEN 1       -- still unpaid past its due date = delinquent
            ELSE 0
        END AS hit_30dpd
    FROM loan_payments AS lp
    JOIN vintage_label AS v ON v.loan_id = lp.loan_id
),
-- first MOB at which each loan first hit 30+ DPD (or never)
first_delinquency AS (
    SELECT
        vintage,
        loan_id,
        MIN(CASE WHEN hit_30dpd = 1 THEN mob END) AS first_bad_mob
    FROM installment_flags
    GROUP BY vintage, loan_id
),
mob_spine AS (                                    -- distinct MOB values present per vintage
    SELECT DISTINCT vintage, mob FROM installment_flags
)
SELECT
    s.vintage,
    s.mob,
    vs.vintage_loans,
    COUNT(DISTINCT CASE WHEN fd.first_bad_mob <= s.mob THEN fd.loan_id END) AS loans_ever_30dpd,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN fd.first_bad_mob <= s.mob THEN fd.loan_id END)
          / vs.vintage_loans, 1) AS cumulative_delinquency_pct
FROM mob_spine          AS s
JOIN vintage_size       AS vs ON vs.vintage = s.vintage
LEFT JOIN first_delinquency AS fd ON fd.vintage = s.vintage
GROUP BY s.vintage, s.mob, vs.vintage_loans
ORDER BY s.vintage, s.mob;

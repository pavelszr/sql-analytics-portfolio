-- =============================================================================
-- 06  Monthly cohort retention matrix
-- -----------------------------------------------------------------------------
-- Business question:
--   Of the customers who joined in a given month, what fraction were still
--   transacting N months later? This is the classic retention triangle that
--   shows whether newer cohorts retain better or worse than older ones.
--
-- Approach:
--   1) cohort: each customer's signup month (the cohort anchor).
--   2) activity: every month in which the customer had at least one transaction.
--   3) month_offset = months between the activity month and the cohort month.
--   4) Pivot offsets 0..6 with conditional COUNT(DISTINCT) and divide by the
--      cohort's signup population to get a retention percentage. m0_pct is the
--      activation rate (it can be below 100% when a late-in-month signup does
--      not transact until the following month).
--
-- Technique: cohort retention analysis (cohort + activity + offset + pivot)
--
-- Dialect notes:
--   * Month diff: DuckDB/Postgres use DATE_DIFF / age arithmetic. Here we derive
--     a stable integer offset = (year*12 + month) difference, which is portable.
--   * T-SQL: DATEDIFF(MONTH, cohort_month, activity_month).
-- =============================================================================

WITH cohort AS (              -- each customer's cohort month as an integer YYYYMM-ish ordinal
    SELECT
        customer_id,
        DATE_TRUNC('month', signup_date)                                AS cohort_month,
        EXTRACT(YEAR FROM signup_date) * 12 + EXTRACT(MONTH FROM signup_date) AS cohort_ord
    FROM customers
),
activity AS (                 -- distinct active months per customer
    SELECT DISTINCT
        a.customer_id,
        EXTRACT(YEAR FROM t.txn_date) * 12 + EXTRACT(MONTH FROM t.txn_date) AS activity_ord
    FROM transactions AS t
    JOIN accounts     AS a ON a.account_id = t.account_id
),
offsets AS (                  -- months since signup for each active month
    SELECT
        c.cohort_month,
        c.customer_id,
        CAST(act.activity_ord - c.cohort_ord AS INTEGER) AS month_offset
    FROM cohort   AS c
    JOIN activity AS act ON act.customer_id = c.customer_id
    WHERE act.activity_ord >= c.cohort_ord          -- ignore pre-signup noise, if any
),
cohort_size AS (              -- ALL customers who signed up that month (the true denominator)
    SELECT cohort_month, COUNT(*) AS cohort_customers
    FROM cohort
    GROUP BY cohort_month
)
SELECT
    o.cohort_month,
    cs.cohort_customers,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN o.month_offset = 0 THEN o.customer_id END)
          / cs.cohort_customers, 1) AS m0_pct,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN o.month_offset = 1 THEN o.customer_id END)
          / cs.cohort_customers, 1) AS m1_pct,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN o.month_offset = 2 THEN o.customer_id END)
          / cs.cohort_customers, 1) AS m2_pct,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN o.month_offset = 3 THEN o.customer_id END)
          / cs.cohort_customers, 1) AS m3_pct,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN o.month_offset = 4 THEN o.customer_id END)
          / cs.cohort_customers, 1) AS m4_pct,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN o.month_offset = 5 THEN o.customer_id END)
          / cs.cohort_customers, 1) AS m5_pct,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN o.month_offset = 6 THEN o.customer_id END)
          / cs.cohort_customers, 1) AS m6_pct
FROM offsets     AS o
JOIN cohort_size AS cs ON cs.cohort_month = o.cohort_month
GROUP BY o.cohort_month, cs.cohort_customers
ORDER BY o.cohort_month;

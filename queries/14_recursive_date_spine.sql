-- =============================================================================
-- 14  Recursive CTE: date spine for gap-free daily deposit reporting
-- -----------------------------------------------------------------------------
-- Business question:
--   Daily deposit totals must show ZERO on days with no deposits, otherwise
--   charts and rolling metrics silently skip missing days. How do we produce a
--   continuous, gap-free daily series across the whole reporting window?
--
-- Approach:
--   1) Generate every calendar date between the first and last transaction date
--      with a recursive CTE (the "date spine").
--   2) LEFT JOIN actual daily deposit sums onto the spine, COALESCEing missing
--      days to 0.
--   3) Add a 7-day moving average to show why the gap-free spine matters: the
--      moving window is now correct because no days are skipped.
--
-- Technique: recursive CTE (date spine) + outer join densification
--
-- Dialect notes:
--   * Recursive CTE is ANSI; DuckDB/Postgres/SQLite/T-SQL all support
--     WITH RECURSIVE (T-SQL: just WITH, recursion implied; default MAXRECURSION
--     is 100 so add OPTION (MAXRECURSION 0) for long spines).
--   * day + INTERVAL '1 day': DuckDB/Postgres. SQLite: date(day,'+1 day').
--     T-SQL: DATEADD(DAY, 1, day).
-- =============================================================================

WITH RECURSIVE bounds AS (
    SELECT MIN(txn_date) AS start_date, MAX(txn_date) AS end_date
    FROM transactions
),
date_spine AS (
    SELECT start_date AS calendar_date, end_date
    FROM bounds
    UNION ALL
    SELECT
        CAST(calendar_date + INTERVAL '1 day' AS DATE),
        end_date
    FROM date_spine
    WHERE calendar_date < end_date
),
daily_deposits AS (
    SELECT
        txn_date,
        SUM(amount) AS deposits
    FROM transactions
    WHERE txn_type = 'deposit'
    GROUP BY txn_date
)
SELECT
    s.calendar_date,
    COALESCE(d.deposits, 0) AS daily_deposits,
    ROUND(
        AVG(COALESCE(d.deposits, 0)) OVER (
            ORDER BY s.calendar_date
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ), 2
    ) AS deposits_7day_moving_avg
FROM date_spine     AS s
LEFT JOIN daily_deposits AS d ON d.txn_date = s.calendar_date
ORDER BY s.calendar_date;

-- =============================================================================
-- 03  Month-over-month and year-over-year deposit growth
-- -----------------------------------------------------------------------------
-- Business question:
--   How is total deposit volume growing month over month (MoM) and year over
--   year (YoY)? YoY removes seasonality that MoM cannot.
--
-- Approach:
--   1) Sum deposit inflows per calendar month.
--   2) LAG(...,1) gives the prior month; LAG(...,12) gives the same month last
--      year. Growth = (current - prior) / prior. NULLIF guards divide-by-zero.
--
-- Technique: window function - LAG, MoM / YoY growth
--
-- Dialect notes:
--   * LAG(col, n) OVER (ORDER BY ...) is ANSI and works on all four engines.
--   * SQLite 3.25+ supports LAG. T-SQL identical (SQL Server 2012+).
-- =============================================================================

WITH monthly_deposits AS (
    SELECT
        DATE_TRUNC('month', t.txn_date) AS deposit_month,
        SUM(t.amount)                   AS total_deposits
    FROM transactions AS t
    WHERE t.txn_type = 'deposit'
    GROUP BY DATE_TRUNC('month', t.txn_date)
),
with_lags AS (
    SELECT
        deposit_month,
        total_deposits,
        LAG(total_deposits, 1)  OVER (ORDER BY deposit_month) AS prev_month,
        LAG(total_deposits, 12) OVER (ORDER BY deposit_month) AS same_month_last_year
    FROM monthly_deposits
)
SELECT
    deposit_month,
    total_deposits,
    prev_month,
    ROUND( (total_deposits - prev_month)
           / NULLIF(prev_month, 0) * 100, 1)            AS mom_growth_pct,
    same_month_last_year,
    ROUND( (total_deposits - same_month_last_year)
           / NULLIF(same_month_last_year, 0) * 100, 1)  AS yoy_growth_pct
FROM with_lags
ORDER BY deposit_month;

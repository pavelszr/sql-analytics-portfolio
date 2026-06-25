-- =============================================================================
-- 15  Percentiles and median of customer spend (PERCENTILE_CONT)
-- -----------------------------------------------------------------------------
-- Business question:
--   The AVERAGE customer spend is skewed by a few heavy spenders. What does the
--   DISTRIBUTION look like - the median, the interquartile range, and the 90th
--   percentile - overall and broken out by risk segment?
--
-- Approach:
--   Aggregate monthly debit spend per customer, then use the ordered-set
--   aggregate PERCENTILE_CONT to compute the 25th / 50th (median) / 75th / 90th
--   percentiles. Compare median vs mean to quantify right-skew.
--
-- Technique: percentiles / median via PERCENTILE_CONT (WITHIN GROUP)
--
-- Dialect notes:
--   * PERCENTILE_CONT(f) WITHIN GROUP (ORDER BY x): ANSI ordered-set aggregate,
--     supported by DuckDB and Postgres.
--   * SQLite has NO PERCENTILE_CONT - emulate with NTILE/ROW_NUMBER or a
--     median trick (see README "How to run" for the SQLite fallback).
--   * T-SQL: PERCENTILE_CONT is a WINDOW function there, not an aggregate:
--       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY x) OVER (PARTITION BY seg)
--     i.e. it returns one value per row; wrap in SELECT DISTINCT or AVG to
--     collapse to one row per group.
-- =============================================================================

WITH customer_spend AS (
    SELECT
        a.customer_id,
        c.risk_segment,
        SUM(ABS(t.amount)) AS total_spend
    FROM transactions AS t
    JOIN accounts     AS a ON a.account_id = t.account_id
    JOIN customers    AS c ON c.customer_id = a.customer_id
    WHERE t.amount < 0
    GROUP BY a.customer_id, c.risk_segment
)
SELECT
    risk_segment,
    COUNT(*)                                                              AS customers,
    ROUND(AVG(total_spend), 2)                                           AS mean_spend,
    ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY total_spend), 2)  AS p25_spend,
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY total_spend), 2)  AS median_spend,
    ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY total_spend), 2)  AS p75_spend,
    ROUND(PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY total_spend), 2)  AS p90_spend,
    ROUND(AVG(total_spend)
          - PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY total_spend), 2) AS mean_minus_median
FROM customer_spend
GROUP BY risk_segment
ORDER BY risk_segment;

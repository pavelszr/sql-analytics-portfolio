-- =============================================================================
-- 09  Gaps-and-islands: longest streak of consecutive active days
-- -----------------------------------------------------------------------------
-- Business question:
--   What is each account's longest run of consecutive calendar days with at
--   least one transaction? Long streaks signal highly engaged accounts; the
--   same technique sessionizes activity and finds dormancy gaps.
--
-- Approach (the classic gaps-and-islands trick):
--   1) Reduce transactions to one row per (account, active_day).
--   2) ROW_NUMBER per account ordered by day. For a run of consecutive days,
--      (day - row_number) is constant, so it becomes a stable "island key".
--   3) GROUP BY that island key to collapse each run; the run length is the
--      row count, and we keep the maximum per account.
--
-- Technique: gaps-and-islands / sessionization
--
-- Dialect notes:
--   * Date - integer arithmetic: DuckDB/Postgres support DATE - INT directly.
--     The island key here uses an integer day ordinal so it is fully portable
--     (we convert each day to a day-count via EXTRACT(EPOCH ...)/86400 style;
--     below we use the engine-portable approach of differencing row numbers
--     against a dense day index).
--   * T-SQL: DATEADD/DATEDIFF(DAY, 0, day) gives the day ordinal; the
--     ROW_NUMBER differencing pattern is identical.
-- =============================================================================

WITH active_days AS (                  -- one row per account per active calendar day
    SELECT DISTINCT
        account_id,
        txn_date AS active_day
    FROM transactions
),
day_indexed AS (                       -- attach a per-account sequential index
    SELECT
        account_id,
        active_day,
        ROW_NUMBER() OVER (PARTITION BY account_id ORDER BY active_day) AS rn
    FROM active_days
),
islands AS (
    -- For consecutive days, active_day minus rn days is constant within a run.
    -- DATE_DIFF gives the day ordinal of active_day; subtracting rn yields the
    -- island anchor. (DuckDB/Postgres: active_day - rn works on DATE too.)
    SELECT
        account_id,
        active_day,
        CAST(active_day AS DATE) - CAST(rn AS INTEGER) AS island_key
    FROM day_indexed
),
runs AS (
    SELECT
        account_id,
        island_key,
        MIN(active_day) AS streak_start,
        MAX(active_day) AS streak_end,
        COUNT(*)        AS streak_length
    FROM islands
    GROUP BY account_id, island_key
)
SELECT
    account_id,
    streak_start,
    streak_end,
    streak_length
FROM (
    SELECT
        account_id,
        streak_start,
        streak_end,
        streak_length,
        ROW_NUMBER() OVER (
            PARTITION BY account_id
            ORDER BY streak_length DESC, streak_start
        ) AS rk
    FROM runs
) ranked
WHERE rk = 1                           -- longest streak per account
ORDER BY streak_length DESC, account_id;

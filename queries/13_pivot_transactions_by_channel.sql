-- =============================================================================
-- 13  Pivot: monthly transaction volume by channel (conditional aggregation)
-- -----------------------------------------------------------------------------
-- Business question:
--   How is transaction volume distributed across channels (ATM, POS, online,
--   branch, ACH) each month, presented as a wide report with one column per
--   channel for an at-a-glance management view?
--
-- Approach:
--   Classic conditional-aggregation pivot: SUM a CASE expression per target
--   channel so each channel collapses into its own column. Add a row total and
--   the online share to make the pivot analytically useful, not just reshaped.
--
-- Technique: pivot via conditional aggregation
--
-- Dialect notes:
--   * This SUM(CASE WHEN ... END) pattern is the portable pivot and runs on all
--     four engines unchanged.
--   * T-SQL also has the PIVOT operator; DuckDB has PIVOT; Postgres has crosstab
--     (tablefunc). Conditional aggregation is preferred for portability + control.
-- =============================================================================

SELECT
    DATE_TRUNC('month', txn_date) AS txn_month,
    COUNT(*)                                                          AS total_txns,
    SUM(CASE WHEN channel = 'atm'    THEN 1 ELSE 0 END)               AS atm_txns,
    SUM(CASE WHEN channel = 'pos'    THEN 1 ELSE 0 END)               AS pos_txns,
    SUM(CASE WHEN channel = 'online' THEN 1 ELSE 0 END)               AS online_txns,
    SUM(CASE WHEN channel = 'branch' THEN 1 ELSE 0 END)               AS branch_txns,
    SUM(CASE WHEN channel = 'ach'    THEN 1 ELSE 0 END)               AS ach_txns,
    ROUND(100.0 * SUM(CASE WHEN channel = 'online' THEN 1 ELSE 0 END)
          / COUNT(*), 1)                                              AS online_share_pct
FROM transactions
GROUP BY DATE_TRUNC('month', txn_date)
ORDER BY txn_month;

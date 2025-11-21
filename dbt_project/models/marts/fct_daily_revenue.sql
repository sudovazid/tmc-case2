WITH transactions AS (
    SELECT * FROM {{ ref('stg_transactions') }}
)

SELECT
    DATE(created_at) as report_date,
    COUNT(transaction_id) as total_transactions,
    SUM(amount) as total_revenue
FROM transactions
GROUP BY 1
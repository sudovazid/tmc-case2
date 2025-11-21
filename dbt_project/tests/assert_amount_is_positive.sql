-- This test fails if it returns any rows
SELECT
    transaction_id,
    amount
FROM {{ ref('stg_transactions') }}
WHERE amount < 0
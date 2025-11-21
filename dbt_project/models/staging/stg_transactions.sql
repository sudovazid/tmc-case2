WITH raw_data AS (
    SELECT
        transaction_id,
        created_at,
        amount,
        customer_id,
        _ingestion_timestamp,
        -- Use ROW_NUMBER to find the latest ingestion for this ID
        ROW_NUMBER() OVER(
            PARTITION BY transaction_id
            ORDER BY _ingestion_timestamp DESC
        ) as rn
    FROM {{ source('warehouse', 'raw_transactions') }}
)

SELECT
    transaction_id,
    created_at,
    amount,
    customer_id
FROM raw_data
WHERE rn = 1 -- Only keep the freshest copy
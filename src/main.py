import os
import json
import logging
from google.cloud import storage
from google.cloud import bigquery
from google.cloud import pubsub_v1
from jsonschema import validate, ValidationError
from datetime import datetime

# Configuration (Env vars injected by Terraform later)
PROJECT_ID = os.environ.get('PROJECT_ID')
DATASET_ID = os.environ.get('DATASET_ID')
TABLE_ID = os.environ.get('TABLE_ID')
DLQ_TOPIC_ID = os.environ.get('DLQ_TOPIC_ID')

# Strict Schema for Validation
TRANSACTION_SCHEMA = {
    "type": "object",
    "properties": {
        "transaction_id": {"type": "string"},
        "created_at": {"type": "string", "format": "date-time"}, # ISO 8601
        "amount": {"type": "number"},
        "customer_id": {"type": "string"}
    },
    "required": ["transaction_id", "created_at", "amount"]
}

def ingest_file(event, context):
    """Triggered by a change to a Cloud Storage bucket."""
    file_name = event['name']
    bucket_name = event['bucket']

    logging.info(f"Processing file: {file_name} from {bucket_name}")

    # Initialize Clients
    storage_client = storage.Client()
    bq_client = bigquery.Client()
    publisher = pubsub_v1.PublisherClient()
    dlq_path = publisher.topic_path(PROJECT_ID, DLQ_TOPIC_ID)

    # 1. Read File
    bucket = storage_client.bucket(bucket_name)
    blob = bucket.blob(file_name)
    content = blob.download_as_text()

    # Expecting Newline Delimited JSON (NDJSON) or a JSON Array
    # For simplicity, let's assume one JSON object per line (NDJSON)
    rows_to_insert = []

    lines = content.strip().split('\n')

    for line in lines:
        if not line.strip(): continue

        try:
            record = json.loads(line)

            # 2. Validate Schema
            validate(instance=record, schema=TRANSACTION_SCHEMA)

            # Add ingestion timestamp
            record['_ingestion_timestamp'] = datetime.utcnow().isoformat()
            rows_to_insert.append(record)

        except (ValidationError, json.JSONDecodeError) as e:
            # 3. Route Rejects to DLQ
            error_message = {
                "file": file_name,
                "raw_data": line,
                "error": str(e),
                "timestamp": datetime.utcnow().isoformat()
            }
            print(f"Validation Failed: {e}")
            publisher.publish(dlq_path, json.dumps(error_message).encode('utf-8'))

    # 4. Insert Valid Rows to BigQuery
    if rows_to_insert:
        table_ref = f"{PROJECT_ID}.{DATASET_ID}.{TABLE_ID}"
        errors = bq_client.insert_rows_json(table_ref, rows_to_insert)

        if errors:
            # If BQ insert fails (e.g. system error), send to DLQ as well
            print(f"BigQuery Insert Errors: {errors}")
            # In prod, you would iterate and send specific rows to DLQ

    print(f"Processed {len(lines)} lines. {len(rows_to_insert)} inserted.")
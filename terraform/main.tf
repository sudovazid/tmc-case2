# ---------------------------------------------------------
# 1. Ingestion Layer: GCS Bucket (File Drop)
# ---------------------------------------------------------
resource "google_storage_bucket" "ingestion_bucket" {
  name          = var.bucket_name
  location      = var.region
  force_destroy = true

  uniform_bucket_level_access = true
}

# ---------------------------------------------------------
# 2. Validation Layer: Dead Letter Queue (DLQ)
# ---------------------------------------------------------
resource "google_pubsub_topic" "dlq_topic" {
  name = "ingestion-dlq-topic"
}

resource "google_pubsub_subscription" "dlq_subscription" {
  name  = "ingestion-dlq-sub"
  topic = google_pubsub_topic.dlq_topic.name

  # Retain messages so we can inspect them later
  message_retention_duration = "604800s" # 7 days
}

# ---------------------------------------------------------
# 3. Storage Layer: BigQuery Dataset
# ---------------------------------------------------------
resource "google_bigquery_dataset" "warehouse" {
  dataset_id                  = "data_warehouse_dev"
  friendly_name               = "Data Warehouse"
  description                 = "Main dataset for dbt models"
  location                    = var.region
  default_table_expiration_ms = null

  # Delete contents when destroying terraform (for dev only)
  delete_contents_on_destroy = true
}

# ---------------------------------------------------------
# 4. Governance: Minimal IAM
# ---------------------------------------------------------
# Service Account for the Ingestion (Writer)
resource "google_service_account" "ingestion_sa" {
  account_id   = "ingestion-writer"
  display_name = "Ingestion Service Account"
}

# Service Account for Analytics (Reader)
resource "google_service_account" "analytics_sa" {
  account_id   = "analytics-reader"
  display_name = "Analytics Service Account"
}

# Grant Ingestion SA permission to write to BigQuery
resource "google_bigquery_dataset_iam_member" "ingestion_writer" {
  dataset_id = google_bigquery_dataset.warehouse.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.ingestion_sa.email}"
}

# Grant Analytics SA permission to read BigQuery
resource "google_bigquery_dataset_iam_member" "analytics_reader" {
  dataset_id = google_bigquery_dataset.warehouse.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${google_service_account.analytics_sa.email}"
}

# ---------------------------------------------------------
# 5. The Data Landing Zone (Partitioned Table)
# ---------------------------------------------------------
resource "google_bigquery_table" "raw_transactions" {
  dataset_id = google_bigquery_dataset.warehouse.dataset_id
  table_id   = "raw_transactions"

  # Partition by ingestion time (DAY is standard)
  time_partitioning {
    type = "DAY"
  }

  # Schema definition (JSON format)
  schema = <<EOF
[
  {
    "name": "transaction_id",
    "type": "STRING",
    "mode": "REQUIRED",
    "description": "Deterministic key for idempotency"
  },
  {
    "name": "created_at",
    "type": "TIMESTAMP",
    "mode": "REQUIRED"
  },
  {
    "name": "amount",
    "type": "FLOAT",
    "mode": "NULLABLE"
  },
  {
    "name": "customer_id",
    "type": "STRING",
    "mode": "NULLABLE"
  },
  {
    "name": "_ingestion_timestamp",
    "type": "TIMESTAMP",
    "mode": "REQUIRED",
    "description": "Server timestamp for auditing"
  }
]
EOF
}


# ---------------------------------------------------------
# 6. Cloud Function Artifacts (Code Storage)
# ---------------------------------------------------------
# A separate bucket to hold the function source code zip
resource "google_storage_bucket" "function_source" {
  name          = "${var.bucket_name}-source"
  location      = var.region
  force_destroy = true
  uniform_bucket_level_access = true
}

# Zip the Python source code from the ../src directory
data "archive_file" "function_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../src"
  output_path = "${path.module}/function_source.zip"
}

# Upload the zip to the source bucket
resource "google_storage_bucket_object" "function_archive" {
  name   = "source-${data.archive_file.function_zip.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_zip.output_path
}

# ---------------------------------------------------------
# 7. The Ingestion Cloud Function
# ---------------------------------------------------------
resource "google_cloudfunctions_function" "ingestion_function" {
  name        = "ingestion-processor"
  description = "Validates file drop and inserts to BigQuery"
  runtime     = "python310"

  available_memory_mb   = 256
  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.function_archive.name

  # Trigger: Runs when a file is finalized (uploaded) to the DATA bucket
  event_trigger {
    event_type = "google.storage.object.finalize"
    resource   = google_storage_bucket.ingestion_bucket.name
  }

  entry_point = "ingest_file"

  # Inject Infrastructure details as Environment Variables
  environment_variables = {
    PROJECT_ID   = var.project_id
    DATASET_ID   = google_bigquery_dataset.warehouse.dataset_id
    TABLE_ID     = google_bigquery_table.raw_transactions.table_id
    DLQ_TOPIC_ID = google_pubsub_topic.dlq_topic.name
  }

  # Security: Run as the customized Service Account
  service_account_email = google_service_account.ingestion_sa.email
}

# ---------------------------------------------------------
# 8. IAM Permissions for the Function
# ---------------------------------------------------------
# The Function needs to READ the file from Storage
resource "google_storage_bucket_iam_member" "sa_read_bucket" {
  bucket = google_storage_bucket.ingestion_bucket.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.ingestion_sa.email}"
}

# The Function needs to PUBLISH errors to the DLQ
resource "google_pubsub_topic_iam_member" "sa_publish_dlq" {
  topic  = google_pubsub_topic.dlq_topic.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${google_service_account.ingestion_sa.email}"
}

# Grant permission to run Query Jobs (needed for dbt)
resource "google_project_iam_member" "dbt_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.ingestion_sa.email}"
}


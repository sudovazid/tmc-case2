# Data Pipeline Runbook

## SLOs (Service Level Objectives)
1.  **Data Quality:** 0 rows rejected to DLQ.
2.  **Ingestion Latency:** Data available in BigQuery within 5 minutes of file drop.

## Incident: DLQ Alert Firing
**Symptom:** The "SLO Breach: Invalid Data in DLQ" alert has fired.

**Diagnosis:**
1.  Go to the [GCP Pub/Sub Console](https://console.cloud.google.com/cloudpubsub).
2.  Select the subscription `ingestion-dlq-sub`.
3.  Pull messages to inspect the payload. Look for the `error` field.

**Remediation:**
* **If Schema Mismatch:** Contact the data provider (upstream team) to fix the format.
* **If Bug in Parser:** Fix `src/main.py`, deploy via Terraform, and re-process the file.
* **To Clear Queue:** Once resolved, acknowledge the messages in the subscription to resolve the alert.

## Incident: dbt Pipeline Failure
**Symptom:** GitHub Action fails on "Run dbt Tests".

**Remediation:**
1.  Check the GitHub Action logs.
2.  If `unique` test failed: Check for duplicate `transaction_id` in the source file.
3.  If `amount >= 0` test failed: Identify the transaction with negative amount in BigQuery.
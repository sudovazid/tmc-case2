# GCP DataOps Pipeline (Case 2)

## Overview
This repository implements a "governed" data pipeline on Google Cloud Platform (GCP). It demonstrates a robust DataOps workflow including schema-on-write validation, idempotency, automated quality gates (dbt), and infrastructure-as-code (Terraform).

## Architecture
The pipeline follows an Event-Driven Architecture:

## Project Structure
```
├── dbt_project/        # Data transformation logic & tests
├── src/                # Python Cloud Function (Ingestion logic)
├── terraform/          # Infrastructure as Code (GCP resources)
├── .github/workflows/  # CI/CD Pipeline configuration
└── RUNBOOK.md          # Operational guide for SLO breaches
```

## Setup & Deployment
1. Prerequisites
    Google Cloud Project

    Terraform >= 1.0

    GitHub Repository with Secrets configured (GCP_SA_KEY, GCP_PROJECT_ID)

2. Infrastructure Deployment

    The entire GCP footprint is managed via Terraform.

    To deploy the GCP infrastructure use terraform

    ```
    cd terraform
    terraform init
    terraform apply
    ```
3. dbt Setup (Local)

    ```
    cd dbt_project
    pip install dbt-bigquery
    dbt debug
    dbt run
    ```
Usage Guide
Ingesting Data
Upload a strictly formatted NDJSON file to the ingestion bucket:

Bash

gsutil cp data/valid.json gs://<your-bucket-name>/
Handling Failures (DLQ)
If a file contains invalid schema, it is routed to the Dead Letter Queue. Refer to RUNBOOK.md for triage steps.

CI/CD Quality Gates
Open a Pull Request.

GitHub Actions triggers dbt test.

If any data constraint fails (e.g., negative amount), the pipeline fails, preventing the merge.


---

### **Step 2: Add Screenshots (Optional but Recommended)**
To really stand out, I recommend creating an `images/` folder in your repo and adding 2 screenshots. Link them in your README.

1.  **The "Success" Proof:** A screenshot of BigQuery showing the `fct_daily_revenue` table populated with data.
2.  **The "Gate" Proof:** A screenshot of a GitHub Action run (like the one we fixed earlier) showing `dbt test` passing.
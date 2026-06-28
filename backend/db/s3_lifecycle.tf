# s3_lifecycle.tf
# Terraform infrastructure declaration for compliance retention lifecycles

resource "aws_s3_bucket" "invoice_storage" {
  bucket = "enterprise-invoice-storage-vault"
  
  tags = {
    Environment = "Production"
    Compliance  = "HIPAA-GLBA-SOX"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "invoice_lifecycle" {
  bucket = aws_s3_bucket.invoice_storage.id

  rule {
    id     = "compliance-retention-policy"
    status = "Enabled"

    # Transition active records to lower cost storage class after 90 days
    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    # Transition legacy records to long-term Glacier cold vault after 2 years
    transition {
      days          = 730
      storage_class = "GLACIER"
    }

    # Discard non-current document edits into Glacier after 30 days
    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "GLACIER"
    }
  }
}

resource "aws_s3_bucket_object_lock_configuration" "invoice_worm" {
  bucket = aws_s3_bucket.invoice_storage.id

  rule {
    default_retention {
      mode = "COMPLIANCE"
      days = 2555 # 7 years mandatory auditing retention period
    }
  }
}

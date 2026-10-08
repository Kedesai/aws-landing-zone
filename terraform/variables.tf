variable "billing_email" {
  type        = string
  description = "The billing email address for budget notifications. This must be supplied via external environment variables or secrets (e.g., TF_VAR_billing_email)."
}

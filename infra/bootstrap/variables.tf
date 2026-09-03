variable "subscription_id" {
  description = "Target Azure subscription ID."
  type        = string
}

variable "location" {
  description = "Default Azure region for foundation resources."
  type        = string
  default     = "eastus"
}

variable "github_app_display_name" {
  description = "Display name of the Entra app registration used by GitHub Actions."
  type        = string
  default     = "github-actions-portfolio"
}

variable "notification_email" {
  description = "Email address that receives budget alerts."
  type        = string
}

variable "monthly_budget_amount" {
  description = "Monthly budget cap in the subscription's billing currency."
  type        = number
  default     = 20
}

variable "budget_start_date" {
  description = "Budget period start. Must be the first day of a month, RFC3339."
  type        = string
  default     = "2026-09-01T00:00:00Z"
}

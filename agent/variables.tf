variable "mcp_docs_client_id" {
  description = "Client ID of the mcp-docs app registration (bootstrap output mcp_docs_client_id)."
  type        = string
}

variable "site_origins" {
  description = "Origins allowed to call the api from a browser."
  type        = list(string)
  default     = ["https://mastrocola.dev", "https://www.mastrocola.dev"]
}

variable "key_vault_name" {
  type    = string
  default = "kv-mastrocola-dev"
}

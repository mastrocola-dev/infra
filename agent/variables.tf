variable "mcp_docs_client_id" {
  description = "Client ID of the mcp-docs app registration (bootstrap output mcp_docs_client_id)."
  type        = string
}

variable "key_vault_name" {
  type    = string
  default = "kv-mastrocola-dev"
}

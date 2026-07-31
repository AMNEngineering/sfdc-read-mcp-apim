variable "apim_name" {
  description = "Name of the APIM instance"
  type        = string
}

variable "resource_group" {
  description = "Resource group containing the APIM instance"
  type        = string
}

variable "mcp_server_name" {
  description = "Name of the MCP server resource in APIM"
  type        = string
}

variable "display_name" {
  description = "Display name for the MCP server"
  type        = string
}

variable "description" {
  description = "Description of the MCP server"
  type        = string
  default     = ""
}

variable "backend_mcp_url" {
  description = "Backend MCP server URL (e.g., https://api.salesforce.com/platform/mcp/v1/sandbox/platform/sobject-reads)"
  type        = string
}

variable "transport_type" {
  description = "MCP transport type (StreamableHttp or SSE)"
  type        = string
  default     = "StreamableHttp"
}

variable "base_path" {
  description = "Base path for the MCP server endpoint in APIM"
  type        = string
}

variable "policy_xml_content" {
  description = "Policy XML content to apply to the MCP server"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to the MCP server"
  type        = map(string)
  default     = {}
}

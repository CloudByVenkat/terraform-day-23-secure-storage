variable "project_name" {
  description = "Project name (lowercase, no spaces)"
  type        = string
  default     = "demo"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "Canada Central"
}
variable "admin_user_object_id" {
  description = "Azure AD Object ID of admin user"
  type        = string
}

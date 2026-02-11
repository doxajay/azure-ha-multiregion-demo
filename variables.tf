variable "primary_location" {
  type    = string
  default = "canadacentral"
}

variable "secondary_location" {
  type    = string
  default = "eastus2"
}

variable "project" {
  type    = string
  default = "fcha-ha"
}

variable "sql_admin_username" {
  type    = string
  default = "sqladminuser"
}

variable "sql_admin_password" {
  type      = string
  sensitive = true
}

variable "enable_sql_secondary" {
  type    = bool
  default = false
}

variable "project_name" {
  description = "Short project/workload name used for naming resources (e.g., fcha-g08qgo)"
  type        = string
}

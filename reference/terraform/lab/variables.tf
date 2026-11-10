variable "project" {
  type    = string
  default = "rt-helpdesk"
}
variable "admin_cidr" {
  type        = string
  description = "Your current public IPv4 with /32"
  validation {
    condition     = can(cidrhost(var.admin_cidr, 0)) && endswith(var.admin_cidr, "/32")
    error_message = "Supply one administrator IPv4 address with /32."
  }
}
variable "ssh_public_key" { type = string }
variable "backup_bucket" { type = string }
variable "ci_instance_type" {
  type    = string
  default = "t3.large"
}
variable "app_instance_type" {
  type    = string
  default = "t3.xlarge"
}
variable "budget_email" { type = string }
variable "monthly_budget_usd" {
  type    = number
  default = 100
}

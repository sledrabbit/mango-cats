variable "aws_region" {
  description = "AWS region for the app"
  type        = string
  default     = "us-west-2"
}

variable "ssh_public_key_path" {
  description = "Path to the public half of your SSH deployment key"
  type        = string
  default     = "~/.ssh/mango-cats.pub"
}

variable "ssh_cidr" {
  description = "Your current public IPv4 address as a /32 CIDR, for example 203.0.113.10/32"
  type        = string

  validation {
    condition     = can(cidrhost(var.ssh_cidr, 0)) && endswith(var.ssh_cidr, "/32")
    error_message = "ssh_cidr must be a valid IPv4 /32 CIDR."
  }
}

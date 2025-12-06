variable "name" {
  description = "Name to be used on all the resources as identifier"
  type        = string
}

variable "ip_range" {
  description = "The CIDR block for the VPC."
  type        = string
}

variable "zone" {
  description = "Name of network zone."
  type        = string
  default     = "nbg1"
}
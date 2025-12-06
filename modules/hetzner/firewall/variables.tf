variable "name" {
  description = "Name to be used on all the resources as identifier"
  type        = string
}

variable "rule" {
  description = "Firewall rules"
  type = list(object({
    protocol = string
    port     = number
  }))
}

variable "apply_to" {
  type = list(object({
    label_selector = string
  }))
  default = []
}
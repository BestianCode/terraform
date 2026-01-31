variable "default_zone_id" {
  type        = string
  description = "Fallback Cloudflare Zone ID used when page_rule.zone_id is not provided."
}

variable "page_rules" {
  type = list(object({
    target   = string
    actions  = any
    priority = optional(number)
    status   = optional(string, "active")
    zone_id  = optional(string, "")
  }))
  description = "List of Cloudflare Page Rules to create. If page_rule.zone_id is empty, default_zone_id is used."
  default     = []
}

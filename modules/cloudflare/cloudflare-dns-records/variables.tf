variable "default_zone_id" {
  type        = string
  description = "Fallback Cloudflare Zone ID used when record.zone_id is not provided."
}

variable "records" {
  type = list(object({
    name    = string
    type    = string
    dest    = string
    proxy   = string
    zone_id = optional(string, "")
  }))
  description = "List of DNS records to create in Cloudflare. If record.zone_id is empty, default_zone_id is used."
  default     = []
}

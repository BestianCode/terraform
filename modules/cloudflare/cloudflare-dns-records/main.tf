resource "cloudflare_dns_record" "records" {
  for_each = { for idx, record in var.records : idx => record }
  zone_id  = try(each.value.zone_id, "") != "" ? each.value.zone_id : var.default_zone_id
  name     = each.value.name
  type     = each.value.type
  content  = each.value.dest
  proxied  = each.value.proxy == "true" ? true : false
  ttl      = each.value.proxy == "true" ? 1 : 300
  comment  = "Managed by Terraform"
}

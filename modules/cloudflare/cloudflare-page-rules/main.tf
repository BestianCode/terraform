resource "cloudflare_page_rule" "rules" {
  for_each = { for idx, rule in var.page_rules : idx => rule }

  zone_id  = try(each.value.zone_id, "") != "" ? each.value.zone_id : var.default_zone_id
  target   = each.value.target
  priority = try(each.value.priority, null)
  status   = try(each.value.status, "active")
  actions  = each.value.actions
}

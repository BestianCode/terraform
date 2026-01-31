# cloudflare-dns-records

Creates Cloudflare DNS records.

Key behavior:
- If a record does not specify `zone_id` (or it is an empty string), the module uses `default_zone_id`.
- If `proxy == "true"`, the record is created with `proxied = true` and `ttl = 1` (Cloudflare automatic TTL).

## Usage

```hcl
module "cloudflare_dns_records" {
  source          = "git::https://github.com/BestianCode/terraform.git//modules/cloudflare/cloudflare-dns-records?ref=1.1.0"
  default_zone_id = var.CLOUDFLARE_ZONE_ID

  records = [
    {
      name  = "grafana.example.com"
      type  = "CNAME"
      dest  = "in.example.com"
      proxy = "true"
      # zone_id = "" # optional
    },
    {
      name   = "api.other-zone.example.com"
      type   = "A"
      dest   = "203.0.113.10"
      proxy  = "false"
      zone_id = "0123456789abcdef0123456789abcdef" # optional per-record override
    }
  ]
}
```

## Inputs

- `default_zone_id` (string, required): Fallback Cloudflare Zone ID.
- `records` (list(object), optional): Records to create.
  - `name` (string)
  - `type` (string)
  - `dest` (string)
  - `proxy` (string): Use `"true"` or `"false"`.
  - `zone_id` (string, optional): Override zone for this record.

## Notes

- Configure the Cloudflare provider (API token, etc.) in the *calling* root module, not inside this module.

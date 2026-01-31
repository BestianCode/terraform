# cloudflare-page-rules

Creates Cloudflare Page Rules.

Key behavior:
- If a rule does not specify `zone_id` (or it is an empty string), the module uses `default_zone_id`.

## Usage

Example forwarding URL 301 rule:

```hcl
module "cloudflare_page_rules" {
  source          = "git::https://github.com/BestianCode/terraform.git//modules/cloudflare/cloudflare-page-rules?ref=1.1.0"
  default_zone_id = var.CLOUDFLARE_ZONE_ID

  page_rules = [
    {
      target   = "www.example.com/*"
      priority = 100
      status   = "active"
      actions = {
        forwarding_url = {
          url         = "https://example.org"
          status_code = 301
        }
      }
      # zone_id = "" # optional
    }
  ]
}
```

## Inputs

- `default_zone_id` (string, required): Fallback Cloudflare Zone ID.
- `page_rules` (list(object), optional): Page Rules to create.
  - `target` (string): URL pattern, e.g. `"www.example.com/*"`.
  - `actions` (any): Passed directly to `cloudflare_page_rule.actions`.
  - `priority` (number, optional)
  - `status` (string, optional): Defaults to `"active"`.
  - `zone_id` (string, optional): Per-rule zone override.

## Notes

- Configure the Cloudflare provider (API token, etc.) in the *calling* root module, not inside this module.

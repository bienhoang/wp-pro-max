# `wp-plugin.json` Manifest Contract

`wp-plugin.json` is the single source of truth for a standalone plugin build.
It lives in the **target plugin project root** (the `./<slug>/` directory created
by `/wp-pro-max:plugin new <slug>`).

## Field reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `version` | string | yes | Manifest schema version. Always `"1"`. |
| `plugin.slug` | string | yes | Kebab-case plugin slug (`^[a-z0-9-]+$`). |
| `plugin.name` | string | yes | Human-readable plugin name. |
| `plugin.namespace` | string | yes | PHP namespace (`^[A-Za-z][A-Za-z0-9_]*$`). |
| `plugin.textDomain` | string | yes | Text domain (`^[a-z0-9-]+$`). Defaults to `plugin.slug`. |
| `plugin.description` | string | no | Short plugin description. |
| `plugin.version` | string | no | Plugin version (used in readme/zip). Defaults to `"0.1.0"`. |
| `architecture` | string | yes | Always `"oop"` for v1. |
| `features[]` | array | no | Enabled generators. Each entry has `type` and optional `name`/`options`. |
| `tooling.composer` | boolean | no | Whether `composer.json` is used (auto-true after dev loop scaffolding). |
| `tooling.phpcs` | boolean | no | Whether `phpcs.xml.dist` is present. |
| `tooling.phpunit` | boolean | no | Whether PHPUnit tests are present. |
| `tooling.blockBuild` | boolean | no | Whether a block has been added (Node tooling). |
| `env.port` | integer | no | wp-env port. |
| `env.phpVersion` | string | no | wp-env PHP version. |
| `env.wpVersion` | string | no | wp-env WordPress version. |
| `progress.<stage>` | object | no | Resume state: `status`, `updatedAt`, `notes`. |

## Derivation rules

When `wpplugin_init <slug>` is called without a namespace or name:

- `slug` is used exactly as given.
- `textDomain` = `slug`.
- `namespace` = PascalCase(slug): `acme-widgets` → `AcmeWidgets`.
- `name` = Title Case(slug): `acme-widgets` → `Acme Widgets`.

Override examples:

```bash
wpplugin_init acme-widgets AcmeWidgets "Acme Widgets"
wpplugin_init my-plugin CustomNS "My Plugin"
```

## `features[]` entries

```json
{"type": "cpt", "name": "Item", "restExposed": false}
{"type": "taxonomy", "name": "ItemCategory"}
{"type": "settings"}
{"type": "rest", "name": "Item"}
{"type": "shortcode", "name": "Item"}
{"type": "block", "name": "Hero"}
```

## Complete example

```json
{
  "version": "1",
  "plugin": {
    "slug": "acme-widgets",
    "name": "Acme Widgets",
    "namespace": "AcmeWidgets",
    "textDomain": "acme-widgets",
    "version": "0.1.0"
  },
  "architecture": "oop",
  "features": [
    {"type": "cpt", "name": "Widget", "restExposed": true},
    {"type": "taxonomy", "name": "WidgetCategory"},
    {"type": "settings"},
    {"type": "rest", "name": "Widget"},
    {"type": "shortcode", "name": "Widget"}
  ],
  "tooling": {
    "composer": true,
    "phpcs": true,
    "phpunit": true,
    "blockBuild": false
  },
  "env": {
    "port": 8888,
    "phpVersion": "8.2",
    "wpVersion": "latest"
  },
  "progress": {
    "scaffold": {"status": "done", "updatedAt": "2026-06-26T10:00:00Z", "notes": ""}
  }
}
```

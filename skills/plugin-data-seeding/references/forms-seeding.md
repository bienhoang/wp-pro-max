# Forms Seeding — Contact Form 7 / WPForms

Seed form definitions so the contact page actually works. Prefer WP-CLI;
fall back to a **guarded** `wp db query` only when a setting has no CLI path,
and always run a `SELECT` preview before any `INSERT`/`UPDATE`.

## Contact Form 7 (`contact-form-7`)

A CF7 form is a `wpcf7_contact_form` post. The form template, mail, messages,
and additional settings live in postmeta (`_form`, `_mail`, `_mail_2`,
`_messages`, `_additional_settings`).

### Create idempotently (one payload entry)

Emit the form as a `posts[]` entry; its `_form` template and `_mail` settings go
in `meta`. `_mail` is a JSON **object** — the runtime serializes it correctly via
the WP API (do **not** hand-serialize into SQL), and compares it array-aware so
re-runs are no-ops:

```json
{ "slug": "contact-form", "title": "Contact form", "type": "wpcf7_contact_form", "content": "",
  "meta": {
    "_form": "<label>Your name [text* your-name]</label>\n<label>Your email [email* your-email]</label>\n<label>Message [textarea your-message]</label>\n[submit \"Send\"]",
    "_mail": {
      "active": true,
      "subject": "[your-subject]",
      "sender": "[your-name] <wordpress@example.test>",
      "recipient": "[admin_email]",
      "body": "From: [your-name] <[your-email]>\n\n[your-message]",
      "additional_headers": "Reply-To: [your-email]",
      "attachments": "", "use_html": false, "exclude_blank": false
    }
  } }
```

The post is keyed by slug, so re-running creates no duplicate form.

### Wire the shortcode into the contact page

Shortcode insertion targets an existing page by known ID and is guarded by a
presence check, so it belongs in the QA step (not the seed payload):

```bash
contact_id="$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" post list --post_type=page --name=contact --field=ID | head -n1)"
form_id="$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" post list --post_type=wpcf7_contact_form --name=contact-form --field=ID | head -n1)"
if ! bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" post get "$contact_id" --field=content | grep -q 'contact-form-7'; then
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" post update "$contact_id" \
    --post_content="$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" post get "$contact_id" --field=content)

[contact-form-7 id=\"$form_id\" title=\"Contact form\"]"
fi
```

## WPForms (`wpforms-lite`)

A WPForms form is a `wpforms` CPT post whose **`post_content` is the form JSON**
(fields, settings, notifications). Seed it as a `posts[]` entry whose `content` is
the form-definition JSON string (keep the `id` stable across runs):

```json
{ "slug": "main-contact", "title": "Contact", "type": "wpforms",
  "content": "{\"id\":\"1\",\"fields\":{…},\"settings\":{…}}" }
```

## Guarded raw DB writes (last resort)

If and only if no CLI/PHP path exists, follow the contract: **preview, then
write**.

```bash
# 1) DRY-RUN preview — show what would be affected (SELECT mirrors the WHERE)
wp db query "SELECT meta_id, meta_key FROM $(wp db prefix)postmeta \
  WHERE post_id=$form_id AND meta_key='_some_setting';"

# 2) Only after reviewing the rows above, perform the write
wp db query "UPDATE $(wp db prefix)postmeta SET meta_value='...' \
  WHERE post_id=$form_id AND meta_key='_some_setting';"
```

Rules:

- Never run an `UPDATE`/`DELETE`/`INSERT` without first running the matching
  `SELECT` and confirming the row set.
- Use `$(wp db prefix)` — never hardcode `wp_`.
- Take a backup (`wp db export`) before any multi-row mutation.
- Prefer `wp eval` + WordPress APIs over raw SQL whenever an API exists; SQL is
  the exception, not the rule.

## Idempotency summary

- Form posts are keyed by slug → no duplicate forms on re-run.
- Mail/settings meta are written by the runtime's WP-API call and compared
  array-aware, so re-runs converge to the same value (`updated:0`).
- Shortcode insertion is guarded by a `grep` presence check.

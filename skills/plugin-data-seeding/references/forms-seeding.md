# Forms Seeding — Contact Form 7 / WPForms

Seed form definitions so the contact page actually works. Prefer WP-CLI;
fall back to a **guarded** `wp db query` only when a setting has no CLI path,
and always run a `SELECT` preview before any `INSERT`/`UPDATE`.

## Contact Form 7 (`contact-form-7`)

A CF7 form is a `wpcf7_contact_form` post. The form template, mail, messages,
and additional settings live in postmeta (`_form`, `_mail`, `_mail_2`,
`_messages`, `_additional_settings`).

### Create idempotently

```bash
# 1) Create the form post keyed by slug (helper short-circuits if it exists)
form_id="$(ensure_post contact-form "Contact form" "" wpcf7_contact_form)"

# 2) Set the form template (the [tags] users fill in)
read -r -d '' CF7_FORM <<'HTML' || true
<label>Your name [text* your-name]</label>
<label>Your email [email* your-email]</label>
<label>Message [textarea your-message]</label>
[submit "Send"]
HTML
ensure_acf_value "$form_id" _form "$CF7_FORM"

# 3) Mail settings (serialized array — set via PHP for correct serialization)
wp eval '
  $id = '"$form_id"';
  $mail = [
    "active"     => true,
    "subject"    => "[your-subject]",
    "sender"     => "[your-name] <wordpress@example.test>",
    "recipient"  => get_option("admin_email"),
    "body"       => "From: [your-name] <[your-email]>\n\n[your-message]",
    "additional_headers" => "Reply-To: [your-email]",
    "attachments"=> "",
    "use_html"   => false,
    "exclude_blank" => false,
  ];
  update_post_meta($id, "_mail", $mail);
'
```

`update_post_meta` via `wp eval` serializes the PHP array correctly — do **not**
hand-serialize into a `wp db query`. Idempotency: the post is keyed by slug;
re-setting identical meta is harmless, and `ensure_acf_value` skips unchanged
string meta.

### Wire the shortcode into the contact page

```bash
contact_id="$(_seed_find_post_by_slug contact page)"
# Only update if the shortcode is not already present
if ! wp post get "$contact_id" --field=content | grep -q 'contact-form-7'; then
  wp post update "$contact_id" \
    --post_content="$(wp post get "$contact_id" --field=content)

[contact-form-7 id=\"$form_id\" title=\"Contact form\"]"
fi
```

## WPForms (`wpforms-lite`)

A WPForms form is a `wpforms` CPT post whose **`post_content` is the form JSON**
(fields, settings, notifications). Seed by creating the post with the JSON body:

```bash
form_id="$(ensure_post main-contact "Contact" ./forms/contact.wpforms.json wpforms)"
```

where `./forms/contact.wpforms.json` is the WPForms form definition (a JSON
object with `fields`, `settings`, `id`). Keep the `id` stable across runs.

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

- Form posts are keyed by slug via `ensure_post` → no duplicate forms on re-run.
- Mail/settings meta written by `update_post_meta`/`ensure_acf_value` converge to
  the same value, so re-runs are no-ops.
- Shortcode insertion is guarded by a `grep` presence check.

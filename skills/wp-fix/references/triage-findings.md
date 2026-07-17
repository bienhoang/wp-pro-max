# Triage: static PHP findings

Gate 1 of `wp-fix`. For every finding in `.supported[]`, read the real source at
`file:line` and decide: **confirmed**, **false positive**, or **needs a human**.

`scripts/audit-static.sh` matches with `grep -HnIE` (`:177`). It is a regex over
one line. It cannot see that the value was escaped two lines up, sanitised in the
callee, or that the "user input" is a hardcoded constant. Triage is where that
context gets applied — skipping it means proposing diffs for code that is already
correct.

## Identity

A static finding is identified by **`id` + `file` + `line`**. `id` alone is a rule
slug reused across every file and line it matches (`add_static_finding()` at
`:85`, loop at `:165`).

## The three verdicts

| Verdict | Action | Required |
|---|---|---|
| confirmed | carry to the propose step | a concrete fix pattern |
| false positive | `fix_record dismissed` | **a reason — mandatory** |
| needs a human | `fix_record remaining` | a reason + what you'd need to decide |

A dismissal without a reason is indistinguishable from a finding that was
silently dropped. Always record why.

## Per-rule signatures

### `wpcs-output-not-escaped` — pattern `\becho\s+.*\$_(GET|POST|REQUEST|COOKIE)` (XSS)

Category is `code-style`; the real risk is **XSS**. Do not downgrade it.

False positive when:
- The value passes through an escaping helper first —
  `echo acme_out($_GET['q'])` where `acme_out()` wraps `esc_html()`. **Read the
  helper before dismissing**; a helper named like an escaper that does not escape
  is the exact bug this rule exists to catch.
- It is inside a comment or a heredoc that is never emitted.

Confirmed → wrap at the output site, choosing by context:

| Context | Function |
|---|---|
| text node | `esc_html()` |
| attribute value | `esc_attr()` |
| URL | `esc_url()` |
| rich text that must keep markup | `wp_kses_post()` |
| inside a `<script>` | `wp_json_encode()` |

`esc_html()` is the safe default. Escaping a URL with `esc_html()` "works" but
mangles `&` — pick by context, not by habit.

### `wpcs-direct-db-no-prepare` — pattern `\$wpdb->(get_results|get_col|get_var|query)\s*\(.*\$` (SQLi)

The pattern fires on **any** `$` inside the call, including an already-prepared
statement and `$wpdb->prefix`.

False positive when:
- `$wpdb->prepare()` is on a prior line and the finding line only passes the
  prepared string: `$sql = $wpdb->prepare(...); $wpdb->query($sql);`
- The only interpolation is `{$wpdb->prefix}` or `$wpdb->posts` — table names
  cannot be placeholders. Note it and dismiss.

Confirmed → `$wpdb->prepare()` with `%s` / `%d` / `%f`. Never `%s` in quotes
(`'%s'` double-quotes it). Table names stay interpolated; **values** become
placeholders.

**Needs a human** when the query is assembled across several lines or a variable
`IN (...)` list — the placeholder count is dynamic and a mechanical rewrite is
likely to be wrong. Record it in `fix.remaining[]` with the reason.

### `wpcs-missing-sanitize` — pattern `\$_(GET|POST|REQUEST|COOKIE|SERVER)`

The broadest rule: it fires on **every** superglobal occurrence, including one
already wrapped in `sanitize_text_field()`. Expect a high false-positive rate.

False positive when:
- Already sanitised on the same or a prior line.
- Sanitised inside the callee it is passed to (read the callee).
- It is `isset($_GET['x'])` / `empty($_POST['y'])` — an existence check consumes
  no value.
- `$_SERVER['REQUEST_METHOD']` compared against a literal.

Confirmed → sanitise by intent, and `wp_unslash()` **before** sanitising:

| Intent | Function |
|---|---|
| plain text | `sanitize_text_field( wp_unslash( $_POST['x'] ) )` |
| email | `sanitize_email()` |
| integer id | `absint()` / `intval()` |
| slug | `sanitize_key()` |
| URL | `esc_url_raw()` |
| textarea | `sanitize_textarea_field()` |

### `wpcs-missing-nonce` — `audit-static.sh:181-188` (CSRF)

File-level, not line-level: it fires when a file registers `wp_ajax_*` but
contains neither `check_ajax_referer` nor `wp_verify_nonce` **anywhere in that
file**. The `line` points at the first `add_action` (`:183`).

False positive when:
- The nonce is verified in a callee defined in **another file** (a shared
  `verify_request()` helper). The scanner greps one file; follow the call.
- The handler is registered but genuinely public and read-only — rare; justify it
  explicitly rather than assuming.

Confirmed → `check_ajax_referer( 'action_name', 'nonce_field' )` as the first
statement of the callback, plus a `wp_create_nonce()` on the emitting side and a
capability check (`current_user_can()`) — a nonce proves intent, not permission.

Because the finding is file-level, the fix usually touches the **callback**, not
the `add_action` line. Anchor to the callback and say so in the diff.

### `sec-base64-decode` — pattern `\bbase64_decode\s*\(`

Fires on any occurrence. **False positives are the norm.**

False positive when: decoding a bundled font/data-URI, a known-constant literal,
or a documented third-party API payload with a fixed shape.

Confirmed only when the decoded value is attacker-controlled AND flows somewhere
dangerous (`eval`, `unserialize`, `include`, a file write). Then the fix is not
"remove base64_decode" — it is validating the decoded data at the sink.
Usually → `fix.remaining[]` with the data-flow noted.

### `sec-unserialize` — pattern `\bunserialize\s*\(`

False positive when the input is trusted and internal — a `get_option()` value
the theme itself wrote. (WordPress already unserialises option values, so
`unserialize(get_option(...))` is usually a *different* bug: a double
unserialise.)

Confirmed → `unserialize( $data, ['allowed_classes' => false] )` when the shape
must stay PHP-serialised, or `json_decode()` when the format is yours to choose.
Attacker-controlled input → **object injection**, not a style nit.

### `sec-eval` · `sec-unsafe-include` · `sec-file-write-user-input`

Critical/high, rarely false, and **almost never mechanically fixable** — each
needs a redesign (allowlist, hardcoded map, path validation), not a wrapper.

Default to `fix.remaining[]` with a concrete recommendation. Only propose a diff
when the correct replacement is unambiguous from the surrounding code — e.g.
`include($_GET['page'] . '.php')` → a hardcoded allowlist map where the full set
of legal pages is visible in the same file.

Never "fix" `eval()` by escaping its argument. The fix is deleting it.

## After the fix: the finding usually stays

Seven of the nine rules **still match after a correct fix** — they grep for a
risky construct, not for a defect:

```php
// Before — genuinely vulnerable:
echo $_GET['q'];

// After — correct, and STILL flagged wpcs-missing-sanitize:
$q = sanitize_text_field( wp_unslash( $_GET['q'] ?? '' ) );
echo esc_html( $q );
```

The rule's pattern is bare `\$_(GET|POST|…)`. Any superglobal read matches it,
forever. The same is true of `$wpdb->query( $wpdb->prepare(…) )` under
`wpcs-direct-db-no-prepare`, and `unserialize( $d, ['allowed_classes' => false] )`
under `sec-unserialize`.

Gate 3 knows this — those come back as `stillFlagged[]`, not as a failure
(`FIX_CLEARING_RULES_JSON` in `scripts/wp-fix-lib.sh`). Two consequences:

- **Do not re-fix a `stillFlagged` finding on the next run.** It is not evidence
  the fix failed. Check the source, not the finding list.
- **Never delete the superglobal read to make the finding go away.** Silencing the
  scanner by removing functionality is not a fix — it is the worst possible
  outcome of a green gate.

Only `sec-eval` (the fix deletes `eval()`) and `wpcs-missing-nonce` (an absence
check — adding the nonce satisfies it) actually clear.

## Batch note

Propose one finding at a time, even when a file holds five. Batch approval is a
v2 question, and only once real usage shows the per-finding loop is the actual
friction.

# Playbook: PHP fatal / white screen (WSOD)

Symptoms: "trắng trang", white screen, HTTP 500, "There has been a critical error
on this website".

## 1. Evidence first

A white screen is a *class*, not a cause. Never propose a fix before you have the
actual fatal text — the guess rate is near-total otherwise.

### Reading `debug.log`

`scripts/wp-env-bootstrap.sh:100-102` sets `WP_DEBUG_LOG: true`, so WordPress
**does** write `wp-content/debug.log` inside the container. But `:106` maps only
the theme destination (plus `wp-content/uploads/wppm-src` when an optimized copy
exists) — **`debug.log` is not mapped to the host.** There is no host path to
`cat`, and inventing one produces a confident "file not found" that looks like
"no errors".

Read it **through WP-CLI, in-container**, deriving the path from `WP_CONTENT_DIR`
rather than hardcoding one (the `skills/wp-performance-backend/SKILL.md:156`
idiom; hardcoding container paths is forbidden by `CLAUDE.md`):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" eval '$f = WP_CONTENT_DIR . "/debug.log"; echo file_exists($f) ? implode("", array_slice(file($f), -80)) : "NO_DEBUG_LOG";'
```

If that prints `NO_DEBUG_LOG`, the log simply has not been written yet — that is
information, not failure.

### When WP-CLI itself is down

**This is the common case.** A fatal in `functions.php` breaks WP-CLI too, so
`wpx` cannot bootstrap and cannot read the log. Do not report "no errors found"
because a probe you could not run returned nothing.

Fall back, in order:

1. **The text the user pasted.** A WSOD screenshot or the browser's error output
   usually names the file and line outright. Ask for it — it is the highest-value
   evidence available and costs one question.
2. **`php -l` across the theme.** Catches every parse error without WordPress:
   ```bash
   find "$THEME_PATH" -name '*.php' -print0 | xargs -0 -n1 php -l
   ```
3. **Read the most recent change.** `fix.backupDir` from a previous run, or
   `git diff` in the target project. A site that worked an hour ago and does not
   now has a small suspect list.

## 2. Classify the fatal

| Fatal text | Class | Typical cause |
|---|---|---|
| `syntax error, unexpected …` | Parse error | Stray brace/semicolon; `php -l` locates it exactly |
| `Call to undefined function <wp fn>()` | Load order | Theme code running before WordPress loads it — hooked too early, or called at file top level |
| `Call to undefined function <acf/elementor fn>()` | Missing dependency | Plugin inactive; guard with `function_exists()` |
| `Cannot redeclare <fn>()` | Namespace collision | Un-namespaced theme function; prefix with the theme slug (`CLAUDE.md`) |
| `Too few arguments to function` | Wrong hook signature | Filter callback missing a parameter, or `add_filter` `$accepted_args` wrong |
| `Class "X" not found` | Autoload | Missing `require`, or Composer autoload not loaded |
| `Allowed memory size exhausted` | Not a syntax bug | Usually infinite recursion — a hook that triggers itself |
| `syntax error` + `match`/`enum`/`readonly` | PHP version | Code newer than the container's PHP (`wp-build.json` `env.phpVersion`) |

## 3. Fix patterns

**Called too early** — move the call into a hook:

```php
// Fatal: get_option() at file top level, before WordPress loads.
add_action( 'after_setup_theme', function () {
    $value = get_option( 'acme_setting' );
} );
```

**Missing dependency** — guard, and fail visibly rather than fataling:

```php
if ( ! function_exists( 'get_field' ) ) {
    return; // ACF inactive — degrade, don't fatal.
}
```

**Redeclare** — namespace with the theme slug:

```php
if ( ! function_exists( 'acme_render_card' ) ) {
    function acme_render_card( $args ) { /* … */ }
}
```

**PHP version** — confirm the target before rewriting syntax:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" eval "echo PHP_VERSION;"
```

## 4. WSOD recovery

If the theme itself is fatal, the site is unreachable and no probe verifies
anything. Recover first, then diagnose from a working site:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" theme activate twentytwentyfour
```

`AskUserQuestion` before switching themes — it is visible on a live site, and on
a local wp-env build it is cheap. Record it in `fix.runtimeChanges[]` and
**switch back** once the fatal is fixed. Leaving a user on a fallback theme is
not a fix.

## 5. Verification limits — state them

With wp-env down, the only honest verification is:

- `php -l` passes on every changed file.
- `fix_static_rescan` introduces no new static findings.
- The user confirms the site loads.

Do not claim more. "The syntax is now valid and the static scan is clean; I could
not reach wp-env to load the page — can you confirm it renders?" is the accurate
report. A `verified: true` that rests on a probe that never ran is worse than an
honest `verified: false`.

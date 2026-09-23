# 26-45 · The sign-in screen is not the mockup's sign-in screen

- **Stage**: 26
- **Status**: ready
- **Found**: 2026-09-23, reading the approved mockup Artifact ("AGO Chat для Android",
  `8b4fb3a8-ddc0-4b2f-81ce-81d13c30a9d3`) against `ago-android` `main` at `ad2859b`.

## Found

This is the first surface anyone sees, and it is the one screen in the app that has had no fidelity
pass at all — `26-23`, `26-28`, `26-30`, `26-32` and `26-34` all landed elsewhere.

The mockup:

```html
<div class="signin">
  <div class="wordmark">AGO</div>
  <div class="tag2">Чат и записи для вашего сайта</div>
  <div class="btn fill wide">Войти</div>
  <div class="btn out wide" style="margin-top:10px">Создать аккаунт</div>
</div>
```

```css
.signin{flex:1; display:flex; flex-direction:column; justify-content:center; padding:0 28px; gap:10px}
.wordmark{font-family:"Unbounded",sans-serif; font-weight:700; font-size:34px; letter-spacing:-.02em; color:var(--brand)}
.signin .tag2{font-size:14px; color:var(--ink-soft); margin-bottom:22px}
.btn{height:38px; border-radius:19px; display:flex; align-items:center; justify-content:center;
     font-size:13.5px; font-weight:700; border:1px solid transparent}
.btn.fill{background:var(--brand); color:#fff}
.btn.wide{width:100%; flex:none}
```

Four things differ, and three of them are not judgement calls:

1. **The wordmark is «AGO», in brand colour, at display size.** The app draws `app_name` — which is
   `AGO Chat`, the full product name — in `headlineLarge` (20sp) and default ink.
2. **The tagline is different copy.** Mockup: «Чат и записи для вашего сайта». App: «Отвечайте
   посетителям, где бы вы ни были».
3. **The block is left-aligned**, vertically centred in a `28px` gutter. The app centres everything
   horizontally.
4. **«Войти» is a full-width pill.** The app draws a default-width Material `Button` sized to its own
   label.

## What is actually true today, confirmed against real code

- `app/src/main/kotlin/ago/chat/android/signin/SignInScreens.kt:126-143`:

  ```kotlin
  @Composable
  private fun LaunchScreen(
      modifier: Modifier,
      onSignIn: () -> Unit,
  ) {
      Centred(modifier) {
          Text(text = stringResource(R.string.app_name), style = MaterialTheme.typography.headlineLarge)
          Text(
              text = stringResource(R.string.sign_in_tagline),
              style = MaterialTheme.typography.bodyLarge,
              textAlign = TextAlign.Center,
              modifier = Modifier.padding(top = 8.dp, bottom = 32.dp),
          )
          Button(onClick = onSignIn) {
              Text(text = stringResource(R.string.sign_in_action))
          }
      }
  }
  ```

- `Centred` (`:289-301`) is `horizontalAlignment = Alignment.CenterHorizontally` — shared by the six
  other pre-session arms in this file, all of which are short centred messages for which centring is
  right. The launch screen is the one arm that is not that shape.
- `app/src/main/res/values/strings.xml`:
  - `app_name` is `AGO Chat`, and its own comment says why it must not be translated or reworded — it
    is the brand name, and it is also the launcher label. The mockup's wordmark is the shorter `AGO`,
    which is a *display* string, not the app's name.
  - `sign_in_tagline` is `Отвечайте посетителям, где бы вы ни были`.
- The display type role exists: `AgoTypography.displayLarge` is `AgoFontDisplay` SemiBold 22sp
  (`ui/theme/Type.kt:57`), whose own comment names its purpose as "the shell wordmark, tokens.css's
  own `--ago-text-display`". It is 22sp, not 34px — `Type.kt`'s header states the rule this item must
  respect: "no Manrope/Unbounded/JetBrains Mono `.ttf` is bundled with the app… `FontFamily.SansSerif`
  stands in". The mockup's `34px`/Unbounded is not reachable today and should not be faked with an
  arbitrary `34.sp` on the system sans; use `displayLarge`, and if the size is genuinely wrong at 22sp
  say so in the report rather than inventing a literal.
- The brand colour exists as `MaterialTheme.colorScheme.primary` (`Theme.kt` binds `AgoBrandLight`).

## Scope

One promise: **the launch screen is laid out and worded the way the mockup lays it out and words it.**

1. **The wordmark** — a new string (`sign_in_wordmark`, «AGO»), *not* `app_name`: the launcher label
   and a display wordmark are two different strings that happen to share a prefix, and sharing one is
   how a later rename of one silently changes the other. Rendered in `displayLarge` and
   `colorScheme.primary`.
2. **The tagline copy** becomes «Чат и записи для вашего сайта».
3. **The block left-aligns** and sits in the mockup's own `28dp` gutter, vertically centred. This arm
   stops using `Centred`; the other six arms keep it unchanged.
4. **«Войти» becomes a full-width button**, `fillMaxWidth()`, at the mockup's `.btn` height and
   stadium radius.

## Out of scope

- **«Создать аккаунт».** `SignInScreens.kt:117-125` already settles this deliberately: the
  registration form is not built, and "a button that led nowhere would be worse than its absence. It
  arrives with the form." Unchanged, and the mockup's second button stays undrawn until then.
- **Naming a deployment anywhere on this screen.** Same doc comment, and the mockup's own caption
  («Адрес окружения убран») agrees. Nothing in this item may add a hostname.
- **Bundling the real Unbounded/Manrope font files.** `26-10` scoped that out and this item does not
  reopen it; it is a `Type.kt` change made once when somebody decides to, not a sign-in screen change.
- The six other pre-session arms in this file.

## Done when

- [ ] The launch screen shows «AGO» in brand colour at display size, left-aligned.
- [ ] The tagline reads «Чат и записи для вашего сайта».
- [ ] «Войти» is full-width.
- [ ] `app_name` is unchanged and the launcher still reads «AGO Chat».
- [ ] No hostname, environment name or API origin appears anywhere on the screen.
- [ ] The other six `SignInHost` arms render exactly as before.
- [ ] `./gradlew ktlintCheck lint test assembleDebug` green.
- [ ] Checked against the mockup on a real device, in both light and dark.

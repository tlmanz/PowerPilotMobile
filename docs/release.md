# Play Store release (CircleCI)

How a commit becomes a build on Google Play's internal testing track. The
pipeline is `.circleci/config.yml`, after klutch-app's (its
`docs/14-play-release.md` has the longer story behind each choice).

```
push a branch  ──► verify             analyze · format · tests · release-notes dry run
push v1.0.1    ──► verify
                   build_aab          signed AAB, versionCode = number of v* tags
                   publish_internal   release notes ← Gemini, from the code diff
                                      fastlane → internal testing track
```

**Nothing goes beyond internal testing.** Promoting a release is a decision you
make in the Play Console.

## One-time setup

### 1. Play Console

1. The app exists as **com.mannapperuma.powerpilot**. The package name can
   never change.
2. *Testing → Internal testing → Testers*: an email list with your Google
   account. Testers see nothing until they open the opt-in link and accept.
3. **The first upload is manual.** The Play API can't create an app's first
   release, so 1.0.0 (versionCode 1) went up by hand, with Play App Signing on.
   Tag that commit `v1.0.0` so the tag count and Play agree; when the tag
   reaches CI, `publish_internal` sees Play already holds versionCode 1 and
   skips the upload.

### 2. The shared upload key

One upload key signs every app's uploads: the one created for PowerPilot,
`~/.config/powerpilot/upload-keystore.jks`, alias `upload` (its certificate
says `OU=Personal`, nothing app-specific). Google holds each app's *app
signing* key (Play App Signing), so sharing the upload key shares nothing
users' phones check. The trade: if it leaks, it can upload to every app that
uses it, until Play support resets each one.

Play ties an app to the upload key of its first accepted upload, so a new app's
first bundle must be signed with this key. (klutch-app predates it and stays on
its own key and its own `klutch-play` context.)

Keep the file and its password in a password manager. For local release builds,
`android/key.properties` (git-ignored) in each app:

```properties
storeFile=~/.config/powerpilot/upload-keystore.jks
storePassword=…
keyAlias=upload
keyPassword=…
```

Without it, release builds fall back to the debug key, which Play refuses.

### 3. One service account for the Play developer account

The Play API logs in as a Google Cloud service account, and one is enough for
every app in the developer account: access is granted app by app.

1. Play Console → *Setup → API access*: link a Google Cloud project, then create
   a service account there (*IAM → Service accounts*) and *Keys → Add key →
   JSON*. Or reuse one you already have, such as klutch-app's: you need its
   JSON key file, since CircleCI won't show the saved one again.
2. Play Console → *Users and permissions* → the service account (invite its
   email if it isn't listed) → *App permissions → Add app* → each app, with
   *Release to testing tracks* and *View app information*. Permissions are
   granted here, not in Google Cloud.
3. Check it before trusting the pipeline (a `validate_only` upload):

   ```sh
   make build-aab
   cd android && bundle install && PLAY_JSON_KEY_FILE=/path/to/key.json bundle exec fastlane validate
   ```

### 4. CircleCI: the shared play-release context

1. *Organization Settings → Contexts → Create* `play-release`, once, with:

   | Variable | Value |
   |---|---|
   | `ANDROID_KEYSTORE_BASE64` | `base64 -i ~/.config/powerpilot/upload-keystore.jks \| pbcopy` |
   | `ANDROID_KEYSTORE_PASSWORD` | the keystore password |
   | `ANDROID_KEY_ALIAS` | `upload` |
   | `ANDROID_KEY_PASSWORD` | the key password (the same one, for a PKCS12 keystore) |
   | `PLAY_SERVICE_ACCOUNT_JSON_BASE64` | `base64 -i key.json \| pbcopy` (step 3) |
   | `GEMINI_API_KEY` | [aistudio.google.com/apikey](https://aistudio.google.com/apikey); optional, without it the notes say "Stability and performance improvements." |

   CircleCI never shows a saved value again, so these come from the files and
   the key page, not from another context.
2. *Projects → Set Up Project* → the app's repo, using its
   `.circleci/config.yml`. If `play-release` has project restrictions, add the
   project.
3. The context is attached to `verify` on branch pushes too, so the
   release-notes dry run calls Gemini for real; every app's branch builds can
   read the shared upload key and the Play key. In *each* project's *Project
   Settings → Advanced*: **"Pass secrets to builds from forked pull requests"
   off** (or a fork's pull request could read them), and **"Only build pull
   requests" off** (or tags never build).

## Adding another app

Copy the pipeline, change two things, and do the Play side once:

1. **Copy** `.circleci/config.yml`, `Makefile`, `tool/gen_changelog.py`,
   `android/Gemfile`, `android/Gemfile.lock` and `android/fastlane/` (without
   the changelogs), plus the signing block and `import java.util.Properties`
   from `android/app/build.gradle.kts`, the `formatter:` lines of
   `analysis_options.yaml` and the release lines of `.gitignore`.
2. **Change** `package_name` in `android/fastlane/Appfile`, and `APP_NAME` and
   `APP_DESCRIPTION` at the top of `tool/gen_changelog.py`. Nothing else names
   the app. (`priority()` there ranks `lib/ui/screens/` first; adjust it if the
   new app's screens live elsewhere.)
3. **Version** the pubspec as `version: 1.0.0`, no `+build`: the versionCode is
   the tag count.
4. **Play Console:** create the app, make the first upload by hand (`git tag
   v1.0.0`, `make build-aab`, upload) signed with the shared key, then add the
   app to the service account's permissions (step 3).
5. **CircleCI:** set up the project (step 4.2) and turn off forked-PR secrets
   (step 4.3). Push the `v1.0.0` tag: Play already holds versionCode 1, so the
   pipeline skips the upload, and the next tag ships.

## Releasing

```sh
# 1. Bump the versionName. That's the whole edit: the versionCode is the number
#    of v* tags, so the tag issues it.
#    pubspec.yaml → version: 1.0.1
# 2. Optional: hand-write android/fastlane/metadata/android/en-US/changelogs/<code>.txt
#    (code = current tag count + 1). A committed file always beats Gemini.
git commit -am "Release 1.0.1"
git tag v1.0.1
git push origin main v1.0.1
```

CI then runs verify → build_aab → publish_internal. Read the release-notes step
in its output: that text goes to testers. The AAB and the notes are kept as
build artifacts, so a failed upload never means a rebuild.

`make build-aab` builds the same bundle locally (it needs the tags and
`android/key.properties`); `make changelog ARGS=--dry-run` shows what Gemini
would write.

## Gotchas

- **Never delete a released tag.** The count is the versionCode; removing one
  makes the next release reuse a code Play has already seen. Tag forward.
- **The tag must match `version:` in the pubspec**, or `build_aab` stops in
  seconds, before anything is built.
- **A debug-signed AAB builds fine and Play rejects it later.** `build_aab`
  checks the signature before uploading.
- **Play's target API level rises every August.** Flutter 3.44 targets API 36;
  a Flutter upgrade is what keeps this true.
- **fastlane has no single working directory,** so every path in the Fastfile
  is absolute. Keep it that way.

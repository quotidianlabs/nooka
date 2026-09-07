# RuStore uploads use the cianru Gradle plugin

**Decision:** CI uploads the release APK to RuStore with
`ru.cian.rustore-publish-gradle-plugin`, applied unconditionally in the Android app's Gradle
`plugins {}` block and fed a credential from the `RUSTORE_CREDENTIALS` secret.

RuStore has no first-party GitHub Action, and its public API authenticates by RSA-signing a
timestamp with a private key to mint a short-lived token. The options were the maintained Gradle
plugin, a hand-written script calling the API directly, or no automation at all.

The plugin was chosen because that authentication is exactly the sort of fiddly cryptography a
maintained dependency should own. Re-implementing the signing, the token handling and the
multi-call upload flow by hand is fragile and a poor use of a single maintainer's time, with no
offsetting benefit. Manual upload was rejected because releases are frequent enough to be worth
automating.

The plugin's one real cost is that it couples publishing into the Gradle build, which is the very
thing the Play Store approach avoids by using a thin action instead. That is mitigated by how it
is applied: it registers only inert `publishRustore*` tasks, changes no build output, and the
upload runs solely in the guarded stable-tag release step. Applying it conditionally behind a
Gradle property was considered and rejected, because configuring its extension that way requires
naming the plugin's extension class, which is undocumented. Neither `flutter analyze` nor
`flutter test` touches Gradle, so only an actual build resolves it.

**Revisit trigger:** the plugin becomes unmaintained or breaks against a RuStore API change, or
RuStore ships a first-party Action or a token-exchange auth needing no local key signing. Either
makes a thin CI script the lighter option, matching the Play approach.

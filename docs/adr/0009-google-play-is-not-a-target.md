# Google Play is not a target

**Decision:** This app is not published to Google Play, and the Play pipeline built for it was
closed unmerged rather than kept warm. The store presence is RuStore, alongside the sideload APK
attached to each GitHub Release. There is no `.aab` build, no Play upload step, and no Play
listing documentation.

The reason is an external constraint rather than a preference, which is exactly why it is worth
recording: Play verifies a developer's identity against the country on the payment profile, and
that check cannot be completed for this maintainer. It is not a matter of paying the fee or
filling in more forms, and it will not resolve by retrying. A Play pipeline was written before
this was understood and was abandoned at that point, which is the cost this record exists to
stop anyone paying twice.

RuStore is the realistic alternative rather than a consolation. An individual developer account
needs no fee and no foreign payment method, it has no closed-testing gate, and it accepts a
self-signed APK directly, so most of the release plumbing already existed. That is why the
upload is a small guarded addition to the existing pipeline rather than a second one.

Two related refusals sit with this. The APK uploaded to RuStore is the same universal build
attached to GitHub Releases, not a separate bundle: RuStore's separate signature handling buys
nothing for an app this size. And there is no Google-free build flavour that strips the Drive
backup; one build ships everywhere, and Drive backup degrades gracefully on a device without
Google Play Services.

**Revisit trigger:** the identity verification becomes completable, whether because Play's
requirements change or because the maintainer's circumstances do. Note that the Play-specific
work was deleted rather than parked, so reopening this means rebuilding the bundle target, the
upload step and the data-safety declaration from scratch.

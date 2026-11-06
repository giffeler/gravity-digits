# Apple Developer account

This repository is prepared for distribution by the organization below. The account
holder supplied these enrollment details on 2026-11-06.

| Field | Value |
| --- | --- |
| Entity name | gekko Gesellschaft fuer Kommunikation und Kooperation mit beschraenkter Haftung |
| Team ID | `W4KKT72RUX` |
| Program | Apple Developer Program |
| Enrolled as | Organization |
| Account Holder | Denis Giffeler |
| Phone | 49-1709579292 |
| Street address | Pappelallee 78-79 Berlin, 10437 Germany |

## Repository configuration

`GravityDigits.xcodeproj/project.pbxproj` defines the organization team for Debug and Release. `Signing.example.xcconfig` uses the same team; local overrides require `-xcconfig Signing.local.xcconfig`.

| App target | Existing bundle identifier |
| --- | --- |
| GravityDigits | `com.example.gravitydigits` |

Keep existing bundle identifiers and companion-app relationships when applying the
organization account settings. The repository configuration does not establish
ownership or registration status in Apple Developer or App Store Connect.

The `com.example` identifiers are existing repository defaults. Confirm the intended
registered identifiers and App Store records before release; this preparation does
not assign replacement identifiers.

## Before the next signed release

- Confirm that team `W4KKT72RUX` shows the supplied organization enrollment and that
  the intended existing app records and bundle identifiers are available to it.
- Check the organization seller and contact details in App Store Connect.
- Verify access to the required signing certificates, provisioning profiles, and
  target capabilities before producing a signed archive.
- Keep signing credentials, private keys, certificates, and provisioning profiles
  out of git. Check any local or CI signing overrides against the organization team.

This preparation changes repository configuration and documentation only. It does
not transfer an app, register an identifier, create or revoke signing assets,
install an app, upload a build, or establish App Store release readiness.

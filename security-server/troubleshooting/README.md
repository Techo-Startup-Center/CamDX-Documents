# Troubleshooting

Arrived here with a symptom or an error message? Start with the table below.

| Symptom / error | Start here |
|---|---|
| Cannot open Admin UI | [Connectivity](./connectivity.md) |
| Cannot reach CamDX | [Connectivity](./connectivity.md) |
| Security Server peer connection fails | [Connectivity](./connectivity.md) |
| Token unavailable/inactive | [Error Reference](./error-reference.md) / Contact CamDX |
| `USER_PIN_INCORRECT` | [Error Reference](./error-reference.md) / Contact CamDX |
| Certificate pending/not registered | [Error Reference](./error-reference.md) / Contact CamDX |
| OCSP error | [Error Reference](./error-reference.md) / Contact CamDX |
| Global configuration expired/not updating | [Error Reference](./error-reference.md) / Contact CamDX |
| Database connection error | [Error Reference](./error-reference.md) / Contact CamDX |
| OPMON data unavailable | [Error Reference](./error-reference.md) / Contact CamDX |
| Unknown X-Road error/message | [Error reference](./error-reference.md) |

If no dedicated guide is linked above, check the [Error Reference](./error-reference.md), collect the diagnostic information below, and contact CamDX if the issue remains unresolved.

## Before contacting CamDX

Please have the following ready — it speeds up every support request:

- Security Server version (platform and package/image version)
- Operating system and version
- Timestamp of the issue, and timezone
- The operation you were performing when it failed
- The exact error code/message, verbatim
- Status of the relevant service (e.g. is `xroad-proxy` running?)
- A relevant recent log excerpt
- Whether this is happening in **DEV** or **PROD**

**Do NOT send:**

- Token PIN
- Passwords
- Personal access tokens (PAT) or API tokens
- Private keys
- Full secret-bearing configuration files
- Sensitive API payloads — unless specifically requested through an approved CamDX support channel

## Error reference

For a specific error code or message, see the [error reference](./error-reference.md).

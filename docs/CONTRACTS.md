# Credential-provider contract

Business entry points import src/contracts/RunbookVault.psm1 and use these functions:

| Function | Contract |
| --- | --- |
| Initialize-RunbookVault -ConfigurationPath | Validate nonsecret configuration and select a built-in provider; no credential returned |
| Test-RunbookVault -Reference | Return Reference, Healthy, LastRotationUtc, NextRotationUtc, PasswordAgeLimitSeconds, MinimumRemainingLifetimeSeconds, RemainingLifetimeSeconds and AdmissionAllowed; fail closed on unsupported or unhealthy metadata |
| Get-RunbookCredential -Reference | Enforce the admission margin against rotation age and credential TTL, then return exactly an in-memory PSCredential for the configured reference; never write credentials to job output |
| Close-RunbookVault | Forget local state; not a password rotation, check-in, token revocation or session termination |

Reference is a configured name such as OperationDirectory, not a provider-specific path chosen by an operator. Only OpenBao is implemented. Additional providers must implement this contract and demonstrate equivalent freshness/identity checks, or reject unsupported behavior explicitly. Do not claim all PAM products have identical APIs or rotation semantics.

The initial OpenBao adapter supports ArcManagedIdentity only. Authentication is independent of the AD execution identity. The caller disposes Credential.Password in finally and closes the provider. Strings and process memory are not guaranteed to be securely erased by setting variables to null.

Vendor probes may use a provider module scope to inspect capabilities; that escape hatch is reserved for code-owned diagnostics, not operator-supplied scripts. The current facade is single-session per PowerShell process and does not support concurrent configurations in the same module instance.

Credential rotation defaults to 86400 seconds; the default admission margin is 2100 seconds. Missing margin fields in older configurations inherit 2100 seconds. A near-rotation role can be healthy while credential admission is denied. See [rotation safeguards](CREDENTIAL-ROTATION.md).

# Development roadmap

## Platform development

- Add ordinary directory operations with explicit target, permission, verification and recovery definitions.
- Define a neutral platform execution/job-context contract as additional execution platforms are integrated.
- Implement account-wide concurrency and coordinated rotation drain before multi-worker credential sharing.
- Add AWS/GCP and alternative vault providers with conformance tests.
- Validate supported Linux runtimes and a Linux credential/identity adapter separately.
- Add central audit correlation and lifecycle management without granting workers broad management access.

## Deployment options

Production deployments can use baseline Azure RBAC or the [optional Microsoft Entra PIM procedure](advanced/ENTRA-PIM.md) for time-limited human access. Choose the access policy according to licensing, risk and operational requirements; complete the procedure's acceptance and ownership checks when enabling PIM.

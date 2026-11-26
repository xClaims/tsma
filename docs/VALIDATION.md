# Validation procedure

## Offline checks

Run tests/Invoke-TSMAChecks.ps1 in PowerShell 7.4 or later for parser, JSON and all isolated fixture suites. These tests mock Azure, Graph, AD, vault and LDAP adapters; no production resources should be contacted. Tests intentionally exercise provider private functions where necessary.

For Windows PowerShell 5.1:

~~~powershell
.\tests\Invoke-TSMAChecks.ps1 -OfflineOnly
~~~

This runs source parsing plus isolated AST-loaded logic tests for membership safeguards/recovery, metadata normalization, write state and the credential facade. It cannot certify actual PS7 module loading, Arc endpoint behavior, supported Azure runtimes, ACL deployment or live AD writes. Do not strip production Requires declarations to claim runtime support.

PSScriptAnalyzer is an additional static check. No fixtures contain real credentials: TEST/FAKE/OFFLINE values and example domains are deliberate.

## Fresh deployment acceptance

1. Verify code/config ACLs, no filesystem links, expected worker host, SYSTEM SID and actual PowerShell runtime.
2. Verify DNS, TCP/TLS trust, synchronized UTC and unsealed vault.
3. Confirm managed identity matches the exact JWT oid binding, with correct issuer, tenant, role, audience and signature validation.
4. Run access, authorization and LDAPS probes. Expect exact read capabilities and HTTP403 for actual denied GETs; an empty or unavailable response is not a passing denial test.
5. Run isolated JWT wrong audience/tenant/identity/issuer and altered-signature checks. Never weaken the production role for a test.
6. Observe a scheduled password rotation across the configured interval without manually rotating, then verify fresh AD authentication. Record both timestamps and job output. Validate the 35-minute admission blackout separately; metadata-only monitoring should remain healthy while credential admission is false. See [rotation acceptance](CREDENTIAL-ROTATION.md).
7. Preview an eligible user/group. Confirm no AD write and review evidence.
8. Reject a disabled user, protected privileged group, Tier 0 object, Domain Controllers object, foreign identity, expired review and disabled-write request. Keep these tests in an authorized environment; do not move or weaken real privileged assets to construct fixtures.
9. Open writes only after approval; add one authorized membership, independently verify, then repeat to prove AlreadyMember/no mutation.
10. Confirm evidence and Application events, missing Azure metadata handling, SIEM forwarding if configured, maintenance pause and recovery procedures.

Retain commit ID, actual runtime/extension versions, operator, scope review, sanitized job output and result records. Retain acceptance evidence for the actual deployed environment; package fixture results do not replace these checks.

## Optional PIM acceptance

Before activation, invocation denied. During activation, invocation allowed and publication denied. After expiry/deactivation and propagation, new invocation denied. Test inherited access bypasses, approver separation and emergency recovery. Existing/queued jobs and workload credentials have independent lifecycles.

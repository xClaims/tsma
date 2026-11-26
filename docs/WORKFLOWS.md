# Approval and execution workflows

These diagrams separate human access approval, workload authentication, directory safeguards and schedule authorization. They describe the documented TSMA Azure Automation/OpenBao deployment; each environment supplies its own policy settings and accountable people.

## 1. Human approval and runbook submission

A business ticket/change approval and PIM activation approval are separate decisions. TSMA records the supplied ChangeReference; it does not query a ticket system or verify CAB approval. PIM is optional and controls human group activation before Azure invocation.

```mermaid
flowchart TD
    A["Operator has an approved operational request"] --> B{"Optional PIM enabled?"}
    B -->|No| C["Use assigned Azure group membership"]
    B -->|Yes| D["Request eligible group activation<br/>Authenticate and provide justification"]
    D --> E{"Activation approval required?"}
    E -->|Yes| F["Named independent approver reviews request"]
    F --> G{"Approved?"}
    G -->|No or expired request| H["No activation<br/>Access remains unavailable"]
    G -->|Yes| I["Time-limited active group membership"]
    E -->|No| I
    C --> J["Azure RBAC evaluates effective invocation access"]
    I --> J
    J --> K{"Authorized?"}
    K -->|No| L["Submission denied"]
    K -->|Yes| M["Submit published runbook to approved worker group"]
    M --> N["TSMA independently checks execution policy and targets"]
```

Approval is shown as configurable because PIM policy determines whether an approver is required. For the recommended production settings and eligibility/ownership controls, see [optional Entra PIM](advanced/ENTRA-PIM.md). Baseline group/RBAC configuration is documented in [operator access](setup/OPERATOR-ACCESS.md). Account-scoped invocation rights apply to the account's runbooks; PIM does not narrow that scope.

Activation expiry/deactivation restricts new requests after propagation; it does not automatically cancel queued/running jobs or invalidate established AD sessions. Independent grant paths and group-owner privileges must also be reviewed.

## 2. Workload identity and credential flow

```mermaid
sequenceDiagram
    autonumber
    actor Operator as Named operator
    participant Azure as Azure Automation
    participant Worker as Windows Hybrid Worker / SYSTEM
    participant Arc as Local Arc identity endpoint
    participant Entra as Microsoft Entra ID
    participant Bao as OpenBao
    participant AD as Configured domain controller
    participant Audit as Protected evidence / Application events

    Operator->>Azure: Start published runbook with names, reference and Preview
    Azure->>Azure: Authorize operator through effective Azure RBAC
    Azure->>Worker: Dispatch job to selected worker group
    Worker->>Worker: Load protected code, mapping and policy
    Worker->>Arc: Request dedicated API resource token
    Arc->>Entra: Use the machine managed identity
    Entra-->>Arc: Signed access token for the dedicated audience
    Arc-->>Worker: Entra JWT after local challenge validation
    Worker->>Bao: JWT login with configured role
    Bao->>Bao: Verify signature, issuer, audience, expiry and bound claims
    Bao-->>Worker: Scoped short-lived vault token
    Worker->>Bao: Read mapped rotation metadata and credential
    Bao-->>Worker: Execution account credential
    Worker->>AD: Read and classify pinned targets using explicit credential
    Worker->>Audit: Record intent under a local account lock
    alt Eligible authorized write requested
        Worker->>AD: Recheck eligibility and add one member link over LDAPS
        Worker->>AD: Verify direct membership on the same DC
        Worker->>Audit: Record verified outcome or recovery requirement
    else Preview or already a direct member
        Worker->>Audit: Record outcome without membership mutation
    end
    Worker-->>Azure: Safe result, RunId and evidence path
    Azure-->>Operator: Job status and sanitized output
```

The human operator, worker SYSTEM process, Arc machine identity and AD execution account are distinct. The worker receives the password in memory; the operator receives only safe job output. Tokens, challenge-file contents and passwords must never be written to job output or evidence.

The sequence shows the successful authentication path. Invalid identity bindings, unhealthy/stale credentials, unsafe configuration, unavailable evidence or ineligible targets fail closed. The JWT role/policy and credential-provider implementation enforce access independently of the human's PIM activation. See [architecture](ARCHITECTURE.md), [Entra/OpenBao trust](setup/ENTRA-OPENBAO.md) and [credential contract](CONTRACTS.md).

## 3. Directory operation decisions and recovery

```mermaid
flowchart TD
    A["Published Add-DirectoryGroupMember job"] --> B["Load protected policy<br/>Obtain healthy mapped credential"]
    B --> C{"Policy, identity, review,<br/>write state and freshness valid?"}
    C -->|No| R["RejectedBeforeWrite<br/>No membership mutation"]
    C -->|Yes| D["Resolve user and group to GUIDs<br/>Validate protected evidence path"]
    D --> E{"Acquire local account lock?"}
    E -->|No| R
    E -->|Yes| F["Read and classify targets and parent groups<br/>Enforce Tier 0 and DC exclusions"]
    F --> G{"Eligible and intent evidence recorded?"}
    G -->|No| R
    G -->|Yes| H{"Already a direct member?"}
    H -->|Yes| I["AlreadyMember<br/>MutationAttempted=False"]
    H -->|No| J{"Preview=True?"}
    J -->|Yes| K["Preview<br/>MutationAttempted=False"]
    J -->|No| L["Recheck eligibility, membership and rotation margin"]
    L --> M{"Still admissible?"}
    M -->|No| R
    M -->|Already a member| I
    M -->|Yes| N["Persist mutation-attempt record<br/>Send one LDAPS member-link add"]
    N --> O{"Direct membership verified<br/>and outcome recorded?"}
    O -->|Yes| P["VerifiedSuccess"]
    O -->|No or uncertain| Q["RecoveryRequired<br/>Retain local lock and reconcile"]
    I --> S["Record final evidence and release lock"]
    K --> S
    P --> S
```

Preview defaults True. The write-state gate applies to write requests; preview can remain available during maintenance while scope review and other policy checks are valid. Protected objects, privileged ancestry, unknown classification, disabled users and unsupported groups are rejected. Early rejection can precede creation of a RunId/evidence record.

The diagram summarizes the normal success paths. A failed final evidence/event write can itself require recovery; an intended success outcome is not accepted when its recording fails. Pre-mutation rejection releases any acquired lock when cleanup succeeds. A marked/uncertain mutation keeps the lock and requires actual-state reconciliation; it does not trigger automatic membership removal or blind retry.

The local lock serializes this operation on one worker. It does not coordinate other consumers or OpenBao's independent password-rotation timer. See [group membership procedure](ADD-DIRECTORY-GROUP-MEMBER.md) and [recovery procedure](OPERATIONS.md).

## 4. Recurring jobs and maintenance authorization

```mermaid
flowchart TD
    A["Authorized administrator reviews schedule<br/>Runbook, worker group, owner and expiry"] --> B["Create finite recurring job schedule"]
    B --> C["Azure Automation triggers the published runbook"]
    C --> D["Worker applies runbook execution safeguards"]
    D --> E["Record job output and operation evidence"]
    B -.-> F["Schedule is a separate ongoing authorization<br/>Human PIM activation is not repeated for each trigger"]
    G["Planned maintenance"] --> H["Pause applicable starts and schedules<br/>Disable new write admissions"]
    H --> I["Allow admitted jobs to finish<br/>Reconcile uncertain outcomes and retained locks"]
    I --> J["Perform maintenance and read-only validation"]
    J --> K["Approved restoration of admissions and schedules"]
```

A schedule must have its own reviewed operating authorization; do not treat one human PIM activation as approval for indefinite future automation. The bundled schedule helper creates a finite read-only service-health schedule, not privileged directory mutations or password rotation. Directory-write admission controls do not pause read-only health schedules automatically.

OpenBao performs scheduled AD password rotation independently; these diagrams do not imply a distributed maximum-age-plus-drain coordinator. Disabling new admissions allows already admitted work to finish. Urgent containment uses the separately governed incident-response process. See [installation and schedules](INSTALL.md) and [maintenance](OPERATIONS.md).

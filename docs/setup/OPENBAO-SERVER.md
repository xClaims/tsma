# Install and initialize OpenBao

**Run on:** your Linux vault host, as its administrator. The Windows worker need not exist yet. This stage creates a new vault only; never initialize an existing initialized cluster again.

## 1. Install Docker Engine and Compose

Use Docker's instructions for your supported distribution. For Ubuntu, follow [Docker Engine installation](https://docs.docker.com/engine/install/ubuntu/) including the official package repository, then verify:

~~~sh
sudo systemctl status docker --no-pager
sudo docker run --rm hello-world
sudo docker compose version
~~~

Use sudo for Docker unless your security policy deliberately grants docker-group membership, which is powerful host access. Do not mix unrelated distribution Docker packages with the official installation. See [Compose plugin installation](https://docs.docker.com/compose/install/linux/).

## 2. Copy deployment resources

Create /opt/tsma/openbao and obtain its TLS files as described in [certificates](CERTIFICATES-LDAPS.md). From an interactive workstation terminal, copy these repository files to that directory on the actual Linux host:

- deployment/openbao/compose.yaml
- deployment/openbao/.env.example
- deployment/openbao/server.hcl.example
- deployment/openbao/operation-directory-worker-policy.hcl (used later)

For example, replacing the SSH username and host:

~~~powershell
scp C:\Code\tsma\deployment\openbao\compose.yaml vaultadmin@vault01.example.com:/opt/tsma/openbao/
scp C:\Code\tsma\deployment\openbao\server.hcl.example vaultadmin@vault01.example.com:/opt/tsma/openbao/
scp C:\Code\tsma\deployment\openbao\.env.example vaultadmin@vault01.example.com:/opt/tsma/openbao/
scp C:\Code\tsma\deployment\openbao\operation-directory-worker-policy.hcl vaultadmin@vault01.example.com:/opt/tsma/openbao/
~~~

Use your real account/host; scp does not create the remote directory. Do not transfer private CA keys or save SSH passwords in scripts. On Linux:

~~~sh
cd /opt/tsma/openbao
cp .env.example .env
cp server.hcl.example server.hcl
chmod 600 .env
~~~

Edit .env and server.hcl using your preferred editor. Replace all example addresses. The vault DNS must resolve from both the worker and container. AD_DNS_IP supplies container DNS capable of resolving your AD domain and forwarding external registry/Entra queries.

## 3. Select and pin compatible server/plugins

Use [OpenBao releases](https://github.com/openbao/openbao/releases) and the official [OCI plugin documentation](https://openbao.org/docs/configuration/plugins/) to select a supported server with declarative audit/plugin features and a compatible LDAP plugin. The repository's LDAP artifact is a previously exercised version, not a promise that it is the latest supported version. Review release/security notes for your selected deployment.

APPROVED_VERSION and VERIFIED_DIGEST are placeholders, not real tags. Pull the server tag you actually selected and record its digest. This read prompts for a nonsecret version tag:

~~~sh
printf 'Approved OpenBao server version tag: '
read -r OPENBAO_TAG
sudo docker pull "ghcr.io/openbao/openbao:$OPENBAO_TAG"
sudo docker image inspect "ghcr.io/openbao/openbao:$OPENBAO_TAG" --format '{{json .RepoDigests}}'
~~~

Set OPENBAO_IMAGE in .env to the official image reference pinned by the verified registry digest. Set BAO_ADDR to https://<real-vault-name>:8200, AD_DNS_IP to your DNS server, and BIND_IP to an actual local interface address. In server.hcl set api_addr and cluster_addr to the real vault name. The LDAP plugin OCI artifact is not a runnable server image; configure its independently verified image/digest in the plugin stanza. Leave the plugin cache writable.

The compose file publishes only 8200; the 8201 cluster address is not an instruction to expose it externally for this single-node starting deployment. Persistent named volumes hold Raft, plugin cache and audit output. Protect them and back them up.

## 4. TLS permissions and startup

Inspect the selected image's runtime identity rather than assuming a UID. The compose variables must already be filled:

~~~sh
sudo docker compose -p tsma-vault config --quiet
sudo docker compose -p tsma-vault run --rm --no-deps --user openbao --entrypoint sh openbao -c 'id'
ls -ldn tls
ls -ln tls/server.crt tls/server.key tls/ca.crt
~~~

If the image does not contain the expected openbao user, stop and consult that image's documentation. Grant the runtime identity read access to the key/certificates and traversal of tls, using a dedicated trusted group or ACL. Do not make the private key world-readable. For a trusted group whose numeric GID you verified, a 0750 TLS directory and 0640 files can work. Do not blindly chgrp to a group shared with untrusted host users. Test from the container before starting:

~~~sh
sudo docker compose -p tsma-vault run --rm --no-deps --user openbao --entrypoint sh openbao -c 'for f in /bao/tls/server.crt /bao/tls/server.key /bao/tls/ca.crt; do test -r "$f" || exit 1; done'
sudo docker compose -p tsma-vault up -d
sudo docker compose -p tsma-vault logs --tail=80 openbao
sudo docker compose -p tsma-vault exec openbao bao status
~~~

bao status may return a nonzero exit status while sealed; inspect Initialized and Sealed values. Startup should show TLS enabled and Raft storage, not development mode. Plugin download completion does not by itself prove the plugin is registered in the catalog.

## 5. Initialize once and unseal

Only if Initialized=False, run from a private interactive terminal without terminal/transcript recording:

~~~sh
sudo docker compose -p tsma-vault exec openbao bao operator init -key-shares=5 -key-threshold=3
~~~

This prints highly sensitive unseal shares and an initial root token. Record them securely with the intended custodians; do not paste output into GitHub, Azure job output, chat, repository files or audit examples. Do not retain all shares alongside the vault's data backup.

Unseal with three different shares using hidden prompts, once per share:

~~~sh
sudo docker compose -p tsma-vault exec openbao bao operator unseal
sudo docker compose -p tsma-vault exec openbao bao status
~~~

An unsealed, initialized vault is the exit condition. With Shamir sealing, a restart requires unsealing again unless you separately design supported auto-unseal. The five/three example requires you to actually retain enough shares; do not choose a threshold that cannot be recovered. See [initialization](https://openbao.org/docs/commands/operator/init/) and [seal/unseal](https://openbao.org/docs/concepts/seal/).

## 6. Administrator session and audit

Open a private container shell and log in with the initial root token only for bootstrap:

~~~sh
sudo docker compose -p tsma-vault exec openbao sh
bao login
bao status
bao audit list -detailed
bao plugin list -detailed secret
bao plugin list -detailed auth
~~~

The server example declares audit in configuration; do not assume bao audit enable is allowed on that release. Verify the configured device and writable audit volume. Create a properly scoped administrative authentication/recovery arrangement before retiring the initial root token; no community worker needs a root token.

Confirm ldap and jwt are present. If not, use your release's official plugin registration instructions; stop rather than guessing a catalog name/version. With plugin_auto_download and plugin_auto_register enabled, investigate configuration/catalog logs before trying a mount. See [declarative audit](https://openbao.org/docs/configuration/audit/).

From the worker or management host with the public CA trusted, verify HTTPS health:

~~~powershell
Invoke-RestMethod 'https://bao.example.com:8200/v1/sys/health' | Select-Object initialized,sealed,version
~~~

Replace the URL. Expect initialized=True and sealed=False. Do not bypass certificate validation. Proceed to [LDAP account management](OPENBAO-LDAP.md).

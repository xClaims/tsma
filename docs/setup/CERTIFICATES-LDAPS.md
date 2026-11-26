# Certificates, CA trust and LDAPS

**Run on:** the CA/DC using authorized PKI administrators; the vault host as its administrator; and the worker as local administrator. Use the CA hostname, certificate profiles and trust chain approved for your environment.

## 1. Supply a CA

Use your established PKI when available. If starting an isolated Windows environment, install AD Certificate Services -> Certification Authority on an appropriately protected server, then configure an Enterprise Root CA using the AD CS configuration wizard and a deliberately recorded CA name/key/validity policy. A single-tier online root can support an isolated first installation; production CA hierarchy, availability and offline-root design require separate PKI planning. TSMA does not require thirty-year root or ten-year server certificates.

Use [Microsoft's AD CS installation procedure](https://learn.microsoft.com/en-us/windows-server/networking/core-network-guide/cncg/server-certs/install-the-certification-authority) for supported prerequisites/options. Back up CA database, configuration, certificate and private key securely and test restoration. Never transfer the CA signing private key to the vault host or worker.

## 2. Enroll the domain controller

In Certificate Templates (certtmpl.msc), duplicate Kerberos Authentication if suitable for your supported DC versions and PKI policy. Give the template an environment-specific name, enable Server Authentication and the DC/KDC capabilities you require, use DNS names built from AD, and grant the intended Domain Controllers Read/Enroll/Autoenroll. Do not enable arbitrary enrollee-supplied subject names as a shortcut. Publish the template on the CA through Certificate Templates -> New -> Certificate Template to Issue.

Link a dedicated computer GPO to the Domain Controllers OU. Under Computer Configuration -> Policies -> Windows Settings -> Security Settings -> Public Key Policies -> Certificate Services Client - Auto-Enrollment, select Enabled and both renewal/update options. On each intended DC, apply policy and trigger enrollment:

~~~powershell
gpupdate /force
certutil -pulse
~~~

Inspect Local Computer -> Personal certificates. The selected certificate must have a private key, Server Authentication EKU, DC FQDN DNS identity, valid dates and trusted chain. A DC/Kerberos template is not a Windows Hello deployment by itself. Use a planned service refresh/restart consistent with Microsoft's LDAPS procedure; do not reboot every DC simultaneously.

## 3. Validate LDAPS before configuring the vault

From a management host, open ldp.exe -> Connection -> Connect -> actual DC FQDN, port 636, SSL selected. Verify connection and an authorized bind. Use FQDN rather than IP so hostname validation matches. From the Linux vault host, validate the TLS chain and hostname using your exported public root:

~~~sh
openssl s_client -connect dc01.ad.example.com:636 -servername dc01.ad.example.com -CAfile dc-ca-chain.pem -verify_hostname dc01.ad.example.com -verify_return_error </dev/null
~~~

The PEM file contains the public CA trust chain, not a private key and not simply the DC leaf certificate. The vault's LDAP certificate setting is this trust material. Successful TCP alone is insufficient. See [Microsoft's LDAPS certificate requirements](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/configure-ldap-signing-certificates).

## 4. Obtain a vault TLS certificate

On the Linux vault host, create its deployment directory and private key/CSR. Replace bao.example.com in the command with the real DNS name:

~~~sh
sudo install -d -m 0750 -o "$USER" -g "$(id -gn)" /opt/tsma/openbao
cd /opt/tsma/openbao
umask 077
mkdir -p tls
openssl req -new -newkey rsa:3072 -nodes -keyout tls/server.key -out bao.req -subj '/CN=bao.example.com' -addext 'subjectAltName=DNS:bao.example.com'
~~~

Transfer only bao.req to a CA administration workstation using scp in an interactive terminal. Have the PKI administrator issue it through an approved TLS server template with Server Authentication and the requested DNS SAN. The CA must approve the SAN; requesting it in a CSR does not guarantee it is in the issued certificate. For an enterprise CA use its documented certreq submission or web enrollment procedure and approved template name.

Export the CA public certificate from Certification Authority -> CA Properties -> View Certificate -> Details -> Copy to File -> Base-64 encoded X.509 (.CER). Return the issued leaf and public CA certificate/chain to the vault host. Keep the generated private key on the vault host.

Base-64 X.509 files containing BEGIN CERTIFICATE are already PEM. Place the leaf at tls/server.crt and public trust anchor(s) at tls/ca.crt. If the issued leaf is DER, convert only that file:

~~~sh
openssl x509 -inform DER -in bao.cer -out tls/server.crt
~~~

For an intermediate hierarchy, server.crt serves leaf followed by intermediate certificates; the trust file supplies root trust. Verify regardless of whether conversion was needed:

~~~sh
openssl verify -CAfile tls/ca.crt tls/server.crt
openssl x509 -in tls/server.crt -noout -subject -issuer -dates -ext subjectAltName
openssl pkey -in tls/server.key -pubout | openssl sha256
openssl x509 -in tls/server.crt -pubkey -noout | openssl sha256
~~~

The two public-key hashes must agree. Preserve restrictive key permissions; container-readable permissions are set in the next stage. Import only the public root/intermediate certificates into the worker's Local Computer trusted stores using the approved certificate deployment process.

## 5. DNS and time exit checks

Create the vault A/AAAA record in the authoritative DNS zone and confirm both worker and vault host resolve the real name. Linux resolved/systemd-resolved must route your AD zone to AD DNS rather than a public resolver; configure the network manager/netplan persistently. A successful nslookup against an explicitly supplied AD DNS server does not configure the system resolver.

~~~powershell
Resolve-DnsName bao.example.com
Test-NetConnection dc01.ad.example.com -Port 636
Test-NetConnection dc01.ad.example.com -Port 9389
(Get-Date).ToUniversalTime().ToString('o')
~~~

On Linux compare date -u and your time daemon's status, for example chronyc tracking. Fix the clock source and suspend/resume behavior before continuing. Proceed to [OpenBao server installation](OPENBAO-SERVER.md).

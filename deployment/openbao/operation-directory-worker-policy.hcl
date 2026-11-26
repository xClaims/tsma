# Worker can read only its exact Directory execution account.
path "ldap-operation/static-role/operation-directory" {
  capabilities = ["read"]
}
path "ldap-operation/static-cred/operation-directory" {
  capabilities = ["read"]
}

# Token self-inspection only; does not grant target configuration/rotation rights.
path "sys/capabilities-self" {
  capabilities = ["update"]
}

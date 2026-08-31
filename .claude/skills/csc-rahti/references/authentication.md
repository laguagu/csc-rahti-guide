# Rahti CLI authentication for agents and automation

## Use the right identity

- Use a personal CSC login only for interactive administration and for bootstrapping or rotating an automation credential. CSC MFA cannot and should not be bypassed by a skill.
- Use a dedicated, namespace-scoped OpenShift service account for agents, local deployment scripts, and external CI.
- Do not use an SSH key for `oc login`. SSH keys authenticate Git access, not the OpenShift API.
- Do not place tokens in `SKILL.md`, a repository, shell history, or chat.

## Plain `oc` version (no scripts)

With a personal `oc` login active:

```bash
oc create serviceaccount deployer-bot -n <namespace>
oc adm policy add-role-to-user edit system:serviceaccount:<namespace>:deployer-bot -n <namespace>
oc create token deployer-bot -n <namespace> --duration=8760h
```

Store the printed token in your secret manager or a gitignored env file, then use it:

```bash
oc login https://api.2.rahti.csc.fi:6443 --token=<token>
oc project <namespace>
```

Role guidance: `view` for read-only automation, `edit` for building and deploying,
`admin` only when the account must also manage namespace RBAC. Prefer the shortest
duration that is practical.

## Scripted version (bundled PowerShell)

One-time bootstrap or rotation, with a personal `oc` login active:

```powershell
& "$HOME\.claude\skills\csc-rahti\scripts\Initialize-RahtiCredential.ps1" `
  -Namespace <namespace> `
  -AccessNamespaces <namespace>,<other-namespace> `
  -ServiceAccount deployer-bot `
  -Role edit `
  -Duration 8760h `
  -Force
```

This creates or reuses `system:serviceaccount:<namespace>:deployer-bot`, binds the
requested role in every listed namespace, requests a token of the given lifetime, and
writes the secret to a private env directory outside the repository:

```text
~/.agents/env/rahti/<namespace>/rahti-sa.env
```

Override the location with `-SecretFile <path>` or the `RAHTI_ENV_HOME` environment
variable. The scripts themselves contain no credentials — keep the env directory out
of git and out of any synced public folder.

## Connect on this or another machine

After the secret file exists and `oc` is installed:

```powershell
& "$HOME\.claude\skills\csc-rahti\scripts\Connect-Rahti.ps1" -Namespace <namespace>
oc whoami
oc project -q
```

The script reads the stored token, installs it into the local default kubeconfig,
selects the namespace, and verifies that the resulting identity exactly matches the
expected service account. Later terminals use normal `oc` commands with no interactive
login until the token expires or is revoked.

## Revocation and rotation

To cut access immediately, remove the namespace role binding or delete the service
account. The role name in `remove-role-from-user` must match the role that was actually
granted — removing the wrong one silently leaves access intact. Check first:

```powershell
oc get rolebindings -n <namespace> -o wide | Select-String deployer-bot

oc adm policy remove-role-from-user edit system:serviceaccount:<namespace>:deployer-bot -n <namespace>
oc delete serviceaccount deployer-bot -n <namespace>
```

A role binding exists **per namespace** — removing it in one namespace leaves access in
the others in place.

Deleting the service account invalidates its identity. To rotate while keeping the
account and its RBAC, re-run the bootstrap with an active personal login and `-Force`;
the stored env file and the local kubeconfig are replaced.

## Webhooks and CI

- BuildConfig GitHub or generic webhooks use their own webhook secret. They do not need a personal `oc` token.
- External CI should use a dedicated service-account token stored in the CI provider's encrypted secrets.
- Use a separate service account per purpose when permissions differ, such as an `image-pusher` account holding only `system:image-pusher`.

# Vizier - a proof-checked IaC orchestrator

Vizier runs an OpenTofu/Terraform unit tree in dependency order - and runs
**only modules that pass verification** against the IaC Bazaar catalog. A unit
whose module is unsigned, unverified, or below the required verification status
is **blocked before any `tofu apply`** (fail-closed).

It is Terragrunt-shaped: one `vizier.hcl` per unit, `include` for DRY config,
`dependency` blocks that thread outputs.

**On what is and is not novel here.** Refusing to execute an artifact whose
signature does not verify against a pinned key is not a new idea, and this
README used to overclaim that it was. Helm has verified chart provenance since 2016;
ansible-galaxy, Argo CD, Flux and Crossplane all refuse to proceed on a failed
signature, and Terraform and OpenTofu themselves do exactly this for provider
binaries. The mechanism is decades-old and well understood.

What is unusual is where it is missing. Terraform *modules* are the one artifact
in that list nobody checks: HashiCorp's own documentation states that Terraform
does not verify module signatures, there is no module lockfile, and every
Terraform orchestration platform we surveyed - HCP Terraform, Spacelift, env0,
Scalr, Atlantis, Digger, Terrakube - checks the resulting *plan* with
policy-as-code rather than on the module. Vizier applies the established
mechanism to the artifact that was skipped, from a single binary, with no
cluster and no control plane.

## Install

No runtime dependencies beyond a `tofu` (or `terraform`) on `PATH`.


**Download a release** - Linux, macOS and Windows, amd64 and arm64:
<https://github.com/CyberCoreSystems/vizier/releases/latest>

**One-line install** (Linux/macOS) - verifies the download against the release
checksums and refuses to install if it cannot:

```bash
curl -fsSL https://raw.githubusercontent.com/CyberCoreSystems/vizier/main/install.sh | sh
```

**Prebuilt binaries** - download a `vizier_<version>_<os>_<arch>` archive
(linux/darwin/windows, amd64/arm64) from the
[releases](https://github.com/CyberCoreSystems/vizier/releases) page, unpack, and
put `vizier` on your `PATH`.

**From source**:

```bash
go build -o dist/vizier .
./dist/vizier version
```

Point Vizier at a specific engine with `--tofu-bin /path/to/tofu` or the
`VIZIER_TOFU_BIN` environment variable (default: auto-detect `tofu` then
`terraform`).

Releases are cut in the PUBLIC repo by pushing a `vX.Y.Z` tag. Regenerate it
first with `bash scripts/vizier-public-repo.sh`, which verifies the export builds
and passes its tests under the rewritten module path before you push.

## Commands

```
vizier init                          # alias of plan: verify + generate files + tofu init + plan
vizier plan | apply | destroy        # act on the single unit in --dir
vizier run-all <plan|apply|destroy>  # DAG-ordered across every unit under --dir
vizier verify                        # verification ONLY - report each unit's status, run no tofu
vizier exec -- <command>             # run a command in a unit's resolved context, verified first

vizier certify [--wait]              # verify this COMMIT in a real sandbox; returns a receipt
vizier certify status <run>          # read a run and its receipt
vizier certify change <id>           # verify the commit a change pins, and record the verdict on it

vizier stack generate                # stamp out a unit tree from vizier.stack.hcl
vizier stack run <plan|apply|destroy> # generate, then run the whole stack in DAG order
vizier stack output [--json]         # generate, then read every unit's outputs
vizier stack clean [--dry-run]       # remove only the units a stack generated
vizier scaffold <source>             # write a starter vizier.hcl with the module's inputs
vizier catalog list | show <slug>    # browse the verified module catalog

vizier login                         # store a registry token for --catalog-url
vizier login --endpoint <url>        # sign in to a self-hosted Vizier Central
vizier whoami                        # who the token is, and what this tree may download
vizier logout                        # forget the stored token

vizier central                       # what Vizier Central is (a commercial product)
vizier central status                # which control plane this tree uses, and who you are on it
vizier central changes               # what is waiting to be reviewed
vizier central propose               # raise a change, pinned to a commit
vizier central review <id> --approve # somebody ELSE approves it
vizier central show <id>             # its reviews, its checks, and whether it may be applied

vizier browse [<repo>...]            # what modules a repository holds; pipes into scaffold
vizier find [--json] [--dag]         # what is in this tree, as data
vizier list [-l|-T|--format dot]     # what is in this tree, for reading
vizier info print [--json]           # the resolved context: tree, checks, catalog, keys, engine
vizier info proof                    # the floor each unit demands before it will run
vizier mcp                           # serve this tree to an AI assistant (read-only)
vizier backend bootstrap [--dry-run] # create the state store remote_state points at
vizier backend delete                # delete ONE unit's state object, after backing it up
vizier backend migrate <src> <dst>   # move a unit's state, verified before the source is dropped

vizier output-all                    # every unit's outputs, in dependency order
vizier graph-dependencies [--dot]    # the DAG, as text or Graphviz
vizier render-json                   # each unit's resolved config, for debugging
vizier validate-inputs               # check every unit's inputs evaluate
vizier hcl validate [--json]         # check every config, reporting all problems at once
vizier hcl fmt [--check]             # format vizier.hcl files (also: vizier hclfmt)
vizier version
```

An alternative executor, proved the way a module is:

```hcl
engine {
  source = "https://example.com/engines/acme-engine"
  # Required. There is no "latest", no unpinned source, and no flag that turns
  # this check off. An engine plugin replaces the process that RUNS your proved
  # module, so an unprovable plugin would make the proof a statement about a file
  # nobody ran. A .sigbundle.json beside the binary is verified against the same
  # keys modules use.
  sha256 = "9f2c..."
}
```

Repositories worth browsing, declared once at the tree root:

```hcl
sources {
  urls = ["github.com/acme/infrastructure-modules?ref=v1.4.0"]
}
```

Global flags:

| Flag | Default | Meaning |
|---|---|---|
| `--dir` | `.` | Root of the unit tree (or the single unit dir for `init`/`plan`/`apply`/`destroy`) |
| `--verify-mode` | `enforce` | Verification mode: `enforce` \| `warn` \| `off` |
| `--tofu-bin` | auto-detect | Path to `tofu`/`terraform` |
| `--catalog-url` | `https://iac-bazaar.com` | IaC Bazaar catalog base URL |
| `--auto-approve` | `false` | Skip the confirmation prompt for `apply`/`destroy`. Required where there is no terminal, so CI states its intent rather than a closed stdin being read as consent. |
| `--offline` | `false` | Fall back to `vizier.lock` when the catalog is unreachable. Off by default: a network failure must not silently downgrade verification. An offline proof is marked as such in the receipt. |
| `--token` | - | Registry token for this run, instead of the stored one. Beats `VIZIER_TOKEN`, which beats `~/.vizier/credentials.json`. |

`run-all` flags:

| Flag | Default | Meaning |
|---|---|---|
| `--fetch-source` | `false` | Download each `iacbazaar://` module and run **that**, after checking its digest against the signature. See "What verification actually proves" below. |
| `--plan-dir` | - | Save plan files here on `plan`, apply them from here on `apply`, so what is applied is what was reviewed |
| `--detailed-exitcode` | `false` | Exit 2 when a plan has pending changes (drift detection) |
| `--parallelism` | `1` | Run this many independent units concurrently; dependencies are still honoured, and each line of output is prefixed with the unit that produced it |
| `--retries` | `1` | Attempts per engine command; >1 retries known-transient failures |
| `--receipt` | - | Write a JSON run receipt |
| `--receipt-md` | - | Write a Markdown summary, for a PR comment |

`run-all` also takes `--provider-cache DIR` (one shared Terraform plugin cache
for the whole tree, instead of every unit downloading the same provider),
`--queue-include-dir` / `--queue-exclude-dir` / `--queue-exclude-external` /
`--queue-ignore-errors`, and `--feature NAME=VALUE`.

Anything after `--` is forwarded verbatim to tofu, so `-target`, `-refresh=false`
and the rest still work:

```bash
vizier --dir environments/prod/vpc plan -- -target=aws_vpc.main
```

Per-unit, in `vizier.hcl`:

| Setting | Meaning |
|---|---|
| `skip = true` | Leave this unit out of the run. It stays in the DAG, so its outputs still feed dependents. |
| `exclude { if = ..., actions = [...] }` | Conditional exclusion, optionally per action - `actions = ["destroy"]` is prevent_destroy. |
| `feature "x" { default = ... }` | A flag a pipeline flips with `--feature x=true`, read as `feature.x.value`. |
| `errors { retry {...} ignore {...} }` | Per-class retry with backoff, and ignoring an expected failure. `ignore` requires a `message` and reports every match. |
| `iam_role = "arn:..."` | Assume a role for this unit's engine calls, so one tree can span accounts. |
| `download_dir = "..."` | Where modules are materialised (default `<unit>/.vizier-module`). |
| `retryable_errors = [...]` | Regexes that EXTEND the built-in transient-failure list, for a provider with its own distinctive throttling message. |

Exit codes are a contract with CI: **0** ok, **1** error, **2** plan has pending
changes, **3** verification refused. 2 mirrors `terraform plan
-detailed-exitcode`; 3 is separate so a supply-chain refusal routes to a
different reviewer than a broken plan.

## Paid modules

Free modules cost nothing but still need an account - a registry token
identifies who is downloading. No purchase, no subscription, no entitlement:
any valid token works. Modules that are not from this catalog (git, local,
the public Terraform registry, S3) need no credential at all.

Paid ones need a registry token that maps to a live entitlement. Mint one at
[/account/tokens](https://www.iac-bazaar.com/account/tokens), then:

```bash
vizier login                      # paste the token, or --token, or pipe it on stdin
vizier whoami                     # confirms it, and checks the modules in --dir
```

`whoami` answers the question worth asking before a run, not after one:

```
catalog: www.iac-bazaar.com
token:   iacb_********a4f1
account: you@example.com
plan:    team (+2 purchased)

modules in ./environments/prod
  ok       aws-vpc                      1.1.0
  ok       aws-s3-bucket                free (account only)
  BLOCKED  azure-aks                    no entitlement for this module

1 module(s) would be refused by the catalog. Buy or subscribe at:
  https://www.iac-bazaar.com/catalog/azure-aks
```

`vizier ui` shows the same thing next to the Apply button.

`run-all` runs that check itself before it starts. A 40-unit tree with one
module your plan does not cover would otherwise apply 39 units and then stop,
leaving a half-built estate; the catalog refuses either way, so the only
question is whether it refuses before or after the damage. The preflight is
skipped silently when no credential is configured, and when the catalog cannot
be reached - a network blip must not stop you deploying modules you own.

Tokens are stored per host in `~/.vizier/credentials.json` (mode 0600), because
`iac-bazaar.com` and `iac-bazaar.ae` are separate origins and a token for one is
not valid on the other. For CI, set `VIZIER_TOKEN` and write nothing to disk.
A token is sent only to the catalog it belongs to - never onto the object-storage
URL the download redirects to, which carries its own signed access token in the
query string.

### What this does and does not protect

Worth stating plainly, because it is easy to assume the opposite.

**Any check in this binary can be defeated by whoever runs it.** They can patch
it, run an older copy, or not run it at all. That is true of every client-side
check in every tool, and closing the source does not change it - it only makes
the work slightly less convenient, which is not a security property. Nothing
here is a lock; a client-side "is this person subscribed" flag would be a lock
whose key is printed on the door.

What protects the catalog is that the **server** refuses to hand over a paid
module's archive without a token that maps to a live entitlement. That decision
runs where the caller has no vote, and no version of this client can talk it into
anything. Everything in this section exists for the opposite reason: so a
customer who *is* entitled gets what they pay for, and one who is not gets a
sentence naming the fix instead of `HTTP 401`.

Verification and entitlement are **separate axes**. Turning verification off
(`--verify-mode=off`) does not make anyone entitled, and being entitled says
nothing about whether a module was verified.

## `vizier certify` - a receipt from a real sandbox

Everything above runs on your machine and proves things about configuration.
`certify` is the one command that does not: it hands a commit to a Vizier control
plane, which fetches that exact commit, checks the source, applies it in an
isolated sandbox account, verifies it, tears it down, and returns a receipt.

```bash
vizier certify --wait                 # this commit, all four stages, print the receipt
vizier certify --stage plan --wait    # a cheaper shape
vizier certify status r1787651111-4bb0 --json
```

Three things worth knowing before the first run:

**Your repository must be reachable over https.** The sandbox fetches with its
own identity, so an ssh remote cannot be used; `certify` rewrites one to https
for you. A private repository is not supported yet: the control plane has no
credential for your forge and will not ask for one.

**It refuses a dirty working tree.** The control plane fetches the COMMIT, so it
never sees an edit you have not committed. A receipt produced from a dirty tree
would describe code that is not the code in front of you, and it would look
exactly like one that does. Commit and push first, or pin one deliberately with
`--ref`.

**None of your cloud credentials are used or requested.** The sandbox belongs to
the control plane. Nothing here reads your AWS profile, your `gcloud` login or
your `ARM_*` variables, and nothing asks you to upload them.

**A leak has its own exit code.** Verification outcomes are not interchangeable,
so a pipeline can route them separately:

| exit | meaning |
|---|---|
| 0 | applied, checked and torn down |
| 3 | did not pass: a blocking security finding, a failed stage, or nothing applied |
| 4 | **leaked** - applied and the teardown did not finish. Real resources may exist |
| 1 | the command could not run: no endpoint, no token, unreachable |

Exit 4 is separate from 3 on purpose. A failed verification waits until morning;
resources nobody knows about are billing now. When it happens the receipt carries
`findOrphansBy`, which is a search that does not depend on the module having
applied any label.

The endpoint lives in `vizier.control.json` at the tree root. That file must not
contain a credential and is refused if it does; the token is stored per host by
`vizier login`, the same way the registry token is.

## `vizier admit` - a check for the Terraform you already have

Every other command here wants a `vizier.hcl` first. This one does not. It reads
the `module` blocks in ordinary `.tf` files, applies a policy your team writes,
and exits **3** if anything is refused. Nothing is applied and no cloud is
touched.

```bash
vizier admit ./environments/prod
vizier admit . --plan tfplan.json     # sees transitive modules too
vizier admit . --json                 # the full report, for a pipeline
```

Write the rules in `vizier-policy.hcl`, found by searching upward from the root,
so a monorepo keeps one at the top instead of a copy per directory:

```hcl
policy {
  # Source PREFIXES. Prefix rather than glob because the thing teams want to
  # say is "only from our org", and a glob invites mistakes saying it.
  allowed_sources = [
    "git::ssh://git@github.com/acme/",
    "iacbazaar://",
  ]

  # The revocation lever. Named here, a module stops being runnable everywhere
  # this policy reaches, whatever else allows it.
  denied_modules = ["iacbazaar://aws-legacy-vpc@1.0.0"]

  # Only these publishers count, by key name or key id.
  allowed_keys = ["acme-platform"]

  require_signed = true
  min_status     = "live_tested"   # catalog modules only

  # The check that works on an estate nobody has signed. Refuses any address
  # that can resolve to different code tomorrow: a git ref that is a branch or
  # tag rather than a commit, an archive URL with no checksum, a registry
  # version range. No catalog, no signature, no publisher relationship needed.
  require_pinned = true
}
```

`require_pinned` is worth enabling first. `min_status` only means anything for
`iacbazaar://` modules, so on a real estate it is switched off for almost
everything; pinning applies to every source. `?ref=main` is not a version, it is
a promise to run whatever that branch says at fetch time, and two runs an hour
apart can execute different code from an unchanged config. It is deliberately
weaker than a signature and honest about it: it proves the ADDRESS is immutable,
not that the bytes are trustworthy.

Everything is opt-in and the file may be absent. With no policy, admit reports
what it found, refuses nothing, and says so plainly - "0 refused" under no rules
is not an endorsement and must not be printed as one.

Two behaviours worth knowing:

- **A source it cannot read is reported, never assumed.** `source = var.thing`
  is uncheckable; under `allowed_sources` that is a refusal, because "we could
  not tell" is not "it was allowed".
- **A root that does not parse is an error**, not an empty pass. Answering
  "0 modules, nothing refused" for a file with a syntax error would look exactly
  like approval.

Add it wherever runs already happen. Worked examples are in `examples/`:
[`admit-atlantis.yaml`](examples/admit-atlantis.yaml),
[`admit-spacelift.yml`](examples/admit-spacelift.yml),
[`admit-github-actions.yml`](examples/admit-github-actions.yml). It changes
nothing about where you run and needs no credential.

Check twice, and the second time over the plan:

```bash
vizier admit .                                  # before init, cheap refusals
terraform show -json tfplan > plan.json
vizier admit . --plan plan.json                 # the full transitive set
```

The source scan sees only what the root declares. The plan sees what the root's
modules pulled in as well, so a policy that checked only the first layer would
be bypassed by a single wrapper module.

`--receipt admit.json` writes the evidence: which policy was in force (with a
digest over its bytes, so two receipts reveal whether the RULES changed and not
only the outcome), which keys were trusted, and every module's verdict with the
rule that decided it. Like the run receipt, it carries instructions for
re-checking every claim without this tool.

Exit codes: **0** admitted, **3** refused by policy, **1** vizier could not run.
3 and 1 are distinct on purpose - a policy refusal is a decision someone should
read, a broken tool is an incident, and routing both to the same place wastes
the reviewer best placed to act.

## `vizier mcp` - answering an assistant's questions about this tree

A model writing Vizier or Terragrunt HCL is working from what it memorised of a
configuration language that keeps moving, so it produces syntax that is
confident, plausible and rejected. Bridges exist that feed documentation to a
model to close that gap.

This closes a different one. It answers about **this tree**: the resolved
dependency graph, which unit's outputs feed which, which modules are proven and
by whose key, what the saved plan will destroy. None of that is in any training
corpus, and none of it can be read off the files without evaluating them.

```bash
claude mcp add vizier -- vizier mcp --dir /path/to/tree
vizier mcp --list          # what an assistant would be given, without speaking JSON-RPC at it
```

Any MCP client works: the command is `vizier mcp`, it speaks JSON-RPC on stdin
and stdout, and it takes the same global flags as everything else.

| tool | answers |
|---|---|
| `vizier_tree` | every unit, its dependency edges, execution level and proof verdict |
| `vizier_unit` | one unit: its source, what depends on **it**, and the evidence behind its verdict |
| `vizier_findings` | what stands between this tree and an apply, with the facts behind each finding |
| `vizier_plan` | the **saved** plan: what will be created, changed, replaced and destroyed |
| `vizier_hcl_reference` | the complete syntax this build accepts, generated from the parser |
| `vizier_catalog` | search the catalog for a module that exists |
| `vizier_module` | resolve a slug to the exact `source` line, version and digest |
| `vizier_verify` | re-check every unit against the catalog and the trusted keys |

**Every tool is read-only, and that is not caution.** An MCP server hands a
model callable tools, and any file the model reads can contain text aimed at the
model. A server exposing `apply` turns every README in every dependency into a
possible instruction to change infrastructure, and no confirmation step fixes
that, because the thing being confirmed was chosen by whatever the model just
read. Nothing here applies, destroys, writes state, registers a key or edits a
file. When something needs doing, the tools return the command for you to run.

The syntax reference is generated by reflecting over the type the parser
actually decodes into, so it cannot describe a block that does not exist, and a
block added to the config appears in it without anyone remembering to write it
down. Only the one-line descriptions are written by hand, and a test asserts the
two sets match exactly in both directions.

## Leases - making verification something you cannot switch off

Everything above is client-side, and that has a limit worth stating plainly: if
your threat model includes the person running the apply, a check in the binary
they invoke is a linter, not a control. They can pass `--verify-mode off`, run
an older build, or patch the check out. No licence and no amount of closed
source fixes that: the code runs on their machine, at their invitation.

A lease closes that, and not by locking state - your backend already does that.
It closes it because the lease is issued by something the operator does not run,
and only against an admission receipt showing a policy was in force and nothing
was refused:

```bash
vizier lease serve --addr 127.0.0.1:7799          # the reference server
vizier admit . --lease http://127.0.0.1:7799      # ask for one
```

```
vizier admit . --verify-mode off   ->  admits everything locally
                                   ->  receipt records 'nothing enforced'
                                   ->  the lease server refuses
                                   ->  exit 3, the pipeline stops anyway
```

The bypass that catches people is subtle: a receipt from a run where **nothing
was enforced** looks identical on the numbers to a clean one, because both say
zero refused. Only `policyDeclared` tells them apart, and the server checks it.

Refusals are distinguishable because they need different responses. `409 held`
names who holds the key and until when, and means retry. `422 admission` means
fix your modules or your policy, and waiting will not help - it exits 3 like
every other policy refusal, so it reaches whoever owns the policy rather than
whoever handles broken tools.

The key is a **hash** of your state backend address, never the address itself:
that names a bucket and a path in your account, and a lease server has no
business knowing either. It is keyed on the backend rather than the directory
because two checkouts of one repository are two directories and one piece of
infrastructure. One caveat, stated rather than discovered: the backend block
does not include the workspace, so two workspaces of one root share a key and
will wait for each other. Over-locking delays a run; under-locking corrupts
state.

The bundled server is the reference one and says so: single node, in memory,
and restarting it frees every held lease.

## Vizier Central - the same binary, for a team

Everything above is one operator on one tree, and that is a complete product for
a great many people. It stops being one the moment two people share an estate,
because three things have nowhere to live: who may do what, what this company
demands before anything runs, and what happened last Tuesday.

`vizier central` is those three things. You host it, in your network, against
your Postgres.

**It is a commercial product and is not in this build.** Vizier Local, which is
everything above, is free to download and free to use, forever. Central is licensed per team:
<https://www.iac-bazaar.com/pricing>. What follows describes what it does, so
you can tell whether you need it.

**It stores no cloud credentials and no Terraform state.** Not encrypted, not
envelope-encrypted, not "just the secret". A cloud account here is a *pointer*
to an identity you already control - a role ARN, a subscription and client id, a
service account to impersonate - and the runner federates for short-lived
credentials at run time. A full compromise of that database teaches an attacker
which role ARNs you use. That is the whole blast radius, and it is the sentence
to open a security review with.

It also never executes anything, and the direction is the design:

```
Start   -> "about to apply env X at commit Y, citing change Z"
           Central answers with the floor to enforce, or refuses.
<run>      on your machine, with your credentials. Central is not involved.
Finish  -> the outcome, and the receipt, kept verbatim.
```

Report-in, not dispatch-out. A control plane that dispatched would need a
credential for every account it deploys into, which is the one thing this
refuses to become.

### What it adds

**Roles.** viewer, operator, admin, owner. An operator applies and cannot
destroy; weakening an environment is an owner act. The refusal happens on the
server, so a client nobody controls cannot talk its way past it.

**One evidence floor per environment.** Production demands live-tested, signed
and pinned; a sandbox need not. The floor is handed to the runner at the start of
every run and **applied** there, raising any unit that demands less - and only
raising, so a unit its author made stricter keeps its own setting. Nobody has to
remember the right flags, and nobody can quietly not pass them:

```
$ vizier apply --dir envs/prod
control plane: https://vizier.example.internal - prod - run c0c57866
  floor: envs/prod: min_status -> live_tested
  floor: envs/prod: require_signed -> true
```

**Review before an apply.** Branch protection, for infrastructure: each
environment carries a count of how many people *other than the author* must
approve a change before it may be applied there. A change is a pull request
whose diff is the **plan** - a code diff tells you what the HCL says, not that
this apply replaces a database.

```bash
vizier central propose --title "Add a read replica" --head 8f2c41a --verb apply
vizier central review 58384dc6 --approve      # and it must be somebody else
vizier apply --dir envs/prod --change 58384dc6
```

Two rules make that mean something, and both are `WHERE` clauses in the
database rather than checks in a client anybody could edit:

- **The author cannot approve their own change.** Not a role check: an admin who
  raised a change still cannot pass it. Without this, four-eyes is true on the
  org chart and false in the room.
- **An approval is pinned to one commit.** Approve one, apply another, and the
  approval was theatre. It is also why a change is immutable once raised: a new
  commit is a new change, not an edit to this one.

Three more follow: an approval is spent once, so a retried pipeline cannot apply
twice on one decision; a review given on an earlier commit is shown but never
counted; and a run reporting itself as passed while also reporting refusals is
rejected rather than stored.

**History that outlives the process.** Every run from every operator, with its
receipt attached. The local console structurally cannot offer this - its history
ends when you close it.

**Certification, if a client wants to check your pipeline rather than take your
word.** `vizier certify change <id>` reads a change from Central, submits the
commit *that change pins* to the attestation service, waits, and records the
verdict back as a check:

```bash
vizier certify change 58384dc6
```

```
certifying Add a read replica at c4d8e1f0a72b
  run r-8812  (--attach r-8812 to resume watching)
  running
  succeeded
recorded check "certify" = passed on Add a read replica
```

A red verdict blocks production, and nothing new enforces that: a change
carrying a check that is not green was already unmergeable. The command holds
two credentials because they are two services - your Central token annotates the
change, the attestation token pays for the sandbox - and it refuses locally,
before anything is billed, if the change is closed, names no source, or pins
something that is not a full commit id.

A tree that uses both names both, because Central reviews and the attestation
service executes:

```json
{ "kind": "central", "endpoint": "https://vizier.example.internal",
  "attest": "https://iac-bazaar.com", "environment": "..." }
```

### Joining a tree to one

`vizier.control.json` at the tree root. It is meant to be committed - that is how
a team shares *where* the control plane is - and it **refuses to hold a token**,
because a credential in a committed file is a credential in your git history.

```json
{
  "schemaVersion": 1,
  "kind": "central",
  "endpoint": "https://vizier.example.internal",
  "environment": "<environment id, from the console>",
  "onUnreachable": "fail"
}
```

```bash
vizier login --endpoint https://vizier.example.internal   # once per machine
vizier central status
```

`onUnreachable` defaults to `fail`, which is the safe direction: an attestation
that did not happen is not an attestation that passed. `warn` runs anyway and
says the run was **not** attested, so it cannot be mistaken for one that was.

A tree with no `vizier.control.json` does none of this and makes no network call.
Running alone is a mode, not a control plane somebody has not set up yet.

## Trusting your own publisher keys

Verification ships trusting one key: the IaC Bazaar signing key, compiled into
the binary. That is the right root for catalog modules and useless for the ones
your team writes, which is most of a real estate.

Register your own:

```bash
vizier run-all plan --trusted-key ./keys/acme-platform.pub
export VIZIER_TRUSTED_KEYS=/etc/vizier/keys      # or a directory, or a path list
cp acme-platform.pub ~/.vizier/trusted-keys/     # or the default location
```

A registered key is accepted for any module whose signature it covers, and the
run receipt records **which** key verified each module, because "signed" stops
being one fact once more than one publisher is trusted.

Three properties worth knowing, because they are deliberate:

- **Keys load from local files only.** Never from the catalog, never over the
  network. A trust root fetched from the same place that serves the artifact is
  circular: whoever can rewrite the proof can rewrite the key that proves it.
- **The built-in key cannot be removed.** Registering keys only widens trust, so
  there is no attack in keeping it, and a config that could quietly narrow the
  trust root could make a run look verified against a key nobody chose.
- **A bad key file is an error, not a skip.** A key that silently fails to load
  turns "signed by a publisher I trust" into "blocked for reasons I cannot see",
  and you would go looking at the module instead of at your own config.

Widening the key set does not widen what a signature is allowed to mean: the
digest binding still applies, so a genuine signature over some other artifact
still cannot stand in as proof for this one.

## Bring your own modules

Any source Terragrunt accepts works: `git::`, `git@`, `github.com/…`, the
Terraform registry, `https://…tar.gz`, `s3::`, `gcs::`, and local paths, with
`//subdir` and `?ref=`. A git source records the RESOLVED COMMIT, not the tag you
asked for, because a tag moves.

These are not IaC Bazaar modules, so there is no signature from us to check them
against - and admitting them unconditionally would give up the only thing this
tool is for. You supply the evidence instead:

```hcl
terraform {
  source = "git::https://github.com/acme/mods.git//vpc?ref=v1.2.0"
}

verify {
  # Pin what you expect. No catalog and no signing key needed: you declare what
  # the code should be, and code that is not that does not run.
  source_sha256 = "9f2c…"

  # Or admit a whole repo without checking anything:
  # allow_unverified = ["git::https://github.com/acme/mods.git"]
  # Or, explicitly: this tree runs code from anywhere.
  # allow_any_source = true
}
```

With none of the three, `enforce` refuses and tells you all three ways forward.
An unpinned admission is marked `unpinned` in the receipt - a bypass should never
be invisible.

`--source-map OLD=NEW` repoints a whole tree at a fork or a local checkout
without editing every unit; `--source-update` re-fetches a cached copy.

## What verification actually proves

By default it proves things about the module the CATALOG published - its
verification status, its signature, its digest - and then runs whatever HCL is
in the unit directory. Those are usually the same code. Nothing checks that they
are.

`--fetch-source` closes it: the module is downloaded, hashed while it streams,
and refused if the digest is not the one the signature covers. Only then is the
`sha256` in the receipt a claim about the code that RAN, which is why the receipt
reports `sourceVerified` separately from `signatureVerified` - a receipt must not
imply a check that did not happen.

With no `verify {}` block a unit still gets a fail-closed floor: a signature this
binary verified against its pinned key, plus a status of at least
`statically_validated`. Lower it explicitly if you must (`require_signed =
false`, `min_status = "parses"`), or turn verification off with `--verify-mode off`.

Typical run across a whole environment tree:

```bash
vizier --dir environments/prod run-all apply
```

Vizier discovers every `vizier.hcl` under `--dir`, builds the dependency DAG,
checks every unit **first**, then applies in topological order - threading each
unit's outputs into its dependents' `inputs`.

## The `verify {}` block (the verification policy)

Each unit's `terraform.source` is resolved to a catalog module, and the unit is
checked against its effective `verify {}` policy (usually inherited from a parent
via `include`):

```hcl
# environments/prod/app/vizier.hcl
include "root" {
  path = find_in_parent_folders()          # inherit the shared verify {} policy
}

terraform {
  source = "iacbazaar://aws-ecs-fargate-service@2.0.0"
}

dependency "kms" {
  config_path = "../kms"                     # outputs -> dependency.kms.outputs.*
}

inputs = {
  kms_key_arn = dependency.kms.outputs.key_arn
}

verify {                                     # the verification policy
  require_signed   = true
  min_status       = "live_tested"           # statically_validated | plan_validated_mocked
                                             #   | plan_verified_real | live_tested
                                             # (aliases: validated, live-tested; unknown
                                             #  values fail closed)
  allow_unverified = []                      # explicit escape hatch, empty by default
}
```

Outcomes by `--verify-mode`:

- `enforce` (default) - a unit whose module is unsigned, unverifiable, or below
  `min_status` **blocks the run** with a precise message (which unit, which
  module, why), before any `tofu apply`.
- `warn` - prints the violation and proceeds.
- `off` - skips verification entirely (recorded in the output for honesty).

Sources that are not `iacbazaar://<slug>@<version>` modules are blocked unless
listed verbatim in `allow_unverified`.

## `vizier.lock`

The first successful check pins each verified module - status, signed flag,
`sha256` and the signature bundle itself - into a `vizier.lock` beside your tree.

**The lock is a cache, not the source of truth.** A cosign bundle signs a
DIGEST: it establishes that someone holding the key signed the artifact whose
sha256 is D. It says nothing about which slug, which version, or what
verification status that artifact reached. Those come from the catalog, so the
catalog is asked first and its answer wins.

**Fail-closed:** in `enforce`, an unreachable catalog blocks the run. Pass
`--offline` to fall back to the lock, and an entry with no signature bundle is
still refused - it would be an assertion, not evidence. A proof answered from
the lock is marked as such in the verdict line and in the receipt (`fromLock`),
so an offline run never reads as a fresh confirmation.

## Verification example

`vizier verify` reports each unit without touching `tofu`:

```
$ vizier --dir environments/prod verify
[ok]    kms - aws-kms@1.2.0 proven (live_tested, signed)
[BLOCK] app - aws-ecs-fargate-service@2.0.0 is not signed
```

In `enforce` mode that `BLOCK` aborts `run-all apply` before the cloud is
touched. Set `--verify-mode off` to see every unit report `[ok]` regardless of
proof status (useful for a dry structural check):

```
$ vizier --dir testdata/tree verify --verify-mode off
[ok] app - verify-mode=off
[ok] kms - verify-mode=off
```

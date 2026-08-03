# Examples

[`examples/repository/.fixcards`](../examples/repository/.fixcards) contains
three synthetic teaching cards:

- a frozen pnpm lockfile mismatch;
- a Rust/OpenSSL discovery failure;
- a Docker host-port collision.

They demonstrate exact/secondary/negative anchors, version and platform bounds,
validation evidence, and risk language. They are not a maintained universal fix
corpus and should not be copied into a repository without confirming its actual
toolchain and workflow.

Try the examples from the Fixcard checkout:

```bash
cargo run -q -p fixcard -- lint examples/repository/.fixcards
```

The checkout itself is the Git boundary, so the commands discover the nested
example cards only when they are copied to the checkout's `.fixcards/`. For a
contained demo, copy `examples/repository` to a temporary directory, run
`git init` there, and execute the installed `fixcard` binary inside it:

```bash
fixcard fix --explain ERR_PNPM_OUTDATED_LOCKFILE frozen-lockfile
fixcard fix --explain "address already in use" "0.0.0.0:5432"
```

# Teaching examples

`repository/` is a synthetic Git-repository-shaped example containing three
Fixcards. It contains no real incident data, secrets, or universal prescriptions.

To experiment safely:

1. copy `repository/` to a temporary directory;
2. run `git init` inside it;
3. run `fixcard lint`;
4. pass one of the anchors to `fixcard fix --explain`;
5. inspect the result with `fixcard show <id>`.

Adapt cards only after validating the resolution and constraints in your own
repository.

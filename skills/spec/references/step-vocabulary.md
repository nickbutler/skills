# Primitive step vocabulary (Layer 1)

*Loaded by the `spec` skill before any scenario is written. The rules that govern these — the two-layer model, when a task step is warranted, `@draft` — are in `SKILL.md`.*
## Primitive vocabulary (Layer 1)

The primitive vocabulary is domain-dependent. This skill ships two reference vocabularies — **browser** and **CLI**. Use the one that fits the project's interface; a single project may use both (e.g. a CLI tool with a web UI). When the project's domain fits neither (e.g. a mobile app, a message-queue consumer, an API-only service), establish a new primitive family in `GAPS.md` and get confirmation before writing any feature files.

Parameters use `{curly_braces}`.

**Browser** — locators use visible text or label; never CSS selectors, XPath, or element IDs.

| Step | Category | Notes |
|---|---|---|
| `I navigate to {url}` | Navigation | Absolute or root-relative URL |
| `I click the {text} link` | Interaction | Matches visible link text |
| `I click the {text} button` | Interaction | Matches button label |
| `I click {text}` | Interaction | Any clickable element; use typed variants above when unambiguous |
| `I fill in {field} with {value}` | Input | `{field}` is the input label or placeholder |
| `I select {option} from {field}` | Input | For `<select>` elements |
| `I check {field}` | Input | Checkbox by label |
| `I uncheck {field}` | Input | Checkbox by label |
| `I submit the form` | Input | Submits the active form |
| `I should see {text}` | Assertion | Visible text anywhere on the page |
| `I should not see {text}` | Assertion | |
| `I should be on {path}` | Assertion | URL path match |
| `the {field} field should contain {value}` | Assertion | |
| `the {field} field should be empty` | Assertion | |
| `the {text} button should be disabled` | Assertion | |
| `the {text} button should be enabled` | Assertion | |
| `I should see an error {text}` | Assertion | For inline validation messages |

**CLI** — commands are subcommand-and-flags only; path arguments go in a separate `at path "{path}"` clause. Values go in step text, not fixture names — step definitions stay generic and parameterised.

When a scenario needs to reference the per-test temp directory inside a command string or a path argument, write the literal token `{tmp}` in the feature file — e.g. `When I run command "init {tmp}/workspace"`. The step definition is responsible for substituting `{tmp}` with the actual `tmp_path` (or framework equivalent) at runtime. This keeps feature files portable across environments and free of absolute paths, while letting step text remain self-describing. Bare relative paths in non-command step text (e.g. `the directory "workspace/raw"`) are resolved against `tmp_path` directly by the step definition — no `{tmp}` prefix needed there.

| Step | Category | Notes |
|---|---|---|
| `I run command "{command}"` | Invocation | Subcommand and flags only, e.g. `"init"`, `"collect --all"` |
| `I run command "{command}" at path "{path}"` | Invocation | As above, with explicit working directory |
| `the last command should succeed` | Assertion | Exit code 0 |
| `the last command should fail` | Assertion | Non-zero exit code |
| `the last command should exit with code {code}` | Assertion | Specific exit code |
| `the last command output should contain "{text}"` | Assertion | Match against stdout/stderr |
| `the file "{path}" exists` | State | Pre-state: file present |
| `the file "{path}" does not exist` | State | Pre-state: file absent |
| `the directory "{path}" exists` | State | Pre-state: directory present |
| `the directory "{path}" does not exist` | State | Pre-state: directory absent |
| `the file "{path}" should exist` | Assertion | Post-state: file was created |
| `the file "{path}" should not exist` | Assertion | Post-state: file was not created |
| `the directory "{path}" should exist` | Assertion | Post-state: directory was created |
| `the directory "{path}" should not exist` | Assertion | Post-state: directory was not created |
| `the file "{path}" should contain "{text}"` | Assertion | File content match |

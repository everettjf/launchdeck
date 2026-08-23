# LaunchDeck 2.0 — Recipe Studio Development Plan

## Product contract

LaunchDeck 2.0 turns local objects and registered actions into typed, inspectable workflows. A workflow can be assembled as vertical blocks, generated as a draft by Apple Foundation Models, or edited on a free graph canvas. AI proposes data and plans; the validator and executor remain the only authority that can run tools.

The minimum supported system is macOS 26. On macOS 26, AI uses `SystemLanguageModel` on device. On macOS 27 and later, an explicitly cloud-eligible block may use `PrivateCloudComputeLanguageModel` when PCC is available and below quota. Deterministic workflows remain fully usable when Apple Intelligence or PCC is unavailable.

## Required deliverables

1. **Recipe Schema v2** — stable node/edge/port IDs, typed values, graph policy, v1 migration, versioned JSON import/export.
2. **Type system and execution transactions** — validation, topological execution, cancellation, dry run, receipts, rollback, and persisted undo/redo records.
3. **Vertical block editor** — searchable block library, outline assembly, drag/reorder, inspector, errors, variables, console, and keyboard commands.
4. **On-device AI blocks** — classification, extraction, summarization, rewrite, filename generation, structured generation, privacy policy, and transcript metadata.
5. **Workflow Copilot** — natural-language-to-draft using guided generation, trusted catalog resolution, assumptions, unresolved inputs, diff, and explicit acceptance.
6. **PCC** — managed entitlement, macOS 27 availability and quota checks, visible routing, reasoning level, explicit privacy permission, and local fallback.
7. **Free graph canvas** — pan/zoom, node positioning, typed connections, selection, keyboard movement, accessible alternative outline, and automatic layout.

## Non-negotiable invariants

- Models never invent executable action identifiers; every node resolves through `WorkflowNodeCatalog`.
- Models never grant their own tool or PCC permission.
- Remote execution is never silent. Every model result records `deterministic`, `onDevice`, or `privateCloudCompute`.
- File mutations run inside a transaction when the action supports undo. Partial failure triggers rollback.
- A draft never executes automatically. Validation and dry run precede every mutating run.
- Stable UUID identity is used across lists, drag sessions, graph layout, receipts, and persisted documents.
- Ordinary search and deterministic Recipe execution never wait for AI.

## Milestones and acceptance

### M1 — Schema and migration

- Decode v1 recipes and migrate them to v2 without changing step order or identifiers.
- Detect missing ports, incompatible types, duplicate IDs, cycles, unreachable nodes, missing targets, and unavailable capabilities.
- Round-trip v2 JSON with deterministic ordering.

### M2 — Execution and transactions

- Execute a valid DAG in stable topological order.
- Capture node timing, inputs, outputs, route, tool calls, errors, and undo data in a receipt.
- Cancel between nodes and during delays/model calls.
- Roll back completed reversible mutations in reverse order after failure.
- Persist the latest 50 receipts and undo eligible runs after relaunch.

### M3 — Recipe Studio

- Create a workflow from scratch in under two minutes without a mouse.
- Add/reorder/duplicate/delete blocks; edit typed configuration in an Inspector.
- Switch between Outline and Graph without changing the workflow.
- Show validation errors at workflow, node, and port level.

### M4 — Apple Intelligence

- Generate only structured results using `@Generable` or a trusted dynamic schema.
- Keep on-device sessions serial and cancellable.
- Show model availability and route in the editor and receipt.
- Preserve complete deterministic behavior when models are unavailable.

### M5 — Copilot and PCC

- Generate valid drafts for the checked-in evaluation corpus.
- Reject every unknown block/action/tool ID.
- Require explicit acceptance of draft changes.
- On macOS 27, route PCC-eligible requests only when the workflow policy allows it and PCC reports available quota.
- Fall back to on-device only when the task fits and policy permits; otherwise return an actionable error.

### M6 — Quality gates

- Unit tests: migration, graph validation, type compatibility, topological execution, rollback, routing, catalog resolution, and persistence.
- UI contract tests: vertical editor assembly and graph connection state.
- Performance: 1,000 nodes validate below 100 ms and graph layout below 250 ms on the reference machine.
- Full app tests, static analysis, universal Release build, release metadata, and launch smoke test pass.

## Delivery order

Schema → validator → executor/receipts → vertical editor → on-device AI → Copilot → PCC → graph canvas → performance and release audit.

## Implementation status

- [x] Recipe Schema v2 and lossless v1 migration
- [x] Typed ports, DAG validation, retries, cancellation, receipts, rollback, persisted undo/redo
- [x] Keyboard-accessible vertical block editor with library, inspector, variables, validation, and run console
- [x] On-device guided-generation AI blocks with availability and route visibility
- [x] Workflow Copilot with catalog-constrained drafts, assumptions, unresolved inputs, and accept/reject review
- [x] PCC entitlement, availability/quota gates, reasoning levels, per-block approval, and local-only policy
- [x] Free graph canvas with zoom, scrolling/panning, typed connection menus, node dragging, and automatic layout
- [x] Schema/editor/execution/routing/rollback/cancellation/performance tests and unsigned Release build audit
- [ ] Signed PCC build verification — Xcode currently reports that the refreshed provisioning profile for `com.everettjf.launchdeck` does not contain the granted managed entitlement

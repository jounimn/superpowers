# Testing Gotchas

**Load this reference when:** a test runs under jsdom, React Testing Library or Vitest and fails — or passes — for a reason unrelated to the code under test.

## Auth clients in one jsdom test file share a session

- **Symptom:** a test that signs in two or more backend/auth clients fails with a permission-shaped error (e.g. a row-level-security violation) even for a user who should be allowed; the same sequence passes in plain Node.
- **Cause:** a global `environment: 'jsdom'` gives the auth SDK one real, shared `localStorage`. Clients whose session key derives from the backend host alone overwrite each other's session.
- **Fix:** start those test files with `// @vitest-environment node`. Scoping environments in config instead? Confirm the option exists in the installed version's types — Vitest ignores a removed option such as `environmentMatchGlobs` without a warning.

## `render` skips Strict Mode's double effects

- **Symptom:** the suite is green, but in the browser a mount-time effect (autosave, fetch, redirect) runs twice or loops.
- **Cause:** React Testing Library's `render` doesn't wrap in `<StrictMode>` unless `reactStrictMode` is enabled, so React's development double effect invocation never runs under test.
- **Fix:** enable it with `configure({ reactStrictMode: true })`. A later `configure()` call that omits the key resets it to off, so set it in the last `configure()` call, together with any other options set there, or pass `render(ui, { reactStrictMode: true })`. Still check mount-once guards in a real browser — network and console across an idle window, no interaction. Guard by comparing the current value with the last one acted on, not with a boolean "once" ref.

## Multi-key tests on a controlled roving-tabindex widget

- **Symptom:** the first arrow-key press moves focus correctly; the second and third land on the wrong item.
- **Cause:** the active index comes from a prop and the test passes a no-op `onChange` spy, so the prop never updates — every press after the first computes from stale state.
- **Fix:** render the component inside a small stateful test wrapper that feeds `onChange`'s value back as the prop, or test one key press per render.

## `getByText(/regex/)` matches several elements

- **Symptom:** `getByText(/2024/)` throws "Found multiple elements" although the intended element renders once.
- **Cause:** the query tests each element's own text, so every element whose text contains the substring matches — a heading and an intro paragraph that both mention the year.
- **Fix:** keep each tested substring unique in the rendered copy (paraphrase the other mentions), or scope the query with `within(<region>)`.

## jest-dom matchers that were never registered

- **Symptom:** test code from a brief or plan fails before any real assertion runs: `Invalid Chai property: toBeInTheDocument` (Vitest) or `expect(...).toBeInTheDocument is not a function` (Jest).
- **Cause:** `@testing-library/jest-dom` is in `package.json`, but nothing registers it: no setup-file import (Vitest: a `setupFiles` file importing `@testing-library/jest-dom/vitest`; Jest: `setupFilesAfterEnv`, not `setupFiles`, which runs before `expect` exists) and no import in the test. Installed is not registered.
- **Fix:** before using `toBeInTheDocument`, `toHaveAttribute` and friends, check the runner's setup files — or match the assertions of an existing passing test.

## Constraint attributes on text/number inputs don't clamp values

- **Symptom:** a field declares `min`/`max`, and a value outside them still reaches state and the code that consumes it.
- **Cause:** on text and number inputs, `min`/`max`/`step`/`pattern` are validation metadata, not input filters: the browser marks the field invalid but still fires `onChange` with what was typed. Two exceptions: `type="range"` clamps to min/max during value sanitization (jsdom does too, so an out-of-range `fireEvent.change` on a range delivers the clamped value), and browsers block typing or pasting past `maxlength`, though `fireEvent.change` and programmatic `value` writes bypass it.
- **Fix:** clamp or validate in code, and test it with an event carrying a value outside the declared limits (not possible through a range input; test the clamp function directly); the attribute is not a tested boundary.

# UI Guidelines

This directory contains native Neovim UI components. Follow these conventions when adding a popup, list, preview, status component, or other custom interface.

## Principles

- Prefer native Neovim APIs over another UI dependency.
- Preserve the visual language already used by `ui.commandline`, `ui.statusline`, and `ui.lsp_list`.
- Keep the smallest correct architecture. Start with one implementation module and one highlight module; split further only when responsibilities become difficult to follow.
- Keep data collection separate from rendering. Normalize provider-specific data before passing it to the UI.
- Do not depend on private modules from installed plugins. Reproduce a useful interaction pattern instead of coupling to plugin internals.
- Respect existing user changes, options, mappings, colorschemes, and window state.

## Module Shape

- Place a component under `lua/ui/<name>/`.
- Expose `setup()` for initialization and `close()` or `disable()` when the component owns resources.
- Keep handles and transient state module-local.
- Call `setup()` explicitly from `init.lua` beside the other UI modules.
- Use a named augroup with `{ clear = true }` so reloading the configuration is safe.

Typical files:

```text
lua/ui/<name>/
  init.lua
  highlights.lua
```

## Popup Layout

- Use `nvim_create_buf(false, true)` for scratch buffers.
- Set `buftype=nofile`, `bufhidden=wipe`, and `swapfile=false`.
- Keep display buffers non-modifiable except while replacing their contents.
- Use `nvim_open_win()` with `relative="editor"` and `style="minimal"` for primary popups.
- Default to a centered popup occupying roughly 80% of the available width and height.
- Clamp all dimensions to the available editor grid.
- Recompute geometry on `VimResized`.
- Use `vim.o.winborder` when practical and fall back to `rounded`.
- For related list and preview windows, overlap and join borders so they read as one interface.
- Put a short, padded title on the upper border. Update it when mode or filter state changes.
- Use a side preview on wide screens and a stacked preview on narrow screens.
- Hide or reduce secondary panels before allowing the primary list to become unusably small.

## Window Options

- Disable unrelated furniture: `relativenumber`, `signcolumn`, and `foldcolumn` unless the component needs them.
- Decide `wrap`, `number`, and `cursorline` per window rather than inheriting global values accidentally.
- Keep the primary interactive window focusable.
- Make passive preview or decoration windows non-focusable.
- Apply window-local highlights through `winhighlight`.
- Validate every buffer and window handle before using it.

## Rendering

- Render plain buffer text, then apply styling with extmarks.
- Use one namespace per component and clear it before repainting.
- Use `hl_eol=true` for a full-width selected-row background.
- Keep primary text prominent and render paths, containers, sources, and other metadata with `Comment`-like highlights.
- Use `LineNr` for positions and standard `Diagnostic*` groups for severities.
- Truncate by display width, not byte length.
- Treat extmark columns as byte offsets.
- Keep a stable mapping from rendered lines to source items when headers or multi-line entries are present.
- Show a deliberate empty state such as `No results` rather than leaving an unexplained blank window.

## Highlights

- Define component highlight links in `highlights.lua`.
- Link to semantic colorscheme groups instead of hard-coding colors.
- Create links with `{ default = true }` so users can override them.
- Reapply highlight definitions on `ColorScheme`.
- Use component-prefixed names such as `LspListBorder` or `CommandlineTitle`.

## Lists And Search

- Prefer a normal read-only buffer when native `/`, `n`, and `N` search is sufficient.
- Do not add a prompt or fuzzy matcher unless the feature requires live filtering.
- Preserve normal `j`, `k`, `gg`, `G`, and scrolling behavior where possible.
- Use buffer-local mappings for popup actions.
- At minimum, support `<CR>` to select and `q` or `<Esc>` to close.
- Follow FFF-style open actions when useful: `<C-s>` for split and `<C-v>` for vertical split.
- Add mode-specific mappings only in the relevant UI. Do not consume normal keys globally.
- Every global mapping must use `vim.keymap.set()` with a `desc`.

## Preview

- Prefer showing the real source buffer when exact syntax and Tree-sitter highlighting are required.
- Never delete or change source-buffer options when closing a preview.
- If a copied snippet is required, retain the source filetype and do not prefix text in a way that invalidates parsing.
- Center the selected location and highlight both its line and exact range.
- Convert LSP character offsets to byte columns using the originating client's encoding.
- Clear preview extmarks when changing targets or closing the UI.
- Keep preview updates synchronized with list cursor movement.

## Async Providers

- Capture the source buffer, source window, and cursor before starting a request.
- Cancel the previous request when starting a replacement request.
- Also use a monotonically increasing generation token; cancellation alone does not prevent stale callbacks.
- Verify handles and generation state before applying an async response.
- Aggregate and deduplicate multi-client LSP responses where appropriate.
- Handle empty results, missing providers, unloaded buffers, and mixed LSP offset encodings.
- Do not use private Neovim LSP APIs.

## Selection And Cleanup

- Restore or reuse the invoking window when opening a selected item.
- Add a jumplist entry before replacing its buffer.
- Open folds and center the destination after jumping.
- Close a multi-window UI only after focus leaves all windows belonging to it.
- Explicitly close owned windows, delete owned scratch buffers, cancel requests, stop timers, clear extmarks, and remove temporary augroups.
- Never delete provider-owned or source buffers.
- Make cleanup idempotent and tolerate already-invalid handles.

## Verification

- Run `git diff --check` on changed files.
- Start the full configuration with `nvim --headless +qa`.
- Load the module with `nvim --headless -u NONE` when testing it in isolation.
- Test empty and populated states.
- Test narrow and wide layouts.
- Test opening, closing, resizing, searching, selecting, and returning through the jumplist.
- Mock asynchronous LSP responses when a real server is not available.
- Confirm Tree-sitter remains active when a preview promises syntax highlighting.

## References

- `ui.commandline` demonstrates reusable buffers, handle validation, highlight restoration, and float lifecycle.
- `ui.statusline` demonstrates semantic highlights, stable ordering, timers, and LSP event cleanup.
- `ui.lsp_list` demonstrates FFF-style joined list/preview floats, native buffer search, location previews, async LSP aggregation, and responsive layout.

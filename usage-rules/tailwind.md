# llms.txt — Project usage rules
# Served at https://daisyui.com/llms.txt
#
# This file contains usage rules for the project, including Tailwind + daisyUI guidelines.
#
## Tailwind + daisyUI Guidelines
- Always use daisyUI components as the base (e.g. `btn`, `card`, `navbar`).
- Prefer semantic and theme-specific daisyUI classes (`btn-primary`, `bg-base-100`, `text-base-content`) instead of raw Tailwind colors (`bg-red-500`).
- Use Tailwind utilities only for layout adjustments (e.g. `flex`, `grid`, `px-4`, `mt-2`).
- Never write custom CSS unless strictly required. If needed, prefer utility-first composition.
- Always structure responsive design using Tailwind’s responsive prefixes (`sm:`, `md:`, `lg:`).
- DaisyUI themes: use `data-theme` attribute or configure via plugin. Always provide a light and dark variant.
- Components:
  * Buttons: `btn`, with modifiers (`btn-primary`, `btn-outline`, `btn-sm`).
  * Cards: `card`, with `card-body` and `card-actions`.
  * Forms: combine `form-control`, `input`, `select`, etc.
- Accessibility:
  * Ensure contrast by using `*-content` classes against background.
  * Always set `aria-*` attributes for interactive components.
  * Ensure focus styles are visible (`focus:` utilities).
  * Ensure contrast ratios meet accessibility standards.

## Conflict resolution
- If multiple guidelines conflict, the daisyUI rules override Tailwind raw utilities.
- These rules override any generic code generation suggestions from the LLM.
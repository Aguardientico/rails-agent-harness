# Landing page

Static landing page with no build step: `index.html` (English), `es/index.html` (Spanish), `styles.css` and `favicon.svg`.

## Placeholders

Replace every placeholder in both `index.html` and `es/index.html` before publishing. `[EMAIL]` and `[FORMSPREE_ID]` are required: until they are filled in, the mailto: links and the contact form are broken.

| Placeholder | Value |
|---|---|
| `[EMAIL]` | Contact address used in the mailto: links (required) |
| `[FORMSPREE_ID]` | Formspree form ID for the contact form (required, or delete the `<form>` in both pages) |
| `[PRICE_SETUP]` | Price of the setup package |
| `[PRICE_WORKSHOP]` | Price of the team workshop |
| `[DURATION_SETUP]` | Typical delivery time of the setup package |
| `[DURATION_WORKSHOP]` | Length of the workshop |

Check that none are left with `grep -rn '\[[A-Z_]*\]' site`.

Once v0.1.0 is on RubyGems, remove the "install from GitHub" note under the install commands in both pages.

## Publishing

`.github/workflows/pages.yml` deploys `site/` to GitHub Pages and only runs manually (`workflow_dispatch`).

1. Fill in the placeholders above.
2. Settings > Pages > Build and deployment > Source: "GitHub Actions".
3. Run the Pages workflow from the Actions tab.

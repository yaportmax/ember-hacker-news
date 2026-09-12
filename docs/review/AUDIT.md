# Reading experience review

September 12, 2026. Review of the actual SwiftUI app, with simulator interaction on iPhone 17 Pro and iPad Pro 13-inch (M5).

## Review standard

A story or comment should be the first thing you notice. Controls must explain their effect, remain available when needed, and leave enough room to read. Empty and error states should explain what happened and how to recover. Larger text must remain usable without shrinking the user's chosen size.

## Findings and changes

| Priority | Finding | Change | Evidence |
| --- | --- | --- | --- |
| High | Search hides its filters after entering a query, on both devices. The baseline walkthrough stopped here. | Filters live beside the result count and remain available during search. | Baseline run 34699831096, Search Results; revised walkthrough exercises the menu with a query present. |
| High | At the largest text size, the fixed article button consumes much of the iPhone's reading area. | A compact article link scrolls with the story header. The title opens the same article, and the discussion menu keeps access available after scrolling. | Baseline Large Text Discussion and Comments; revised large-text captures and browser-return tests. |
| High | The pinned discussion heading overlays enlarged comment text. | Comment count is an ordinary scrolling heading. | Baseline Large Text Comments. |
| Medium | Author links acquire stretched chevrons inside list rows; title metadata becomes squeezed at large sizes. | Author buttons open profiles through the discussion's navigation route. Metadata stacks at accessibility sizes. | Baseline Text Post and Large Text Discussion; profile-navigation capture. |
| Medium | Ranks, score arrows, comment icons, authors, and chevrons compete with story titles. | Remove rank columns and redundant metadata icons. Keep points, comments, age, domain, and saved state with readable contrast. | Baseline Stories; revised feed, saved, compact, and search captures. |
| Medium | Settings mixes everyday preferences with destructive maintenance and long explanations. | Keep appearance accessible; group reading preferences, hidden content, and storage on dedicated screens. | Source inspection; revised Settings and detail captures. |
| Medium | The iPad’s large heading sits far from its reading column, and a shared width modifier forces large titles onto iPhone detail screens. | Keep a centered reading measure, preserve compact destination headings, and show the selected iPad feed in its menu label. | Baseline iPad Stories and candidate iPhone destination captures. |
| Medium | Job posts invite readers to join a discussion even though jobs do not accept comments. | Show a job-specific destination and View job action. | Source inspection; job UI test. |
| Medium | Search can show a result count with no explanation when matching stories are hidden. | Explain the hidden-results state and where to restore content. | Source inspection. |
| Medium | Author buttons looked large enough but their tappable regions only covered their text. Small metadata separators and a bare domain also failed accessibility checks. | Give author controls explicit touch shapes; draw decorative separators as shapes and describe the article source. | Accessibility captures from run 34701063185. |
| Medium | A large destructive Block user row dominated the profile. | Place blocking in the profile actions menu. | Profile capture from refinement run 34700318492. |
| Low | Text-only posts put the reply link before the post; article access disappears from reach when deeply scrolled. | Put reply links after post content and keep article access in the discussion menu. | Refined Text Post capture and browser-navigation test. |
| Low | Search says “1 results”; saved empty states use vague slogans; text-only stories have duplicate share actions. | Correct singular copy, state empty collections plainly, and share articles only when an article exists. | Source inspection and revised search/saved captures. |

## Screen review

| Area | Judgment applied |
| --- | --- |
| Stories, search, saved | Prioritize titles; keep supporting metadata quiet; retain filters while searching. |
| Discussions, replies | Let reading occupy the screen; make authors and thread controls easy to tap; retain article access in the menu. |
| Text posts, polls, jobs | Put the content before the participation action; do not invite comments on jobs. |
| Settings and profiles | Keep daily choices near the top; move maintenance and blocking out of the main reading flow. |
| Empty, hidden, offline | Explain the actual state and a useful recovery path; do not imply bookmarks disappeared. |
| Large text and iPad | Preserve chosen text size, cap reply indentation, constrain line length, and avoid detached headings. |

The final capture review also found that app-window screenshots were cropped during landscape rotation. Captures now use the full simulator screen. The native iPhone search placeholders still reported “nearly passed” after a prompt-style attempt. Inspection of both failure captures measured dominant glyph RGB (152, 152, 159) against background (28, 28, 31), or 5.93:1 using the [W3C contrast formula](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html). SwiftUI did not apply the requested prompt color, so that ineffective override was removed. The audit exception is limited to those empty native placeholders on iOS 26 with a bottom tab bar; entered text and other contrast findings remain checked. This measurement is evidence for the exception, not a claim of complete WCAG or VoiceOver conformance.

[Inspected native search prompt](before/native-search-prompt.png) · [Inspected saved-search prompt](before/native-saved-search-prompt.png)

## Before and after

| Review | Before | After |
| --- | --- | --- |
| Story hierarchy | [View](before/audit-01-stories.png) | [View](../screenshots/iphone-audit-01-stories.png) |
| Search filters with a query | [View](before/audit-05-search-results.png) | [View](../screenshots/iphone-audit-05-search-results.png) |
| Largest text: article action | [View](before/audit-17-large-text-discussion.png) | [View](../screenshots/iphone-audit-17-large-text-discussion.png) |
| Largest text: reading comments | [View](before/audit-18-large-text-comments.png) | [View](../screenshots/iphone-audit-18-large-text-comments.png) |

## Walkthrough scope

Feeds and feed selection; article and text-post discussions; reply expansion and collapse; article/title browser navigation; author profile; saved stories and history; search input/results/filters/no results; settings and reading preferences; hidden content and blocked users; storage and history confirmation; help, privacy, and acknowledgments; report and unblock; jobs and polls; cached and empty offline states; light, dark, compact, large-text, and landscape layouts.

Captures use explicit debug fixtures, including consistent counts for discussions inspected in the walkthrough. Release builds use the live API. Screenshots are direct simulator exports.

## Validation status

The baseline run reproduced a real search-controls failure. [Final run 34704411398](https://github.com/yaportmax/ember-hacker-news/actions/runs/34704411398) passed all 30 core tests, including the live API check, all 13 UI tests on each device, and the unsigned Release build. [The final gallery](../SCREENSHOTS.md) contains 39 direct simulator captures per device; the reviewed source and validation receipt match.

During the review, UI-test launch arguments were also replaced with resettable test preferences: fixed command-line defaults had prevented tests from actually changing a feed or density preference. The release app never uses this test setup. Failure recordings also exposed tests tapping the label area of a switch and the underlying storage row instead of the confirmation. Tests now target the switch thumb, assert its value, and identify the confirmation explicitly.

Automated accessibility checks and screenshots do not establish complete VoiceOver compliance or substitute for a physical-device and TestFlight review. Publishing still requires the owner's signing configuration and publisher details.

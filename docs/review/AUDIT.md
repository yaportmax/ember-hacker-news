# Reading experience review

September 12, 2026. Review of the actual SwiftUI app, with simulator interaction on iPhone 17 Pro and iPad Pro 13-inch (M5).

## Review standard

A story or comment should be the first thing you notice. Controls must explain their effect, remain available when needed, and leave enough room to read. Empty and error states should explain what happened and how to recover. Larger text must remain usable without shrinking the user's chosen size.

## Findings and changes

| Priority | Finding | Change | Evidence |
| --- | --- | --- | --- |
| High | Search hides its filters after entering a query, on both devices. The baseline walkthrough stopped here. | Filters live beside the result count and remain available during search. | Baseline run 34699831096, Search Results; revised walkthrough exercises the menu with a query present. |
| High | At the largest text size, the fixed article button consumes much of the iPhone's reading area. | A compact article link scrolls with the story header. The title opens the same article. | Baseline Large Text Discussion and Comments; revised large-text captures and browser-return tests. |
| High | The pinned discussion heading overlays enlarged comment text. | Comment count is an ordinary scrolling heading. | Baseline Large Text Comments. |
| Medium | Author links acquire stretched chevrons inside list rows; title metadata becomes squeezed at large sizes. | Author buttons open profiles through the discussion's navigation route. Metadata stacks at accessibility sizes. | Baseline Text Post and Large Text Discussion; profile-navigation capture. |
| Medium | Ranks, score arrows, comment icons, authors, and chevrons compete with story titles. | Remove rank columns and redundant metadata icons. Keep points, comments, age, domain, and saved state with readable contrast. | Baseline Stories; revised feed, saved, compact, and search captures. |
| Medium | Settings mixes everyday preferences with destructive maintenance and long explanations. | Keep appearance accessible; group reading preferences, hidden content, and storage on dedicated screens. | Source inspection; revised Settings and detail captures. |
| Medium | The iPad's large heading sits far from its centered reading column. | Use inline navigation headings in regular-width layouts. | Baseline iPad Stories; final iPad captures. |
| Medium | Job posts invite readers to join a discussion even though jobs do not accept comments. | Show a job-specific destination and View job action. | Source inspection; job UI test. |
| Medium | Search can show a result count with no explanation when matching stories are hidden. | Explain the hidden-results state and where to restore content. | Source inspection. |
| Low | Search says “1 results”; saved empty states use vague slogans; text-only stories have duplicate share actions. | Correct singular copy, state empty collections plainly, and share articles only when an article exists. | Source inspection and revised search/saved captures. |

## Walkthrough scope

Feeds and feed selection; article and text-post discussions; reply expansion and collapse; article/title browser navigation; author profile; saved stories and history; search input/results/filters/no results; settings and reading preferences; hidden content and blocked users; storage and history confirmation; help, privacy, and acknowledgments; report and unblock; jobs and polls; cached and empty offline states; light, dark, compact, large-text, and landscape layouts.

Captures use explicit debug fixtures, including consistent counts for discussions inspected in the walkthrough. Release builds use the live API. Screenshots are direct simulator exports.

## Validation status

The baseline run reproduced a real search-controls failure. This document is an active review record until the final native gate and screenshot review are recorded here.

Automated accessibility checks and screenshots do not establish complete VoiceOver compliance or substitute for a physical-device and TestFlight review. Publishing still requires the owner's signing configuration and publisher details.

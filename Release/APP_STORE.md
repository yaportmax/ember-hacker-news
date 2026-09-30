# App Store listing

Prepared September 13, 2026 after the publisher requested public release. Submission remains pending App Store Connect verification.

**Price:** Free

**Copyright:** 2026 Max Yaport

**Release:** Automatically after Apple approval

**Support URL:** https://github.com/yaportmax/ember-hacker-news/blob/main/docs/SUPPORT.md

**Privacy URL:** https://github.com/yaportmax/ember-hacker-news/blob/main/docs/PRIVACY.md

**Name:** Ember for Hacker News

**Subtitle:** Stories. Discussions. No noise.

**Primary category:** News

**Secondary category:** Productivity

**Keywords:** hn,technology,programming,startups,reader,bookmarks,comments,developer,tech,news

**Promotional text:** A quiet place for Hacker News. Read stories, follow discussions, and keep the ones you want to come back to.

## Description

Ember is a minimal Hacker News reader for iPhone and iPad.

Browse Top, New, Best, Ask HN, Show HN, and Jobs. Explore additional lists such as Best Comments, and find stories from the past day, week, month, year, or a custom date range.

Open articles directly from their titles. Read threaded discussions with replies expanded, tap to collapse conversations, and use a small next-comment arrow to move past long comments. Large discussions load ahead as you read.

Make reading feel right with separate story and comment fonts, text sizes, line spacing, row spacing, and reply indentation. A live preview shows your changes immediately.

Find an old favorite with full-text search. Save stories for later, search your bookmarks, and pick up where you left off with reading history.

• Native design with light and dark themes
• Search with date filters and relevance or recent sorting
• Collapsible comments and author profiles
• Bookmarks and reading history stored on your device
• Cached feeds when you’re offline
• Adjustable typography, density, and system text sizing
• Built-in article browser with Reader support
• No ads, analytics, or account required to read

Ember has no accounts, account creation, sign-in, voting, or posting features. External articles and full comment trees require an internet connection. Offline access covers cached feeds and saved story details, including loaded post text.

Ember is an independent app and is not affiliated with Y Combinator. Search is provided by Algolia.

## Version 1.0 notes

The first release of Ember: native feeds, threaded comments, search, bookmarks, reading history, and light and dark themes.

## Review notes

No account is needed for the app’s native reading features. The app uses the public Hacker News API and Algolia search. For testing, open Top, select a story, read automatically expanded replies, save the story with the bookmark button, and open the Saved tab. Search supports relevance/recent sorting and date ranges.

Guideline 5.1.1(v): the previous build linked to Hacker News's combined sign-in/account-creation webpage. The updated build removes the Sign in on Hacker News and Submit a story settings buttons, the Vote or reply on HN discussion action, and the Reply on Hacker News comment action. Direct HN login, registration, posting, voting, and password-recovery URLs are rejected by Ember's link handler. Ember has no native or developer-operated accounts, does not automatically create guest accounts, and does not collect credentials. There is no account-creation flow or account record to delete. Bookmarks, history, blocked users, and preferences are local to the device. Settings > Storage offers removal of bookmarks, history, and cached feeds. No demo sign-in is required.

Public community content can be reported using the original item on HN and the publisher’s configured support page. Users can block authors from a profile, a comment menu, or the report page. Blocked content is hidden locally. External articles and public source links remain ordinary browser links; Ember does not offer account actions or handle browser credentials.

The release build uses live data. Store screenshots are direct native captures of deterministic sample content; fixtures are Debug-only and are not compiled into Release. The captured controls and layout match the release application.

## Publisher fields required

Use the registered app ID 6811495244 and bundle com.maxyaport.ember. Reuse the existing review contact where present; do not invent a phone number, address, rights agreement, or EU trader status. Do not invent an age rating: complete Apple's current questionnaire for user-generated content, messaging/commenting, web access, and any relevant content categories. Review third-party data practices before submitting privacy answers. No rating or privacy label has been certified for this project.

The earlier 5.1.0 build was internal-only. The release branch exports a new App Store-eligible build with the same application code. Upload alone does not submit a review or publish the app.

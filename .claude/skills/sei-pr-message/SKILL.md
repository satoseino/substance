---
name: sei-pr-message
description: "Emit a brief GitHub PR message (title + description) in raw markdown summarizing the changes discussed in the current conversation, ready to be copied with `/copy`."
disable-model-invocation: true
---

Output a brief PR message — a short title and a short description of what changed and why — for
the user to copy (via `/copy`) and paste directly onto GitHub when opening or updating a pull request.

Answer entirely from the current conversation context — do not read any files.

The entire response is the PR message in GitHub-flavored markdown, with no prose before or after.
Do not wrap the response as a whole in a code fence (`/copy` copies it verbatim); fenced code
blocks inside the description are fine. Structure:

- Line 1: the PR title, as plain text (no `#` heading marker, no markdown formatting).
- Line 2: blank.
- Line 3 onward: the PR description — a few sentences or short bullet points on what changed and why.

Do not hard-wrap paragraphs; GitHub renders single newlines in PR descriptions as line breaks.

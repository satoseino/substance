---
name: sei-pr-comment
description: "Emit a GitHub PR review comment in raw markdown for a given finding label, ready to be copied with `/copy`."
disable-model-invocation: true
argument-hint: "<finding-label>"
arguments: [label]
---

Emit a GitHub PR review comment for the finding label `$label`, for the user to copy (via `/copy`)
and paste directly onto GitHub.

Answer entirely from the current conversation context — do not read any files.

The entire response is the comment in GitHub-flavored markdown, with no prose before or after.
Do not wrap the response as a whole in a code fence (`/copy` copies it verbatim); fenced code
blocks inside the comment are fine. Structure:

```
This is change request [$label].

<finding description and supporting detail from the current conversation context, addressed to the PR author in a constructive, direct tone>
```

Do not hard-wrap paragraphs; GitHub renders single newlines in PR comments as line breaks.

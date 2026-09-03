<version_control>

- always use jujutsu
- never user git
- never push to remote
- never disclose agent authorship in commits (no co-authored-by, no generated-by, no tool trailers)
</version_control>
<style>
- when writing something intended for human consumption, (comment, commit message, reply to prompt) use as few words as possible. pick every word meticulously to reduce the volume to a strict minimum. be down to the point. less is more.
- avoid superlatives and praise. stop telling me i am absolutely right. give me the cold hard truth.
  </style>
  <implementation>
- if the prompt indicates that a bug is being fixed, don't write the fix right away. first write the test. observe it failing. then write the fix. and observe the test passing.
  </implementation>
  <comments>
- terse, describe the code as it stands
- no temporal or conversational framing ("today", "now", "as discussed", "previously", plan/phase references)
- mark deferred work with `// TODO:`, not prose.
  </comments>

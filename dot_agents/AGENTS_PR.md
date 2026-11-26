# Pull request instructions

For Git commits made as part of a PR, follow [AGENTS_git.md](./AGENTS_git.md).

## Creating PR

- Use the template below, adapted from Ashlee M. Boyer.
- Description conversational, use ASD-STE100 (without limit on words)
- Use the following headings in this order. Omit sections that do not apply instead of adding filler.

  ```markdown
  ## Related Links

  - Link to the deploy preview, tracking issue, or user story.

  ## What

  - Summarize the changes at a high level.

  ## Why

  - Explain why the changes are helpful or necessary.

  ## How

  - Explain implementation choices that help the reviewer understand the change.
  - Link to relevant APIs, libraries, tutorials, or other implementation resources.

  ## Designs

  - Link to the relevant designs, mockups, or prototypes.
  - Include before-and-after screenshots for UI changes as PR attachments.

  ## Test Steps

  - [ ] Describe one action the reviewer can repeat.
  - [ ] Describe one expected observation.

  ### Evidence

  - Show some outputs, UI changes etc, compare between previous and current version to understand the change
  - Also, highlight how it affects end-user

  ## Other Notes

  - Describe risks, new dependencies, known issues, or follow-up work relevant to the review.
  ```

- In What, use short bullets that summarize related changes together.
- In Why, focus on the motivation and intended outcome.
- In How, explain major restructures or new abstractions that affect the review.
- In Test Steps, include prerequisites and repeatable steps that demonstrate the intended behavior.
- Keep each test step to one action or observation.
- Describe new or changed test coverage rather than listing passing test counts.
- In Other Notes, include follow-up commands in code blocks with comments that explain their purpose.

## Merging PR

- When addressing PR comments, write as a human, no jargon, just be concise about why a suggestion is accepted/rejected, without providing unnecessary details.

## PR screenshots

- Attach UI screenshots directly to the PR. Keep the images as PR attachments, not repository files or local links.

## References

These links record the sources for the rules in this file.
Consult an external reference only when this file leaves a relevant question unanswered.
Reuse reference information already read during the session.

- [Ashlee M. Boyer: An Undefeated Pull Request Template](https://ashleemboyer.com/blog/pull-request-template/)

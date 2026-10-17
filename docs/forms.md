# Forms

Forms is a default plugin (`plugins/forms`): it comes with the binary,
installed and switched on. In the admin it's **Content › Forms**.

## Building a form

- **Fields**: drag a type from the left onto the form (or click it to add it
  after the chosen field), drag the grip to reorder (or focus it and press
  the arrow keys), and click a field to edit it on the right: label, name,
  required, width (full or half), help, placeholder, choices, limits. The
  name is what the site posts and the merge tag; a new field's name follows
  its label until you edit it.
The editor's tabs: **General** (name, slug, status, the site's URLs),
**Editor** (the fields), **Admin Confirmation**, **User Confirmation**,
**Spam** and **After Submission**.

- **Admin Confirmation**: who gets each submission (to, cc, bcc), the subject,
  the message, which email field replies go to, and a from name and address
  for this form. Blank ones use Settings › Email.
- **User Confirmation**: sent to the address they typed in the email field
  you choose, with its own subject, message, reply-to and from.
- **Messages** are rich text (Tiptap) and start from boilerplate. The values
  they can use are listed beside them: drag one into the message, or click it
  in at the cursor. They're sent as HTML (answers escaped, `{{ all_fields }}`
  as a table) with a plain-text copy.
- **Spam**: the honeypot (`_hp`), a minimum time between the page loading
  (`_ts`) and the post, and a captcha: none, Cloudflare Turnstile or Google
  reCAPTCHA (v2, or v3 with a lowest score), each with its own keys.
- **After Submission**: the button label, the thank-you message, or a page to
  send them to.

Merge tags: `{{ <field name> }}`, `{{ all_fields }}`, `{{ form_name }}`,
`{{ site_name }}`, `{{ submission_id }}`, `{{ date }}` (spaces inside the
braces are optional).

Email needs Settings › Email (an SMTP server and a default from name and
address); **Send test email** there checks it.

## On the site

```
GET  /api/x/forms/definition?form=<slug>   the fields, labels, choices and spam checks to draw
POST /api/x/forms/submit?form=<slug>       a submission
```

The definition's `spam.captcha` names the provider, its site key, its
script, and the field its token is posted in (`cf-turnstile-response` or
`g-recaptcha-response`).

Post JSON (files as `{"filename", "content_type", "data": "<base64>"}`), a
urlencoded form, or `multipart/form-data` (for files; 10 MB in all). Send an
empty `_hp`, and `_ts` set to when the page loaded (ms since the epoch):

```js
const res = await fetch(`${CMS}/api/x/forms/submit?form=contact`, {
  method: "POST",
  headers: { "Content-Type": "application/json", Accept: "application/json" },
  body: JSON.stringify({ name, email, message, _hp: "", _ts: loadedAt }),
});
// 200 {"ok": true, "message": "Thanks!", "redirect": ""}
// 422 {"error": "invalid", "errors": {"email": ["isn't an email address"]}}
// 410 the form is closed; 429 too many posts from one address
```

A plain HTML `<form method="post" action="…">` works without script: it's
answered with a redirect to the thank-you page, or back to the page with
`?form=<slug>&form_status=sent` (or `error`). The site's origin must be in
Settings › General › Allowed origins (or be the public site URL) for a
browser's `fetch` to be allowed.

Uploaded files go into the media library under `Form uploads/<slug>`. Like
every media file, they're served at an address that can't be guessed, but
isn't private: don't take documents on a form that mustn't be public.

## Submissions

**Forms › Submissions** lists them newest first: unread, read, spam, by
form. Opening one marks it read and shows how its emails went. **Export CSV**
takes the current form and status; values a spreadsheet would run as a
formula are kept as text.

The routes the admin uses are the plugin's own (`/api/x/forms/forms`,
`/form`, `/submissions`, `/submission`, `/submissions.csv`, …), so the CLI
and agents can use them too, with the `forms:read` and `forms:write`
capabilities (Roles).

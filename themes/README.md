# The site's theme

A theme draws the public website from the CMS's content (docs/themes.md):
a Rails engine with a gemspec at its top level, here as `themes/<name>`.
It belongs to the install, like its data and its plugins, so everything
here except this file is ignored by git. An install has at most one; with
none the CMS is headless.

    git clone git@github.com:org/acme-theme.git themes/acme   # working on one
    CMS_THEME="https://x-access-token:TOKEN@github.com/org/acme-theme#v1.0.0"   # a Docker build (bin/fetch-theme)

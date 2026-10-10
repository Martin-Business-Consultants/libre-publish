# Installed plugins

Plugins installed into this CMS, one directory (a gem with a gemspec) each.
They belong to the install, like its data, so everything here except this
file is ignored by git.

    bin/rails "plugins:install[https://github.com/org/cms-plugin,v1.0.0]"
    bin/rails "plugins:update[cms-plugin]"     # or all, with no name
    bin/rails "plugins:remove[cms-plugin]"     # its tables stay
    bin/rails plugins:list

A Docker install lists its plugins in CMS_PLUGINS instead (docs/install.md).

The core bundles only the reference plugin, `engines/hello`; Forms and
Commerce are installed here like any other. Writing one: `docs/plugins.md`.

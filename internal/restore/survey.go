package restore

import (
	"context"
	"slices"
	"strings"

	"github.com/Martin-Business-Consultants/libre-publish/internal/store"
)

// Rails' own bookkeeping, which nobody needs told about.
var bookkeeping = []string{"schema_migrations", "ar_internal_metadata"}

// survey counts what the staged site holds and notes what won't work
// here as it did there.
func survey(ctx context.Context, db *store.DB, rep *Report) error {
	tables, err := store.Strings(ctx, db, `SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name`)
	if err != nil {
		return err
	}
	known := store.Tables()
	for _, t := range tables {
		if slices.Contains(bookkeeping, t) {
			continue
		}
		n, err := store.Count(ctx, db, `SELECT count(*) FROM `+quote(t))
		if err != nil {
			return err
		}
		if n == 0 {
			continue
		}
		rep.Tables[t] = n
		if !slices.Contains(known, t) {
			rep.Unused = append(rep.Unused, t)
		}
	}
	if len(rep.Unused) > 0 {
		rep.warn("these tables are kept but this core doesn't use them (the Rails core's, or its plugins': Commerce, Leads, …): %s", strings.Join(rep.Unused, ", "))
	}
	if rep.Secrets.RailsEncrypted, err = railsEncrypted(ctx, db); err != nil {
		return err
	}
	if len(rep.Secrets.RailsEncrypted) > 0 {
		rep.warn("values the Rails core encrypted can't be read here (%s): tokens still sign in, but webhook secrets must be rotated and keys entered again", counts(rep.Secrets.RailsEncrypted))
	}
	if rep.TwoFactorUsers, err = store.Count(ctx, db, `SELECT count(*) FROM users WHERE totp_enabled`); err != nil {
		return err
	}
	if rep.TwoFactorUsers > 0 {
		rep.warn("%d people use two-factor sign-in, which this core can't check yet: turn it off for them with `librepublish user disable-2fa --email …`", rep.TwoFactorUsers)
	}
	return nil
}

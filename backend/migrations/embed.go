// Package migrations embeds the SQL files so migrations ship inside the binary.
package migrations

import "embed"

//go:embed *.sql
var FS embed.FS

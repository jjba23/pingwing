#!/usr/bin/env bash
# pingwing - the free and open Lisp-powered notification nexus
#
# Copyright © Josep Bigorra <jjbigorra@gmail.com>
#
# pingwing is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Apply the SQL migrations under resources/migrations/sqlite to a database,
# oldest first, once each.
#
# A migration is applied when its file name is not yet in the
# `schema_migrations' table, so re-running this is safe and a database that is
# already up to date is left alone.  That is what a new migration relies on: it
# does not have to be written to survive being run twice, because it is not.
#
# Usage: scripts/migrate.sh [path/to/database.db]

set -euo pipefail

db="${1:-pingwing.db}"
# Where the project is, worked out from this script's own path so that it does
# not matter which directory the caller happened to be in.
script_dir="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
project_root="$(realpath "$script_dir/..")"
migrations_dir="$project_root/resources/migrations/sqlite"

if [ ! -d "$migrations_dir" ]; then
    echo "no migrations directory at $migrations_dir" >&2
    exit 1
fi

sqlite3 "$db" "CREATE TABLE IF NOT EXISTS schema_migrations (name TEXT PRIMARY KEY, applied_at TEXT NOT NULL DEFAULT (datetime('now')));"

for migration in "$migrations_dir"/*.sql; do
    name="$(basename "$migration")"
    applied="$(sqlite3 "$db" "SELECT COUNT(*) FROM schema_migrations WHERE name = '$name';")"
    if [ "$applied" = "0" ]; then
        echo "  applying $name"
        sqlite3 "$db" < "$migration"
        sqlite3 "$db" "INSERT INTO schema_migrations (name) VALUES ('$name');"
    else
        echo "  already applied $name"
    fi
done

echo "migrations up to date for $db"

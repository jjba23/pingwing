# pingwing - The free and open Lisp-powered notification nexus

# Copyright © Josep Bigorra <jjbigorra@gmail.com>

# pingwing is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# pingwing is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# You should have received a copy of the GNU Affero General Public License
# along with pingwing.  If not, see <https://www.gnu.org/licenses/>.

# Code:

.PHONY: test dir-install dir-uninstall dev server production-server fmt init-db compile-i18n new-i18n join-i18n init-i18n-nl init-i18n-en merge-i18n-nl merge-i18n-en

# Constants

PINGWING_DB="pingwing.db"
COPYRIGHT_HOLDERS="Josep Bigorra"
I18N_LOCATION="sys/i18n/locale"

# System details
GUIX_VERSION := $(shell guix --version)

# Logging helpers

define pingwing-log-info
	@printf "\n\033[1m[INFO] $(shell date --rfc-3339=seconds) - %s\033[0m\n" $(1)
endef

watchexec:
	watchexec -i "dist/**" -r -e scm,css,js -- "make server"


# Target to format source code files according to the style guide
# Find all .scm files and format them using 'guix style'
fmt:
	$(call pingwing-log-info,"formatting all Scheme files")
	find . -maxdepth 8 -name "*.scm" -type f -exec guix style -f {} \;

# Target to start a development server for pingwing
# Use watchexec to watch for file changes and restart the server on changes
dev:
	@-make fmt
	$(call pingwing-log-info,"starting development server for pingwing")
ifdef GUIX_VERSION
	guix shell -m manifest.scm -- make watchexec
else
	make watchexec
endif


# Target to start the pingwing server
# Start the server with the default configuration
server:
	$(call pingwing-log-info,"starting pingwing server")
	art work

# Target to start the pingwing server with production configuration
production-server:
	$(call pingwing-log-info,"starting production pingwing server")
	guix shell -m manifest.scm -- art work -c conf/production.conf


# Initialize a new database and enable WAL mode for higher concurrent writes to SQLite 3
init-db:
	$(call pingwing-log-info,"initializing a new database")
	-rm -v $(PINGWING_DB) $(PINGWING_DB)-shm $(PINGWING_DB)-wal
	guix shell -m manifest.scm -- sqlite3 pingwing.db 'PRAGMA journal_mode=WAL;'

# Development REPL
repl:
	guix shell -m manifest.scm -- guile --fresh-auto-compile -L ./lib/ -c '((@ (ares server) run-nrepl-server))'

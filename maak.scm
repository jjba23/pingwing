;;; pingwing -- The free and open Lisp-powered notification nexus

;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;; pingwing is free software: you can redistribute it and/or modify
;; it under the terms of the GNU Affero General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; pingwing is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU Affero General Public License for more details.

;; You should have received a copy of the GNU Affero General Public License
;; along with pingwing.  If not, see <https://www.gnu.org/licenses/>.

(define-module (maak)
  #:use-module (maak maak)
  #:declarative? #t)

;; ====== Maak constants ======

;; The TCP port on which the web server will listen.
(define http-port
  50077)

;; The file where the Pingwing DB is located.  
(define pingwing-db
  "pingwing.db")

(define hot-reload-file-types
  '(scm css js))

;; The Emacs Lisp script to run for publishing the manual, which is the
;; project's README: one document, so a reader has one place to look and the
;; two cannot come to say different things.
(define emacs-lisp-manual-publish-cmd
  '(progn (find-file "./README.org")
          (org-html-export-to-html)
          (message "finished publishing the PingWing manual")))

;; The SQL migrations, oldest first, as the file names sort.
(define migrations-glob
  "resources/migrations/sqlite/*.sql")

;; ====== Maak tasks ======

(define (repl)
  "Development REPL."
  (time-machine-manifest-shell '("guile -L ./lib -L ."
                                 "-c '((@ (ares server) run-nrepl-server))'")))

(define (default)
  "Default task to be run, list available tasks."
  ($ '("maak --list")))

(define (build-manual)
  "Render the project's manual -- the README -- as a single HTML page."
  (time-machine-manifest-shell (list (~ "emacs -Q --batch --eval '~s'"
                                        emacs-lisp-manual-publish-cmd))
                               #:verbose? #t))

(define (migrate)
  "Apply the SQL migrations under resources/migrations/sqlite, once each.

The runner keeps its own record of what it has applied, so this is how a
running deployment is brought up to the schema the source in front of it
expects -- and it is safe to run again."
  (time-machine-manifest-shell (list (~ "bash scripts/migrate.sh ~a"
                                        pingwing-db))
                               #:verbose? #t))

(define (fmt)
  "Format Scheme source code files according to the Guix style guide."
  ($ '("find . -maxdepth 8 -name '*.scm'" "-type f -exec guix style -f {} \\;")))

(define (hot-reload)
  "Hot-reloading developer's setup."
  (time-machine-manifest-shell (list "watchexec"
                                     "--clear"
                                     (~ "--exts ~a"
                                        (string-join (map symbol->string
                                                      hot-reload-file-types)
                                                     ","))
                                     "--on-busy-update=restart"
                                     "--shell bash"
                                     "--watch . --"
                                     "maak server")))

(define (hr)
  "Alias to hot-reloading."
  (hot-reload))

(define (dev)
  "Developer's setup."
  (hot-reload))

(define (kill-server)
  "Kill any running HTTP server in the same port."
  ($ (list (~ "fuser -k ~a/tcp || true" http-port)))
  ($ '("sleep 1")))

(define (server)
  "Target to start the pingwing server with the default configuration."
  (kill-server)
  (time-machine-manifest-shell '("art work")))

(define (production-server)
  "Target to start the pingwing server with the production configuration."
  (kill-server)
  (time-machine-manifest-shell '("art work -c conf/production.conf")))

(define (init-db)
  "Initialize a new database: the file, WAL mode, and the schema.

The database that comes out is empty and ready -- every migration under
resources/migrations/sqlite is applied to it in file order -- so this is the
first command of a new deployment.  It deletes whatever file is already there,
which is why a deployment that has data runs `maak migrate' instead."
  (delete-file-recursively pingwing-db)
  (delete-file-recursively (~ "~a-shm" pingwing-db))
  (delete-file-recursively (~ "~a-wal" pingwing-db))
  (time-machine-manifest-shell (~ "sqlite3 ~a 'PRAGMA journal_mode=WAL;'"
                                  pingwing-db))
  (migrate))

(define (import-production-env)
  "Import production env's database to local workspace via SSH/SCP"
  ($ '("scp wolk-jjba:/etc/byggsteg/job-clone/pingwing/trunk/env.scm .")))

(define (test)
  "Run the project's test suite."
  (time-machine-manifest-shell (list "guile -L ./lib -L . test/run-tests.scm")
                               #:verbose? #t))

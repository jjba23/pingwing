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

;; Where the SQL migrations live, oldest first, as the file names sort.
(define migrations-dir
  "resources/migrations/sqlite")

;; Quote TEXT the way a POSIX shell reads it back as TEXT: wrapped in single
;; quotes, where every character is literal, with a single quote of its own
;; closed, escaped and reopened.  A command that has to set a variable or pass
;; a script of its own -- the benchmark run below -- needs this, since a shell
;; is handed one string and would otherwise read the spaces as argument
;; boundaries.
(define (shell-quoted text)
  (string-append "'"
                 (apply string-append
                        (map (lambda (c)
                               (if (eqv? c #\') "'\\''"
                                   (string c)))
                             (string->list text))) "'"))

;; ====== Maak tasks ======

(define (repl)
  "Development REPL."
  (time-machine-manifest-shell '("guile -L ./lib -L ."
                                 "-c '((@ (ares server) run-nrepl-server))'")))

(define (default)
  "Default task to be run, list available tasks."
  (list-tasks))

(define (build-manual)
  "Render the project's manual -- the README -- as a single HTML page."
  (time-machine-manifest-shell (list (~ "emacs -Q --batch --eval '~s'"
                                        emacs-lisp-manual-publish-cmd))
                               #:verbose? #t))

(define (migrate)
  "Bring the database up to the schema the source in front of it expects.

Mutastructura does the work: it keeps its own ledger of which migration has
run, applies the rest oldest first, and runs each one in a transaction, so a
migration that fails leaves the database as it was.  Running this again is
safe -- the migrations already recorded are skipped."
  (time-machine-manifest-shell (list (~
                                      "mutastructura --database sqlite3 --connection ~a --migrations ~a"
                                      pingwing-db migrations-dir))
                               #:verbose? #t))

(define (fmt)
  "Format Scheme source code files according to the Guix style guide."
  (run (list "find" "." "-maxdepth" "8" "-name" "*.scm" "-type" "f"
             "-exec" "guix" "style" "-f" "{}" ";")
       #:verbose? #t))

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
  (run (list "sleep" "1")))

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

The database that comes out is empty and ready, every migration applied to it
in file order, so this is the first command of a new deployment.  It deletes
whatever file is already there, which is why a deployment that has data runs
`maak migrate' instead."
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
  "Run the project's test suite with Veritas.

The runner scans ./test for suites and loads each spec as a module, which is
why the specs under test/veritas/unit are named `(veritas unit ...)': that is
the name the runner derives from where they sit, and `-L ./test' is what lets
Guile resolve it."
  (time-machine-manifest-shell (list "guile -L ./lib -L . -L ./test"
                                "-c '(begin (use-modules (veritas runner)) (run-tests))'")
                               #:verbose? #t))

(define (test-benchmark)
  "Run the project's benchmarks with Veritas.

The benchmarks live under test/veritas/benchmark, the second category the same
runner understands; naming it here is what makes them run, since an ordinary
`maak test' looks for unit specs only.

The run is handed to `sh -c' rather than passed as arguments: the type of run
is set through the environment, and a Guix shell runs the program it is given
without a shell in between, so `VERITAS_TEST_TYPE=benchmark' would be read as
the name of a program."
  (time-machine-manifest-shell (list "sh -c"
                                     (shell-quoted
                                      "VERITAS_TEST_TYPE=benchmark guile -L ./lib -L . -L ./test -c '(begin (use-modules (veritas runner)) (run-tests))'"))
                               #:verbose? #t))

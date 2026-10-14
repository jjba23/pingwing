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

;;; What one task costs, measured rather than assumed.
;;;
;;; Two things a sweep does per task are timed here: turning a body into what
;;; SMTP accepts and building the message around it, and reading a batch back
;;; out of SQLite through kracht's builders and bound parameters.  Both use
;;; inputs the size a real notification has -- a few kilobytes of text with
;;; accents and links in it -- since a benchmark on a subject line measures
;;; nothing that ever happens.
;;;
;;; These are benchmarks, not tests: they assert nothing, and `maak
;;; test-benchmark' is what runs them (the unit run does not).

(define-module (veritas benchmark encoding-benchmark)
  #:use-module (veritas veritas)
  #:use-module (srfi srfi-1)
  #:use-module (ice-9 format)
  #:use-module (ice-9 ftw)
  #:use-module (kracht sql)
  #:use-module (pingwing mail)
  #:use-module (pingwing sqlite util)
  #:use-module (pingwing sqlite task)
  #:use-module (pingwing domain task)
  #:export (spec))

;;; ====== the inputs ======

;; A body of the size a notification has: a paragraph, a link, an accented name
;; and a handful of lines, repeated enough to be a few kilobytes.
(define letter-body
  (apply string-append
         (make-list 40
                    (string-append
                     "Dear Josep,\n"
                     "The résumé you uploaded is ready to read:\n"
                     "https://lucidplan.example.org/x/ticket/12\n"
                     "Kind regards,\nPingwing\n\n"))))

(define letter-html
  (string-append "<html><body><p>Dear Josep,</p><p>"
                 (apply string-append (make-list 40 "<p>résumé</p>"))
                 "</body></html>"))

(define non-ascii-subject "Nieuwe opmerking van Jösef over „resumé” — bekijk het")

;;; ====== the database a batch is read from ======

(define migrations-directory "resources/migrations/sqlite")

(define bench-database
  (string-append (or (getenv "TMPDIR") "/tmp")
                 "/pingwing-encoding-benchmark.db"))

(define (delete-if-present path)
  (when (file-exists? path)
    (delete-file path)))

(define (apply-schema!)
  (for-each delete-if-present
            (list bench-database
                  (string-append bench-database "-wal")
                  (string-append bench-database "-shm")))
  (for-each (lambda (migration)
              (let ((status (system (format #f "sqlite3 ~s < ~s"
                                            bench-database migration))))
                (unless (zero? status)
                  (error "could not apply a pingwing migration"
                         migration status))))
            (sort (map (lambda (name)
                         (string-append migrations-directory "/" name))
                       (filter (lambda (name) (string-suffix? ".sql" name))
                               (scandir migrations-directory)))
                  string<?)))

(apply-schema!)
(database-path bench-database)

(define repository (make-sqlite-task-repository))

;; A queue with a sweep's worth of work in it, which is what the batch reading
;; below is timed against.
(define (queue-row n)
  `((id . ,(format #f "bench-~a" n))
    (task-status . "pending")
    (task-type . "send-email")
    (template . "lucidplan-new-ticket")
    (template-vars . "{\"ticket-human-id\":12,\"ticket-title\":\"Fix the SMTP retry\"}")
    (sender-name . "Lucidplan")
    (sender-address . "noreply@example.org")
    (subject . ,non-ascii-subject)
    (recipients . "[{\"name\":\"Josep\",\"address\":\"j@x.y\"}]")
    (created-at . ,n)
    (attempts . 0)
    (last-error . "")))

(define (fill-queue! count)
  (for-each (lambda (n) (insert-task repository (queue-row n)))
            (iota count)))

(fill-queue! 500)

;;; ====== the benchmarks ======

(define encoding-benchmark
  (benchmark #:name "quoted-printable: a notification-sized body"
             #:runs 5
             #:thunk (lambda () (quoted-printable-encode letter-body))))

(define header-benchmark
  (benchmark #:name "rfc2047: a non-ASCII subject"
             #:runs 5
             #:thunk (lambda () (rfc2047-encode non-ascii-subject))))

(define message-benchmark
  (benchmark #:name "build-mail-message: the whole message, both parts"
             #:runs 5
             #:thunk (lambda ()
                       (build-mail-message #:id "bench-id"
                                           #:from-name "Lucidplan"
                                           #:from-address "noreply@example.org"
                                           #:to-name "Josep"
                                           #:to-address "j@x.y"
                                           #:subject non-ascii-subject
                                           #:body letter-body
                                           #:body-html letter-html))))

(define select-benchmark
  (benchmark #:name "kracht: building the batch reading"
             #:runs 5
             #:thunk (lambda ()
                       (sql-select "tasks"
                                   #:columns '(id task-status)
                                   #:where '((task-status . "pending"))
                                   #:order-by '((created-at asc))
                                   #:limit 16))))

(define batch-benchmark
  (benchmark #:name "sqlite: reading a sweep's batch of 16"
             #:runs 5
             #:thunk (lambda () (get-pending-tasks repository 16))))

(define claim-benchmark
  (benchmark #:name "sqlite: claiming tasks, 200 of them"
             #:runs 3
             #:thunk (lambda ()
                       ;; The claims are undone between runs by putting the rows
                       ;; back, so each run claims the same tasks rather than
                       ;; finding nothing left to take.
                       (for-each (lambda (task)
                                   (claim-task-by-id repository (assq-ref task 'id)))
                                 (get-pending-tasks repository 200))
                       (for-each (lambda (n)
                                   (update-task-by-id
                                    repository (format #f "bench-~a" n)
                                    '((task-status . "pending"))))
                                 (iota 200)))))

(define (spec)
  (veritas-run encoding-benchmark
               header-benchmark
               message-benchmark
               select-benchmark
               batch-benchmark
               claim-benchmark))

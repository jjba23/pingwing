;; pingwing - the free and open Lisp-powered notification nexus
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; The repository against a real SQLite file.
;;;
;;; A repository is a thin translation of Scheme values into statements, and
;;; the two things worth pinning down about that translation are the ones a
;;; unit test of the string alone cannot see: that what a caller stores is
;;; exactly what a caller reads back, and that a value which looks like SQL is
;;; still just a value.  So the schema here is the project's own migrations --
;;; applied by sqlite3 to a file of our own in the temporary directory -- and
;;; every reading below is taken through the same repository the server and the
;;; queue worker use.
;;;
;;; The database is made once, while this file loads, and the readings are taken
;;; while it loads too: what the assertions compare is then deterministic, and
;;; each scenario works on rows of its own, so the order and the shuffling that
;;; veritas applies cannot change an answer.

(define-module (veritas unit task-repository-spec)
  #:use-module (veritas veritas)
  #:use-module (srfi srfi-1)
  #:use-module (ice-9 format)
  #:use-module (ice-9 ftw)
  #:use-module (ice-9 time)
  #:use-module (pingwing sqlite util)
  #:use-module (pingwing sqlite task)
  #:use-module (pingwing domain task)
  #:export (spec))

;;; ====== the database the readings are taken from ======

(define migrations-directory
  "resources/migrations/sqlite")

(define spec-database
  (string-append (or (getenv "TMPDIR") "/tmp")
                 "/pingwing-task-repository-spec.db"))

(define (sql-file? name)
  (string-suffix? ".sql" name))

(define (migration-files)
  "The migrations, oldest first, the way their file names sort."
  (sort (map (lambda (name)
               (string-append migrations-directory "/" name))
             (filter sql-file?
                     (scandir migrations-directory))) string<?))

(define (delete-if-present path)
  (when (file-exists? path)
    (delete-file path)))

(define (apply-schema!)
  "Build SPEC-DATABASE from the project's migrations, through sqlite3.

Reading the schema from the migration files rather than restating it here is
what makes these tests about the database the deployment actually has: a
migration that a repository disagrees with fails a reading below, rather than
both drifting together."
  (for-each delete-if-present
            (list spec-database
                  (string-append spec-database "-wal")
                  (string-append spec-database "-shm")))
  (for-each (lambda (migration)
              (let ((status (system (format #f "sqlite3 ~s < ~s" spec-database
                                            migration))))
                (unless (zero? status)
                  (error "could not apply a pingwing migration" migration
                         status))))
            (migration-files)))

(apply-schema!)

;; The file this repository talks to, for the rest of this process.
(database-path spec-database)

(define repository
  (make-sqlite-task-repository))

;;; ====== the rows ======
;;;
;;; A task as a caller inserts one: the fields the API requires, and nothing
;;; invented.  Every scenario below names its own ids so that the order the
;;; tests run in cannot matter.

(define* (task #:key id
               (status "pending")
               (created-at 1)
               (attempts 0)
               (subject "a subject")
               (template "password-reset")
               (updated-at #f)
               (last-error ""))
  `((id unquote id)
    (task-status unquote status)
    (task-type . "send-email")
    (template unquote template)
    (template-vars . "{\"user\":\"joe@x.y\"}")
    (sender-name . "No Reply")
    (sender-address . "n@x.y")
    (subject unquote subject)
    (recipients . "[{\"name\":\"Joe\",\"address\":\"j@x.y\"}]")
    (created-at unquote created-at)
    ,@(if updated-at
          `((updated-at unquote updated-at))
          '())
    (attempts unquote attempts)
    (last-error unquote last-error)))

(define (insert-all! tasks)
  (for-each (lambda (t)
              (insert-task repository t)) tasks))

;;; ====== reading the queue ======

;; Three pending tasks, queued out of order on purpose: the queue answers by
;; when a task was created, whatever order it was handed them in.
(define queue-rows
  (list (task #:id "queue-middle"
              #:created-at 200)
        (task #:id "queue-oldest"
              #:created-at 100)
        (task #:id "queue-newest"
              #:created-at 300)))

(insert-all! queue-rows)

(define next-pending
  (get-next-pending-task repository))
(define pending-batch
  (get-pending-tasks repository 2))
(define pending-over-limit
  (get-pending-tasks repository 10))
(define recent
  (get-recent-tasks repository 3))

(define reading-suite
  (suite "reading the queue"
         (test "the next task is the oldest pending one"
               (assert-equal #:name
                             "a queue answers in the order it was filled"
                             #:expect "queue-oldest"
                             #:got (assq-ref next-pending
                                             'id)))
         (test "a batch is the oldest first and as long as it was asked for"
               (assert-equal #:name
                "a sweep takes the batch it asked for, oldest first"
                #:expect '("queue-oldest" "queue-middle")
                #:got (map (lambda (t)
                             (assq-ref t
                                       'id)) pending-batch))
               (assert-equal #:name
                "a batch never carries a column the row does not have"
                #:expect (list "queue-oldest" "queue-middle" "queue-newest")
                #:got (map (lambda (t)
                             (assq-ref t
                                       'id)) pending-over-limit)))
         (test
          "the list an operator reads carries the metadata and no secrets"
          (assert-equal #:name
           "the newest first, and only the columns an operator needs"
           #:expect '("queue-newest" "queue-middle" "queue-oldest")
           #:got (map (lambda (t)
                        (assq-ref t
                                  'id)) recent))
          (assert-false (any (lambda (t)
                               (or (assq-ref t
                                             'template-vars)
                                   (assq-ref t
                                             'recipients))) recent)
                        #:name
                        "a reset link must not be on the way to a browser"))))

;;; ====== what a value is, and is not ======
;;;
;;; The statement a repository builds is text; the values travel beside it and
;;; are bound by SQLite.  The readings below are the proof of that: a value
;;; with an apostrophe in it, and a value that spells out a statement of its
;;; own, both come back exactly as they went in, and the table is still there.

(define hostile-subject
  "O'Brien'); DROP TABLE tasks; -- \"quoted\" & <b>bold</b>")

(define (row-of id)
  "The task ID, read the way the API reads one."
  (car (filter (lambda (t)
                 (equal? (assq-ref t
                                   'id) id))
               (get-recent-tasks repository 50))))

(insert-task repository
             (task #:id "awkward"
                   #:created-at 400
                   #:subject hostile-subject))

(define awkward
  (row-of "awkward"))

(define binding-suite
  (suite "binding, not splicing"
         (test "a subject with an apostrophe in it round-trips unchanged"
               (assert-equal #:name
                             "O'Brien is a name, not the end of a literal"
                             #:expect hostile-subject
                             #:got (assq-ref awkward
                                             'subject)))
         (test "a value that spells out SQL changes nothing"
               (assert-equal #:name "the table the value named is still there"
                             #:expect 4
                             #:got (length (get-pending-tasks repository 10))))))

;;; ====== claiming ======

(define (status-of id)
  "The status of ID, read the way the API reads a task."
  (let ((row (row-of id)))
    (and row
         (assq-ref row
                   'task-status))))

(insert-all! (list (task #:id "claim-me"
                         #:created-at 500)))

(claim-task-by-id repository "claim-me")

(define pending-ids-after-claim
  (map (lambda (t)
         (assq-ref t
                   'id))
       (get-pending-tasks repository 10)))

;; A second claim of a row that is no longer pending must leave it as it is,
;; and the row it leaves must still say processing rather than being put back
;; in the queue by a claim that lost.
(claim-task-by-id repository "claim-me")

(define claiming-suite
  (suite "claiming"
         (test "a claimed task is no longer pending"
               (assert-false (member "claim-me" pending-ids-after-claim)
                             #:name "claiming takes the task out of the queue")
               (assert-equal #:name "and the row says it is being processed"
                             #:expect "processing"
                             #:got (status-of "claim-me")))
         (test "claiming an already claimed task changes nothing"
               (assert-equal #:name "a task another sweep took is left alone"
                             #:expect "processing"
                             #:got (status-of "claim-me")))))

;;; ====== a worker that stopped ======
;;;
;;; A task left processing by a worker that never came back is put in the queue
;;; again -- but only once it is older than the staleness the caller names.  A
;;; task being worked on right now is not taken away from it.

;; One task abandoned long ago, and one a worker is in the middle of now.  The
;; two differ only in when their row was last written, which is the whole of
;; what the sweep reads: a day is longer than the one and not the other, so the
;; threshold is the one thing deciding their fate.
(insert-all! (list (task #:id "stale"
                         #:status "processing"
                         #:created-at 600
                         #:updated-at 60)
                   (task #:id "fresh"
                         #:status "processing"
                         #:created-at 700
                         #:updated-at (current-time))))

(requeue-stale-processing-tasks repository
                                (* 24 60 60))

(define stale-suite
  (suite "a worker that stopped"
         (test "a task old enough to be abandoned goes back in the queue"
               (assert-equal #:name
                "a processing task older than the threshold is pending again"
                #:expect "pending"
                #:got (status-of "stale")))
         (test "a task a worker is still on is not taken away from it"
               (assert-equal #:name
                "a processing task newer than the threshold is left alone"
                #:expect "processing"
                #:got (status-of "fresh")))
         (test "the claim of a task in flight is not undone by the sweep"
               (assert-equal #:name
                "a claim written a moment ago is newer than the threshold"
                #:expect "processing"
                #:got (status-of "claim-me")))))

;;; ====== updating and deleting ======

(insert-all! (list (task #:id "updatable"
                         #:created-at 800)))

;; The row is updated the way the worker updates one: the status is written as
;; the symbol its own source spells (`complete', not `"complete"'), and the
;; reading below is what says such a value reaches the column as text.
(update-task-by-id repository "updatable"
                   `((task-status . complete) (attempts . 2)
                     (last-error . "")
                     (updated-at . 900)))

(define updated
  (car (filter (lambda (t)
                 (equal? (assq-ref t
                                   'id) "updatable"))
               (get-recent-tasks repository 50))))

(delete-task-by-id repository "updatable")

(define updating-suite
  (suite "updating and deleting"
         (test "an update writes the columns it names"
               (assert-equal #:name
                "the status and the attempt count are what was written"
                #:expect '("complete" 2)
                #:got (list (assq-ref updated
                                      'task-status)
                            (assq-ref updated
                                      'attempts))))
         (test "a deleted task is gone"
               (assert-false (any (lambda (t)
                                    (equal? (assq-ref t
                                                      'id) "updatable"))
                                  (get-recent-tasks repository 50))
                             #:name
                             "nothing answers for a task that was deleted"))))

(define (spec)
  (veritas-run reading-suite binding-suite claiming-suite stale-suite
               updating-suite))
